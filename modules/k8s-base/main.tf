terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

resource "kubernetes_storage_class_v1" "encrypted_gp3" {
  metadata {
    name = "encrypted-gp3"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}

resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  namespace        = var.metrics_server_namespace
  create_namespace = true
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = var.metrics_server_chart_version
  timeout          = var.helm_release_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  wait             = true

  values = [
    yamlencode({
      args = [
        "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname",
        "--kubelet-insecure-tls",
      ]
    })
  ]
}

resource "helm_release" "aws_load_balancer_controller" {
  name             = "aws-load-balancer-controller"
  namespace        = var.aws_load_balancer_controller_namespace
  create_namespace = false
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  version          = var.aws_load_balancer_controller_chart_version
  timeout          = var.helm_release_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  wait             = true

  values = [
    yamlencode({
      clusterName = var.cluster_name
      region      = var.aws_region
      vpcId       = var.vpc_id
      serviceAccount = {
        create = false
        name   = var.aws_load_balancer_controller_service_account_name
      }
    })
  ]
}

resource "helm_release" "aws_node_termination_handler" {
  name             = "aws-node-termination-handler"
  namespace        = var.aws_node_termination_handler_namespace
  create_namespace = true
  repository       = "oci://public.ecr.aws/aws-ec2/helm"
  chart            = var.aws_node_termination_handler_chart
  version          = var.aws_node_termination_handler_chart_version
  timeout          = var.helm_release_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  wait             = true

  values = [
    <<-EOT
    enableSpotInterruptionDraining: true
    enableRebalanceMonitoring: false
    enableScheduledEventDraining: false
    EOT
  ]
}

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = var.ingress_nginx_namespace
  create_namespace = true
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_chart_version
  timeout          = var.helm_release_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  wait             = true

  values = [
    <<-EOT
    controller:
      ingressClassResource:
        default: true
      service:
        type: LoadBalancer
        annotations:
          service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
    EOT
  ]

  depends_on = [helm_release.aws_load_balancer_controller]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = var.external_secrets_namespace
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version
  timeout          = var.helm_release_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  wait             = true

  values = [
    yamlencode({
      installCRDs = true
      serviceAccount = {
        create = true
        name   = var.external_secrets_service_account_name
      }
    })
  ]

  depends_on = [helm_release.aws_load_balancer_controller]
}

# ============================================================
# Seccomp Profiles — ConfigMap + DaemonSet Installer
# ============================================================

