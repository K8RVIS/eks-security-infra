resource "kubernetes_manifest" "security_alert_rules" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "eks-security-alerts"
      namespace = var.prometheus_namespace
      labels = {
        release = "kube-prometheus-stack"
      }
    }
    spec = {
      groups = [
        {
          name = "eks-security"
          rules = [
            {
              alert = "HighAPIServer4xxRate"
              expr  = "sum(rate(apiserver_request_total{code=~\"4..\"}[5m])) > 5"
              for   = "2m"
              labels      = { severity = "warning" }
              annotations = {
                summary     = "API Server 4xx 오류율 높음"
                description = "API Server 4xx 요청 rate가 5 req/s 초과"
              }
            },
            {
              alert = "HighPodRestartCount"
              expr  = "sum(increase(kube_pod_container_status_restarts_total[1h])) by (namespace, pod) > 5"
              for   = "5m"
              labels      = { severity = "warning" }
              annotations = {
                summary     = "Pod 재시작 횟수 높음"
                description = "{{ $labels.namespace }}/{{ $labels.pod }} 재시작 1시간 내 5회 초과"
              }
            },
            {
              alert = "TooManyPendingPods"
              expr  = "sum(kube_pod_status_phase{phase=\"Pending\"}) by (namespace) >= 3"
              for   = "5m"
              labels      = { severity = "critical" }
              annotations = {
                summary     = "Pending Pod 다수 감지"
                description = "{{ $labels.namespace }} 네임스페이스에 Pending Pod 3개 이상"
              }
            },
            {
              alert = "HighCPUQuotaUsage"
              expr  = "kube_resourcequota{resource=\"requests.cpu\",type=\"used\"} / kube_resourcequota{resource=\"requests.cpu\",type=\"hard\"} > 0.9"
              for   = "5m"
              labels      = { severity = "warning" }
              annotations = {
                summary     = "CPU Quota 90% 초과"
                description = "{{ $labels.namespace }} CPU quota 사용률 90% 초과"
              }
            },
            {
              alert = "HighMemoryQuotaUsage"
              expr  = "kube_resourcequota{resource=\"requests.memory\",type=\"used\"} / kube_resourcequota{resource=\"requests.memory\",type=\"hard\"} > 0.9"
              for   = "5m"
              labels      = { severity = "warning" }
              annotations = {
                summary     = "Memory Quota 90% 초과"
                description = "{{ $labels.namespace }} Memory quota 사용률 90% 초과"
              }
            }
          ]
        }
      ]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
