#!/usr/bin/env python3
import argparse
import json
import os
import re
import subprocess
from pathlib import Path
from typing import Any

import yaml


EBS_PROVISIONERS = {"ebs.csi.aws.com", "kubernetes.io/aws-ebs"}


def run_command(args: list[str]) -> tuple[bool, str, str]:
    try:
        result = subprocess.run(args, capture_output=True, text=True)
    except FileNotFoundError:
        return False, "", f"Required command not found: {args[0]}"
    return result.returncode == 0, result.stdout.strip(), result.stderr.strip()


def run_json(args: list[str]) -> dict[str, Any]:
    ok, stdout, stderr = run_command(args)
    if not ok:
        raise RuntimeError(stderr or f"Command failed: {' '.join(args)}")
    return json.loads(stdout) if stdout else {}


def aws_args(profile: str | None) -> list[str]:
    return ["aws", "--profile", profile] if profile else ["aws"]


def kubectl_args(context: str | None) -> list[str]:
    return ["kubectl", "--context", context] if context else ["kubectl"]


def credential_source(profile: str | None) -> str:
    if profile:
        return f"profile:{profile}"
    if os.environ.get("AWS_ACCESS_KEY_ID"):
        return "environment"
    return "default-provider-chain"


def detect_region(explicit_region: str | None, profile: str | None) -> str | None:
    if explicit_region:
        return explicit_region

    for key in ("AWS_REGION", "AWS_DEFAULT_REGION"):
        if os.environ.get(key):
            return os.environ[key]

    ok, stdout, _ = run_command(aws_args(profile) + ["configure", "get", "region"])
    return stdout if ok and stdout else None


def is_ebs_provisioner(provisioner: str | None) -> bool:
    return provisioner in EBS_PROVISIONERS or "ebs" in str(provisioner).lower()


def load_yaml_documents(path: Path) -> list[dict[str, Any]]:
    try:
        with path.open("r", encoding="utf-8") as file:
            return [doc for doc in yaml.safe_load_all(file) if isinstance(doc, dict)]
    except Exception as exc:
        return [{"__parse_error__": str(exc)}]


def find_line(path: Path, text: str) -> int | None:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except Exception:
        return None

    for index, line in enumerate(lines, start=1):
        if text in line:
            return index
    return None


def rel_path(path: str | Path, repo_root: Path) -> str:
    try:
        return str(Path(path).resolve().relative_to(repo_root))
    except Exception:
        return str(path)


def classify_not_explicit(default_enabled: bool | None) -> str:
    if default_enabled is False:
        return "high"
    if default_enabled is True:
        return "low"
    return "miss"


def get_default_encryption(region: str | None, profile: str | None) -> dict[str, Any]:
    if not region:
        return {"available": False, "enabled": None, "error": "AWS region not found."}

    ok, stdout, stderr = run_command(
        aws_args(profile)
        + [
            "ec2",
            "get-ebs-encryption-by-default",
            "--region",
            region,
            "--output",
            "json",
        ]
    )

    if not ok:
        return {"available": False, "enabled": None, "error": stderr}

    return {"available": True, "enabled": json.loads(stdout).get("EbsEncryptionByDefault"), "error": None}


def get_cluster_storageclasses(context: str | None) -> list[dict[str, Any]]:
    data = run_json(kubectl_args(context) + ["get", "storageclass", "-o", "json"])
    rows = []

    for item in data.get("items", []):
        metadata = item.get("metadata") or {}
        params = item.get("parameters") or {}
        annotations = metadata.get("annotations") or {}
        provisioner = item.get("provisioner")

        rows.append(
            {
                "name": metadata.get("name"),
                "isDefault": annotations.get("storageclass.kubernetes.io/is-default-class") == "true",
                "isEbs": is_ebs_provisioner(provisioner),
                "provisioner": provisioner,
                "type": params.get("type"),
                "encrypted": params.get("encrypted"),
                "binding": item.get("volumeBindingMode"),
                "source": "cluster",
            }
        )

    return rows


