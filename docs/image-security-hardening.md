# Container Image Security Hardening: 이미지 경량화 + 취약점 검사 + Private Registry 강제

## 1. 왜 (Why) - 배경 및 필요성

### 문제 정의
컨테이너 이미지는 OS, 런타임, 애플리케이션 의존성이 혼합된 아티팩트로, 공급 경로 전체에서 보안 위험에 노출되어 있습니다.

**주요 문제점:**
- 표준 베이스 이미지: 수백 개의 OS 패키지 + 알려진 CVE 포함
- 불필요한 도구: Shell, Package Manager, 디버그 도구가 Post-exploitation 악용 경로 제공
- 공용 레지스트리: Docker Hub 등에서 이미지 변조 여부 검증 불가
- 무결성 검증 부재: 이미지 서명 및 정책 기반 통제 미흡

### NIST SP 800-190 기준
이 구현은 **NIST Special Publication 800-190: Application Container Security** 가이드를 따릅니다:
- 4.1: 베이스 이미지 스캔 및 최소화
- 4.2: 공급 경로 무결성 검증
- 4.3: 이미지 레지스트리 보안
- 4.5: 런타임 보안

### 이슈 배경
- **Issue #35**: Pod 보안: Container Image 취약점 탐지
  - CI/CD 자동 스캔 (Trivy)
  - Critical/High 취약점 감지 시 배포 차단
  
- **Issue #50**: Container Image 경량화 및 Private Registry 관리
  - Distroless/Alpine 기반 이미지 사용
  - ECR Private Registry 강제
  - Kyverno/OPA Gatekeeper 정책

---

## 2. 무엇 (What) - 구현된 컴포넌트

### 2.1 취약점 검사 3중 방어 (Defense in Depth)

#### A. Trivy CI/CD 자동 스캔
**파일**: `.github/workflows/container-image-scan.yml`

```yaml
단계:
1. manifests/**에서 컨테이너 이미지 자동 추출 (list_manifest_images.py)
2. 각 이미지별 Trivy 스캔 실행 (매트릭스 병렬 처리)
3. 스캔 결과:
   - Table 형식: 사람이 읽기 쉬운 보고서
   - JSON 형식: 자동화 도구 연동
   - SARIF 형식: GitHub Security 탭에 자동 업로드
4. Critical/High 취약점 발견 시 빌드 실패 (fail-fast: false)
5. 예외 관리: .trivyignore에 CVE 기입 (보안팀 승인 필수)
```

**동작**:
- Pull Request: PR 생성 시 자동 스캔
- Push: main 브랜치 커밋 시 자동 스캔
- 스케줄: 매주 월요일 02:00 UTC (정기 감시)

#### B. Amazon Inspector v2 지속 모니터링
**파일**: `modules/ecr/main.tf`

```hcl
1. Inspector v2 활성화 (aws_inspector2_enabler)
2. ECR 레지스트리 스캔 설정:
   - scan_type: ENHANCED (고급 스캔)
   - scan_frequency: CONTINUOUS_SCAN (지속 모니터링)
3. 이미지 푸시 후:
   - ECR scan_on_push: 자동 스캔
   - Inspector v2: 새 CVE 발견 시 지속 감지
4. EventBridge + SNS 알림:
   - CRITICAL/HIGH 취약점 발견 → SNS 즉시 알림
```

#### C. ECR 이미지 보호
```hcl
- KMS 암호화 (at rest + 자동 로테이션)
- IMMUTABLE 태그: 푸시 후 태그 덮어쓰기 방지
- 라이프사이클 정책:
  - 태그 없는 이미지 7일 후 자동 삭제
  - 최근 10개 이미지만 유지
```

### 2.2 Private Registry 강제 (Kyverno 정책)

**파일**: `manifests/base/kyverno/`

#### 01-require-registry.yaml
```yaml
정책: ECR Private Registry만 허용
- Pod 생성 시 이미지 출처 검증
- Docker Hub, quay.io 등 공용 레지스트리 거부
- 패턴: *.dkr.ecr.*.amazonaws.com/* 만 허용
- 적용 범위: Pod, Deployment, StatefulSet, DaemonSet 등
```

#### 02-require-security-context.yaml
```yaml
정책: 컨테이너 보안 컨텍스트 강제
- runAsNonRoot: true (루트 사용자 금지)
- readOnlyRootFilesystem: true (읽기 전용 파일시스템)
- allowPrivilegeEscalation: false (권한 상향 금지)
- capabilities.drop: ALL (모든 Linux capabilities 제거)
```