locals {
  seccomp_web_profile = jsonencode({
    defaultAction = "SCMP_ACT_ERRNO"
    architectures = ["SCMP_ARCH_X86_64"]
    syscalls = [{
      action = "SCMP_ACT_ALLOW"
      names = [
        "accept4", "access", "arch_prctl", "bind", "brk", "capget", "capset",
        "chdir", "clone", "close", "connect", "dup", "dup2", "dup3",
        "epoll_create1", "epoll_ctl", "epoll_pwait", "epoll_wait",
        "eventfd2", "execve", "exit", "exit_group", "faccessat",
        "fcntl", "fstat", "fstatfs", "futex", "getcwd", "getdents64",
        "getegid", "geteuid", "getgid", "getpid", "getppid",
        "getrlimit", "getsockname", "getsockopt", "getuid",
        "ioctl", "lseek", "listen", "lstat", "madvise", "mmap",
        "mprotect", "munmap", "nanosleep", "newfstatat", "openat",
        "pipe", "pipe2", "prctl", "pread64", "prlimit64", "pwrite64",
        "read", "readv", "recvfrom", "recvmsg",
        "rt_sigaction", "rt_sigprocmask", "rt_sigreturn", "rt_sigsuspend",
        "sendfile", "sendmsg", "sendto", "setgid", "setgroups", "setuid",
        "setsockopt", "sigaltstack", "socket", "socketpair",
        "stat", "statfs", "sysinfo", "tgkill", "uname",
        "wait4", "write", "writev",
      ]
    }]
  })

  seccomp_api_profile = jsonencode({
    defaultAction = "SCMP_ACT_ERRNO"
    architectures = ["SCMP_ARCH_X86_64"]
    syscalls = [{
      action = "SCMP_ACT_ALLOW"
      names = [
        "accept4", "arch_prctl", "bind", "brk", "capget", "capset",
        "chdir", "clone", "close", "connect", "dup", "dup2", "dup3",
        "epoll_create1", "epoll_ctl", "epoll_pwait", "epoll_wait",
        "eventfd2", "execve", "exit", "exit_group",
        "faccessat", "fallocate", "fcntl", "fdatasync",
        "fstat", "fstatfs", "futex",
        "getcwd", "getdents64", "getegid", "geteuid",
        "getgid", "getpid", "getppid", "getrlimit",
        "getsockname", "getsockopt", "getuid",
        "ioctl", "kill", "lseek", "listen", "lstat",
        "madvise", "memfd_create", "mincore", "mmap", "mprotect",
        "munmap", "nanosleep", "newfstatat", "openat",
        "pipe", "pipe2", "poll", "prctl", "pread64", "prlimit64", "pwrite64",
        "read", "readlink", "readv", "recvfrom", "recvmsg",
        "rt_sigaction", "rt_sigprocmask", "rt_sigreturn",
        "rt_sigsuspend", "rt_sigtimedwait",
        "sched_getaffinity", "sched_yield",
        "sendmsg", "sendto", "setgid", "setgroups", "setuid",
        "setsockopt", "sigaltstack", "socket",
        "stat", "statfs", "statx", "sysinfo",
        "tgkill", "uname", "unlink",
        "wait4", "write", "writev",
      ]
    }]
  })

  seccomp_db_profile = jsonencode({
    defaultAction = "SCMP_ACT_ERRNO"
    architectures = ["SCMP_ARCH_X86_64"]
    syscalls = [{
      action = "SCMP_ACT_ALLOW"
      names = [
        "accept", "accept4", "arch_prctl", "bind", "brk",
        "capget", "capset", "chdir", "clone", "close",
        "connect", "dup", "dup2",
        "epoll_create", "epoll_create1", "epoll_ctl",
        "epoll_pwait", "epoll_wait", "eventfd2",
        "execve", "exit", "exit_group",
        "faccessat", "fcntl", "fdatasync",
        "fstat", "fstatfs", "fsync", "ftruncate", "futex",
        "getcwd", "getdents64", "getegid", "geteuid",
        "getgid", "getpid", "getppid", "getrlimit",
        "getsockname", "getsockopt", "getuid",
        "ioctl", "lseek", "listen", "lstat",
        "madvise", "mmap", "mprotect", "munmap",
        "nanosleep", "newfstatat", "openat",
        "pipe", "pipe2", "poll", "prctl",
        "pread64", "prlimit64", "pwrite64",
        "read", "readv", "recvfrom", "recvmsg",
        "rename", "rt_sigaction", "rt_sigprocmask",
        "rt_sigreturn", "rt_sigsuspend",
        "select", "sendmsg", "sendto",
        "setgid", "setgroups", "setuid",
        "setsockopt", "sigaltstack", "socket",
        "stat", "statfs", "sysinfo", "tgkill",
        "uname", "unlink", "wait4",
        "write", "writev",
      ]
    }]
  })

  seccomp_profiles_hash = sha256(join("", [
    local.seccomp_web_profile,
    local.seccomp_api_profile,
    local.seccomp_db_profile,
  ]))
}

resource "kubernetes_config_map" "seccomp_profiles" {
  metadata {
    name      = "seccomp-profiles"
    namespace = "kube-system"
  }

  data = {
    "web-nginx.json"       = local.seccomp_web_profile
    "api-echo-server.json" = local.seccomp_api_profile
    "db-redis.json"        = local.seccomp_db_profile
  }
}

resource "kubernetes_daemon_set_v1" "seccomp_installer" {
  metadata {
    name      = "seccomp-installer"
    namespace = "kube-system"
    labels    = { app = "seccomp-installer" }
  }

  spec {
    selector {
      match_labels = { app = "seccomp-installer" }
    }

    template {
      metadata {
        labels      = { app = "seccomp-installer" }
        annotations = { "profiles-hash" = local.seccomp_profiles_hash }
      }

      spec {
        init_container {
          name    = "installer"
          image   = "busybox:1.36"
          command = ["sh", "-c", "cp /profiles/*.json /host-seccomp/"]

          volume_mount {
            name       = "profiles"
            mount_path = "/profiles"
          }

          volume_mount {
            name       = "host-seccomp"
            mount_path = "/host-seccomp"
          }
        }

        container {
          name  = "pause"
          image = "registry.k8s.io/pause:3.10"

          resources {
            requests = { cpu = "1m", memory = "4Mi" }
            limits   = { memory = "4Mi" }
          }
        }

        volume {
          name = "profiles"
          config_map {
            name = kubernetes_config_map.seccomp_profiles.metadata[0].name
          }
        }

        volume {
          name = "host-seccomp"
          host_path {
            path = "/var/lib/kubelet/seccomp"
            type = "DirectoryOrCreate"
          }
        }

        toleration {
          operator = "Exists"
        }
      }
    }
  }

  depends_on = [kubernetes_config_map.seccomp_profiles]
}
