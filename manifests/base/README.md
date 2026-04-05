# Sample Workloads Baseline

This directory contains intentionally insecure sample workloads for the training environment.

- `web`: pinned `nginx`, runs as root, no resource limits, no TLS on the ingress
- `api`: `ealen/echo-server`, uses the default ServiceAccount, mounts the service account token
- `db`: `redis:7`, stores a plaintext password in an environment variable, no NetworkPolicy, no read-only root filesystem