#### 03-mutate-default-securitycontext.yaml
```yaml
정책: 보안 설정 자동 주입 (mutate)
- Pod 수준:
  - runAsUser: 65534 (nobody 사용자)
  - fsGroup: 65534
  - seccompProfile: RuntimeDefault
- Container 수준:
  - readOnlyRootFilesystem: true
  - allowPrivilegeEscalation: false
  - capabilities.drop: ALL
- 볼륨: /tmp용 emptyDir 자동 추가
```

### 2.3 워크로드 보안 강화

**파일**: `manifests/base/{web,api,db}/`

#### SecurityContext 개선
```yaml
Pod 수준:
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    runAsGroup: 65534
    fsGroup: 65534
    seccompProfile:
      type: RuntimeDefault

Container 수준:
  securityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop: [ALL]

리소스 요청/제한:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 256Mi
```

#### 볼륨 마운트 (읽기 전용 파일시스템 지원)
```yaml
web (nginx):
  - /var/cache/nginx (emptyDir)
  - /var/run (emptyDir)
  - /tmp (emptyDir)

api:
  - /tmp (emptyDir)

db (redis):
  - /data (PersistentVolume - 데이터 저장)
```

### 2.4 네트워크 격리 (NetworkPolicy)

**파일**: `manifests/base/network-policies/`

```yaml
default-deny.yaml:
  - 모든 Pod 간 트래픽 기본 거부
  
allow-dns.yaml:
  - kube-system 네임스페이스의 DNS(53/UDP) 접근 허용
  - 모든 Pod이 필요로 하는 기본 요청
  
allow-ingress.yaml:
  - web Pod에 외부 트래픽(80/TCP) 수신 허용
  
allow-db.yaml:
  - db Pod(Redis)에 api Pod만 접근 허용(6379/TCP)
  - 마이크로 세그멘테이션: API 계층만 데이터베이스 접근
```

---

## 3. 어떻게 (How) - 실습 과정

### 3.1 취약점 탐지 (Vulnerability Detection)

#### Step 1: Trivy CI/CD 스캔 확인

**시나리오**: PR을 생성하여 CI/CD 스캔 동작 확인

```bash
# 1. 브랜치 생성 및 이미지 변경
git checkout -b test/vulnerable-image

# 2. manifests/base/web/deployment.yaml 수정 (의도적으로 취약한 이미지)
# 변경 전: image: nginx:1.27.5
# 변경 후: image: nginx:1.19.0  (오래되고 취약점 많음)

# 3. 변경사항 커밋
git add manifests/base/web/deployment.yaml
git commit -m "test: vulnerable nginx image"
git push origin test/vulnerable-image

# 4. GitHub에서 PR 생성 → Actions 탭에서 container-image-scan 워크플로우 확인
```

**예상 결과**:
- ✅ GitHub Actions에서 `container-image-scan` 워크플로우 실행
- ❌ nginx:1.19.0에서 CRITICAL/HIGH 취약점 발견 → 워크플로우 실패
- 📋 Scan 결과 아티팩트 생성:
  - `scan_result_nginx_1.19.0.table`
  - `scan_result_nginx_1.19.0.json`
  - `scan_result_nginx_1.19.0.sarif`
- 🔒 GitHub Security 탭에 취약점 자동 업로드

#### Step 2: Amazon Inspector v2 모니터링

**시나리오**: ECR에 푸시된 이미지의 지속적 스캔 확인

```bash
# 1. AWS 콘솔 접속 → Inspector 서비스
# 2. Findings 탭에서 ECR 스캔 결과 확인
```

**확인 사항**:
- 📊 Repository별 이미지 스캔 상태
- 🚨 Critical/High 취약점 목록
- 📅 스캔 시간 및 업데이트 주기 (Continuous)
- 🔔 SNS 알림 주제에 통지 발송 확인

#### Step 3: .trivyignore로 예외 관리

```bash
# 1. 부득이하게 취약점을 허용해야 하는 경우
# .trivyignore 파일에 추가:

cat >> .trivyignore <<'EOF'
# nginx:1.19.0의 CVE-2021-12345 예외 (2024-12-31까지)
# 사유: 보안 패치 대기 중
CVE-2021-12345
EOF

# 2. 커밋 전 보안팀 리뷰 필수 (코멘트: @security-team)
git add .trivyignore
git commit -m "chore: add CVE exception for nginx (ref: #XXX)"
```