def line_for_offset(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def extract_hcl_blocks(text: str, pattern: re.Pattern[str]) -> list[tuple[re.Match[str], str, int]]:
    blocks = []
    for match in pattern.finditer(text):
        brace_start = text.find("{", match.end() - 1)
        if brace_start == -1:
            continue

        depth = 0
        for index in range(brace_start, len(text)):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    blocks.append((match, text[brace_start + 1 : index], brace_start))
                    break
    return blocks


def hcl_string_value(block: str, key: str) -> str | None:
    match = re.search(rf"\b{re.escape(key)}\s*=\s*\"([^\"]+)\"", block)
    return match.group(1) if match else None


def hcl_nested_block(block: str, name: str) -> str | None:
    pattern = re.compile(rf"\b{re.escape(name)}\s*(?:=)?\s*{{")
    blocks = extract_hcl_blocks(block, pattern)
    return blocks[0][1] if blocks else None


def hcl_parameters(block: str) -> dict[str, str]:
    params_block = hcl_nested_block(block, "parameters")
    if not params_block:
        return {}
    return dict(re.findall(r"\b([A-Za-z0-9_-]+)\s*=\s*\"([^\"]+)\"", params_block))


def scan_terraform_storageclasses(repo_root: Path) -> list[dict[str, Any]]:
    storageclasses = []
    resource_pattern = re.compile(r'resource\s+"kubernetes_storage_class_v1"\s+"([^"]+)"\s*{')

    for path in repo_root.rglob("*.tf"):
        if ".terraform" in path.parts:
            continue

        try:
            text = path.read_text(encoding="utf-8")
        except Exception:
            continue

        for match, block, offset in extract_hcl_blocks(text, resource_pattern):
            metadata_block = hcl_nested_block(block, "metadata") or ""
            params = hcl_parameters(block)
            provisioner = hcl_string_value(block, "storage_provisioner")
            name = hcl_string_value(metadata_block, "name") or match.group(1)

            storageclasses.append(
                {
                    "name": name,
                    "file": str(path),
                    "line": line_for_offset(text, offset),
                    "isEbs": is_ebs_provisioner(provisioner),
                    "provisioner": provisioner,
                    "type": params.get("type"),
                    "encrypted": params.get("encrypted"),
                    "source": "terraform",
                }
            )

    return storageclasses


def add_storageclass_finding(
    findings: list[dict[str, Any]],
    sc: dict[str, Any],
    default_enabled: bool | None,
    repo_root: Path,
) -> None:
    if not sc.get("isEbs"):
        return

    source = sc.get("source", "manifest")
    location = Path(sc["file"]) if sc.get("file") else repo_root
    line = sc.get("line") or find_line(location, "parameters:") or find_line(location, "provisioner:")

    if sc.get("encrypted") != "true":
        findings.append(
            {
                "risk": classify_not_explicit(default_enabled),
                "file": str(location),
                "line": line,
                "resource": f"StorageClass/{sc['name']}",
                "message": f"EBS StorageClass encrypted={sc.get('encrypted') or '<missing>'} ({source})",
                "fix": 'parameters.encrypted: "true"를 추가하세요.',
            }
        )
        return

    findings.append(
        {
            "risk": "ok",
            "file": str(location),
            "line": line,
            "resource": f"StorageClass/{sc['name']}",
            "message": f'EBS StorageClass에 encrypted: "true"가 명시되어 있습니다. ({source})',
            "fix": "수정 불필요",
        }
    )


def scan_manifests(
    repo_root: Path,
    default_enabled: bool | None,
    live_scs: dict[str, dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    manifest_scs = {}
    findings = []
    yaml_files = list(repo_root.rglob("*.yaml")) + list(repo_root.rglob("*.yml"))

    for path in yaml_files:
        if ".terraform" in path.parts:
            continue

        for doc in load_yaml_documents(path):
            if "__parse_error__" in doc:
                findings.append(
                    {
                        "risk": "miss",
                        "file": str(path),
                        "line": None,
                        "resource": "YAML",
                        "message": doc["__parse_error__"],
                        "fix": "YAML 문법을 먼저 수정하세요.",
                    }
                )
                continue

            if doc.get("kind") != "StorageClass":
                continue

            name = (doc.get("metadata") or {}).get("name", "<unknown>")
            params = doc.get("parameters") or {}
            provisioner = doc.get("provisioner")

            manifest_scs[name] = {
                "name": name,
                "file": str(path),
                "line": find_line(path, "parameters:") or find_line(path, "provisioner:"),
                "isEbs": is_ebs_provisioner(provisioner),
                "provisioner": provisioner,
                "type": params.get("type"),
                "encrypted": params.get("encrypted"),
                "source": "manifest",
            }

    terraform_scs = {sc["name"]: sc for sc in scan_terraform_storageclasses(repo_root)}
    known_scs = {}
    known_scs.update(terraform_scs)
    known_scs.update(manifest_scs)
    known_scs.update({name: sc for name, sc in live_scs.items() if name not in known_scs})

    for sc in list(terraform_scs.values()) + list(manifest_scs.values()):
        add_storageclass_finding(findings, sc, default_enabled, repo_root)

    for path in yaml_files:
        if ".terraform" in path.parts:
            continue

        for doc in load_yaml_documents(path):
            if "__parse_error__" in doc:
                continue

            kind = doc.get("kind")
            name = (doc.get("metadata") or {}).get("name", "<unknown>")

            if kind == "PersistentVolumeClaim":
                sc_name = (doc.get("spec") or {}).get("storageClassName")
                add_reference_finding(findings, path, f"PersistentVolumeClaim/{name}", sc_name, known_scs, default_enabled)

            if kind == "StatefulSet":
                templates = (doc.get("spec") or {}).get("volumeClaimTemplates") or []
                for template in templates:
                    pvc_name = (template.get("metadata") or {}).get("name", "<unknown>")
                    sc_name = (template.get("spec") or {}).get("storageClassName")
                    add_reference_finding(
                        findings,
                        path,
                        f"StatefulSet/{name} volumeClaimTemplate/{pvc_name}",
                        sc_name,
                        known_scs,
                        default_enabled,
                    )

    return list(known_scs.values()), findings


def add_reference_finding(
    findings: list[dict[str, Any]],
    path: Path,
    resource: str,
    sc_name: str | None,
    known_scs: dict[str, dict[str, Any]],
    default_enabled: bool | None,
) -> None:
    if not sc_name:
        findings.append(
            {
                "risk": "miss",
                "file": str(path),
                "line": find_line(path, "spec:"),
                "resource": resource,
                "message": "storageClassName이 없어 클러스터 기본 StorageClass에 의존합니다.",
                "fix": 'encrypted: "true"가 있는 EBS StorageClass를 명시하세요.',
            }
        )
        return

    sc = known_scs.get(sc_name)
    if not sc:
        findings.append(
            {
                "risk": "miss",
                "file": str(path),
                "line": find_line(path, "storageClassName"),
                "resource": resource,
                "message": f"StorageClass/{sc_name} 정보를 찾지 못했습니다.",
                "fix": "--cluster 옵션으로 live StorageClass를 조회하거나 StorageClass 정의를 포함하세요.",
            }
        )
        return

    if sc.get("isEbs") and sc.get("encrypted") != "true":
        findings.append(
            {
                "risk": classify_not_explicit(default_enabled),
                "file": str(path),
                "line": find_line(path, "storageClassName"),
                "resource": resource,
                "message": f"EBS StorageClass/{sc_name} encrypted={sc.get('encrypted') or '<missing>'}",
                "fix": 'encrypted: "true"가 있는 StorageClass를 사용하세요.',
            }
        )
    elif sc.get("isEbs"):
        findings.append(
            {
                "risk": "ok",
                "file": str(path),
                "line": find_line(path, "storageClassName"),
                "resource": resource,
                "message": f'EBS StorageClass/{sc_name}에 encrypted: "true"가 명시되어 있습니다.',
                "fix": "수정 불필요",
            }
        )


def get_cluster_pvcs(context: str | None, namespace: str | None) -> list[dict[str, Any]]:
    args = kubectl_args(context) + ["get", "pvc"]
    args.extend(["-n", namespace] if namespace else ["-A"])
    args.extend(["-o", "json"])

    data = run_json(args)
    rows = []

    for item in data.get("items", []):
        metadata = item.get("metadata") or {}
        spec = item.get("spec") or {}
        status = item.get("status") or {}

        rows.append(
            {
                "namespace": metadata.get("namespace"),
                "name": metadata.get("name"),
                "phase": status.get("phase"),
                "sc": spec.get("storageClassName"),
                "pv": spec.get("volumeName"),
                "size": (status.get("capacity") or {}).get("storage"),
            }
        )

    return rows


def extract_volume_id(spec: dict[str, Any]) -> tuple[str | None, str | None]:
    csi_volume = (spec.get("csi") or {}).get("volumeHandle")
    if csi_volume and csi_volume.startswith("vol-"):
        return csi_volume, "csi.volumeHandle"

    legacy_volume = (spec.get("awsElasticBlockStore") or {}).get("volumeID")
    if legacy_volume:
        match = re.search(r"(vol-[a-zA-Z0-9]+)", legacy_volume)
        if match:
            return match.group(1), "awsElasticBlockStore.volumeID"

    return None, None


def get_cluster_pvs(context: str | None, region: str | None, profile: str | None) -> list[dict[str, Any]]:
    data = run_json(kubectl_args(context) + ["get", "pv", "-o", "json"])
    rows = []

    for item in data.get("items", []):
        metadata = item.get("metadata") or {}
        spec = item.get("spec") or {}
        status = item.get("status") or {}
        claim = spec.get("claimRef") or {}

        volume_id, source = extract_volume_id(spec)
        encrypted = None
        volume_type = None
        kms_key = None
        error = None
        risk = "miss"

        if not region:
            error = "AWS region not found."
        elif not volume_id:
            error = "EBS volume ID not found."
        else:
            ok, stdout, stderr = run_command(
                aws_args(profile)
                + [
                    "ec2",
                    "describe-volumes",
                    "--region",
                    region,
                    "--volume-ids",
                    volume_id,
                    "--output",
                    "json",
                ]
            )
            if ok:
                volume = json.loads(stdout).get("Volumes", [{}])[0]
                encrypted = volume.get("Encrypted")
                volume_type = volume.get("VolumeType")
                kms_key = volume.get("KmsKeyId")
                risk = "high" if encrypted is False else "low"
            else:
                error = stderr

        rows.append(
            {
                "risk": risk,
                "name": metadata.get("name"),
                "phase": status.get("phase"),
                "sc": spec.get("storageClassName"),
                "claim": f"{claim.get('namespace')}/{claim.get('name')}" if claim else None,
                "volumeId": volume_id,
                "source": source,
                "encrypted": encrypted,
                "type": volume_type,
                "kmsKey": kms_key,
                "error": error,
            }
        )

    return rows


def risk_label(risk: str) -> str:
    return risk.upper()


def print_environment(repo_root: Path, region: str | None, profile: str | None, context: str | None, namespace: str | None) -> None:
    print("[환경]")
    print(f"Repo      : {repo_root}")
    print(f"Region    : {region or '<not detected>'}")
    print(f"AWS Auth  : {credential_source(profile)}")
    print(f"Context   : {context or 'current-context'}")
    print(f"Namespace : {namespace or 'all'}")


def print_default_encryption(default: dict[str, Any]) -> None:
    print("\n[AWS EBS 기본 암호화]")
    if not default["available"]:
        print("상태: 확인 불가")
        print(f"사유: {default['error']}")
        return

    if default["enabled"]:
        print("상태: ON")
        print("설명: 계정/리전 기본 암호화가 켜져 있습니다.")
    else:
        print("상태: OFF")
        print('설명: StorageClass에 encrypted: "true"가 없으면 비암호화 EBS가 생성될 수 있습니다.')


def print_findings(findings: list[dict[str, Any]], repo_root: Path) -> None:
    print("\n[파일별 점검 결과]")
    if not findings:
        print("점검 대상 파일이 없습니다.")
        return

    order = {"high": 0, "low": 1, "miss": 2, "ok": 3}
    sorted_findings = sorted(findings, key=lambda x: order.get(x["risk"], 9))
    for index, item in enumerate(sorted_findings, start=1):
        location = rel_path(item["file"], repo_root)
        line = item["line"] or "-"

        print(f"\n{index}. [{risk_label(item['risk'])}] {item['resource']}")
        print(f"   파일: {location}:{line}")
        label = "상태" if item["risk"] == "ok" else "문제"
        print(f"   {label}: {item['message']}")
        print(f"   조치: {item['fix']}")

        if item["risk"] == "high":
            print("   판단: 실제 비암호화 위험이 높으므로 패치가 필요합니다.")
        elif item["risk"] == "low":
            print("   판단: 기본 암호화로 보호될 수 있지만 매니페스트에 암호화 의도가 명시되지 않았습니다.")
        elif item["risk"] == "miss":
            print("   판단: 스크립트가 자동 판단하지 못했습니다. 사용자가 직접 확인해야 합니다.")
        else:
            print("   판단: 암호화 의도가 명시되어 있어 수정하지 않아도 됩니다.")


def print_important_cluster_resources(pvs: list[dict[str, Any]]) -> None:
    print("\n[확인 필요한 클러스터 리소스]")

    important_pvs = [pv for pv in pvs if pv.get("risk") in {"high", "miss"}]
    if not important_pvs:
        print("추가 확인이 필요한 PV가 없습니다.")
        return

    for index, pv in enumerate(important_pvs, start=1):
        encrypted = pv["encrypted"]
        encrypted_text = "<unknown>" if encrypted is None else str(encrypted).lower()

        print(f"\n{index}. [{risk_label(pv['risk'])}] PV/{pv['name']}")
        print(f"   PVC         : {pv.get('claim') or '<none>'}")
        print(f"   StorageClass: {pv['sc'] or '<none>'}")
        print(f"   EBS Volume  : {pv['volumeId'] or '<missing>'}")
        print(f"   Encrypted   : {encrypted_text}")

        if pv.get("error"):
            print(f"   사유        : {pv['error']}")

        if pv["risk"] == "high":
            print("   판단        : 실제 EBS Volume이 비암호화 상태입니다.")
            print("   조치        : 기존 PV는 자동 암호화되지 않으므로 재생성 또는 마이그레이션이 필요합니다.")
        elif pv["risk"] == "miss":
            print("   판단        : 실제 EBS Volume 암호화 여부를 자동 확인하지 못했습니다.")
            print("   조치        : Volume ID 또는 AWS 조회 결과를 직접 확인해야 합니다.")


def print_result(findings: list[dict[str, Any]], pvs: list[dict[str, Any]]) -> None:
    all_risks = [item["risk"] for item in findings] + [item["risk"] for item in pvs]
    print("\n[결과 요약]")
    print(f"HIGH : {all_risks.count('high')}")
    print(f"LOW  : {all_risks.count('low')}")
    print(f"MISS : {all_risks.count('miss')}")
    print(f"OK   : {all_risks.count('ok')}")

    if all_risks.count("high") > 0:
        print("\n결론: HIGH 항목이 있으므로 패치가 필요합니다.")
    elif all_risks.count("miss") > 0:
        print("\n결론: 치명 항목은 없지만 직접 확인이 필요한 항목이 있습니다.")
    elif all_risks.count("low") > 0:
        print("\n결론: 기본 암호화 안전망은 있으나 매니페스트 명시성 개선이 권장됩니다.")
    else:
        print("\n결론: 확인된 범위에서 EBS 암호화 관련 문제는 없습니다.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--region", default=None)
    parser.add_argument("--profile", default=None)
    parser.add_argument("--cluster", action="store_true")
    parser.add_argument("--context", default=None)
    parser.add_argument("--namespace", default=None)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    region = detect_region(args.region, args.profile)
    default = get_default_encryption(region, args.profile)

    cluster_scs = []
    pvcs = []
    pvs = []
    live_scs = {}

    if args.cluster:
        cluster_scs = get_cluster_storageclasses(args.context)
        live_scs = {sc["name"]: sc for sc in cluster_scs}
        pvcs = get_cluster_pvcs(args.context, args.namespace)
        pvs = get_cluster_pvs(args.context, region, args.profile)

    storageclasses, findings = scan_manifests(repo_root, default["enabled"], live_scs)

    if args.json:
        print(
            json.dumps(
                {
                    "environment": {
                        "repoRoot": str(repo_root),
                        "region": region,
                        "awsAuth": credential_source(args.profile),
                        "context": args.context,
                        "namespace": args.namespace,
                    },
                    "defaultEncryption": default,
                    "knownStorageClasses": storageclasses,
                    "findings": findings,
                    "clusterStorageClasses": cluster_scs,
                    "clusterPVCs": pvcs,
                    "clusterPVs": pvs,
                },
                indent=2,
                ensure_ascii=False,
            )
        )
    else:
        print_environment(repo_root, region, args.profile, args.context, args.namespace)
        print_default_encryption(default)
        print_findings(findings, repo_root)
        if args.cluster:
            print_important_cluster_resources(pvs)
        print_result(findings, pvs)

    has_high = any(item["risk"] == "high" for item in findings) or any(item["risk"] == "high" for item in pvs)
    if has_high:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