### 3.2 배포 및 정책 적용 (Deployment & Policy Application)

#### Step 1: Kyverno 정책 배포

**시나리오**: Kyverno 정책이 Private Registry 강제

```bash
# 1. 클러스터에 Kyverno 설치 (이미 helm으로 설치된 경우)
# modules/k8s-base/main.tf의 Kyverno Helm chart 확인

# 2. 정책 배포
kubectl apply -k manifests/base/kyverno/

# 3. 정책 확인
kubectl get clusterpolicies
# 출력:
# NAME                          VALIDATIONACTION
# require-private-registry      enforce
# require-security-context      enforce
# add-default-securitycontext   audit
```

#### Step 2: 정책 위반 테스트

```bash
# 테스트 1: Public 이미지로 Pod 생성 시도 (실패해야 함)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-public-image
spec:
  containers:
  - name: nginx
    image: nginx:latest  # Public Docker Hub 이미지
EOF

# 예상 결과:
# Error from server: error when creating "": admission webhook "validate.kyverno.io" denied the request:
# Private ECR registry만 허용됩니다.
```

```bash
# 테스트 2: ECR 이미지로 Pod 생성 (성공해야 함)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-ecr-image
spec:
  containers:
  - name: nginx
    image: 123456789.dkr.ecr.ap-northeast-2.amazonaws.com/nginx:1.27.5
EOF

# 예상 결과:
# pod/test-ecr-image created (성공)
```

#### Step 3: 워크로드 업데이트

```bash
# 1. 현재 워크로드 상태 확인
kubectl get pods -n default
# 기존 Pod들은 Kyverno 정책 변경 전이므로 존재

# 2. 새로운 보안 설정으로 Deployment 업데이트
kubectl set image deployment/web web=123456789.dkr.ecr.ap-northeast-2.amazonaws.com/nginx:1.27.5

# 3. Deployment 롤아웃 상태 확인
kubectl rollout status deployment/web -n default

# 4. Pod SecurityContext 확인
kubectl describe pod -l app.kubernetes.io/name=web -n default
# 확인 사항:
# - Running as User UID: 65534 (nobody)
# - Read-only Filesystem: true
# - Capabilities: drop=ALL
```

#### Step 4: NetworkPolicy 적용

```bash
# 1. NetworkPolicy 배포
kubectl apply -k manifests/base/network-policies/

# 2. 정책 확인
kubectl get networkpolicies -n default
# 출력:
# NAME                    POD-SELECTOR                     AGE
# default-deny-all        <none>                           5s
# allow-dns               <none>                           5s
# allow-web-ingress       app.kubernetes.io/name=web       5s
# allow-api-to-db         app.kubernetes.io/name=db        5s
```

### 3.3 적용 확인 (Verification)

#### Step 1: Kyverno 정책 검증

```bash
# 정책 1: Private Registry 강제
echo "✓ Public 이미지 거부 확인:"
kubectl run test-public --image=nginx --restart=Never 2>&1 | grep -q "Private ECR" && echo "  PASS" || echo "  FAIL"

# 정책 2: SecurityContext 강제
echo "✓ runAsNonRoot 강제 확인:"
kubectl run test-root --image=nginx --overrides='{"spec":{"securityContext":{"runAsUser":0}}}' 2>&1 | grep -q "runAsNonRoot" && echo "  PASS" || echo "  FAIL"

# 정책 3: 읽기 전용 파일시스템
echo "✓ readOnlyRootFilesystem 강제 확인:"
kubectl get pod -l app.kubernetes.io/name=web -o jsonpath='{.items[0].spec.containers[0].securityContext.readOnlyRootFilesystem}' | grep -q "true" && echo "  PASS" || echo "  FAIL"
```

#### Step 2: NetworkPolicy 검증

```bash
# 테스트 1: api → db 통신 허용 확인
kubectl exec -it $(kubectl get pod -l app.kubernetes.io/name=api -o jsonpath='{.items[0].metadata.name}') -- \
  nc -zv db 6379
# 예상 결과: Connection successful

# 테스트 2: web → db 통신 거부 확인 (정책 없음)
kubectl exec -it $(kubectl get pod -l app.kubernetes.io/name=web -o jsonpath='{.items[0].metadata.name}') -- \
  timeout 3 nc -zv db 6379 || echo "Connection denied (as expected)"

# 테스트 3: 외부 → web 트래픽 허용 확인
kubectl port-forward svc/web 8080:80 &
curl http://localhost:8080
# 예상 결과: nginx 응답 (200 OK)

# 테스트 4: DNS 조회 동작 확인
kubectl exec -it $(kubectl get pod -l app.kubernetes.io/name=api -o jsonpath='{.items[0].metadata.name}') -- \
  nslookup kubernetes.default
# 예상 결과: 정상 DNS 응답
```

#### Step 3: 취약점 스캔 결과 확인

```bash
# 1. GitHub Security 탭에서 Trivy 스캔 결과
# https://github.com/K8RVIS/eks-secure-infra/security/code-scanning

# 2. AWS Inspector v2 대시보드
# https://console.aws.amazon.com/inspector/v2/

# 3. CloudWatch Logs에서 SNS 알림 확인
aws sns get-topic-attributes \
  --topic-arn arn:aws:sns:ap-northeast-2:ACCOUNT_ID:ecr-findings \
  --attribute-names All
```

#### Step 4: 감시 및 모니터링 설정

```bash
# 1. Kyverno 정책 위반 로그 확인
kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno-policy-controller --tail=50

# 2. 워크로드 이벤트 확인
kubectl describe pod -l app.kubernetes.io/name=web
# 특히 "Events" 섹션에서 정책 적용 기록 확인

# 3. 정기적 스캔 자동화 확인
# → GitHub Actions에서 매주 월요일 02:00 UTC 자동 스캔 실행
# → AWS Inspector v2가 지속적으로 새 CVE 감지
```

---

## 4. 체크리스트 (Done When)

### 배포 체크리스트
- [ ] Kyverno 정책 3개 배포 완료
- [ ] Public 이미지 거부 정책 동작 확인
- [ ] SecurityContext 강제 정책 동작 확인
- [ ] 자동 mutate 정책 적용 확인

### 워크로드 체크리스트
- [ ] web Deployment SecurityContext 강화
- [ ] api Deployment SecurityContext 강화
- [ ] db StatefulSet SecurityContext 강화
- [ ] 모든 Pod에 리소스 요청/제한 설정
- [ ] 모든 Pod에 Probe (liveness/readiness) 설정

### NetworkPolicy 체크리스트
- [ ] default-deny-all 정책 적용
- [ ] allow-dns 정책 동작 확인
- [ ] allow-web-ingress 트래픽 확인
- [ ] allow-api-to-db 마이크로 세그멘테이션 확인

### 취약점 스캔 체크리스트
- [ ] Trivy CI/CD 자동 스캔 실행 확인
- [ ] Critical/High 취약점 감지 시 빌드 실패 확인
- [ ] Amazon Inspector v2 스캔 결과 확인
- [ ] SNS 알림 수신 확인
- [ ] .trivyignore 예외 규칙 검토 및 승인

### 보안 검증 체크리스트
- [ ] 모든 Pod가 비루트 사용자(65534)로 실행
- [ ] 모든 Container의 readOnlyRootFilesystem: true 확인
- [ ] 모든 Container의 capabilities.drop: ALL 확인
- [ ] 정책 위반 시 Pod 생성 거부 확인
- [ ] 네트워크 격리 정책 동작 확인

---

## 참고 자료

### 문서
- [NIST SP 800-190: Application Container Security](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf)
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Kyverno 정책 엔진](https://kyverno.io/)
- [Amazon Inspector v2](https://docs.aws.amazon.com/inspector/)

### 관련 이슈
- [Issue #35: Pod 보안: Container Image 취약점 탐지](https://github.com/K8RVIS/eks-secure-infra/issues/35)
- [Issue #50: Container Image 경량화 및 Private Registry 관리](https://github.com/K8RVIS/eks-secure-infra/issues/50)

### 커멘드 참고
```bash
# Kyverno 정책 확인
kubectl get clusterpolicies
kubectl describe clusterpolicy require-private-registry

# NetworkPolicy 확인
kubectl get networkpolicies -n default
kubectl describe networkpolicy default-deny-all -n default

# Pod 보안 설정 확인
kubectl get pods -n default -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.securityContext}{"\n"}{end}'

# 로그 확인
kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno --tail=50
```
