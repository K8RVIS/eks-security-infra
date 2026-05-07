# Workload Storage Data Protection Design

## Context

`eks-secure-infra` is organized into three layers:

- `environments/infra`: AWS infrastructure, including VPC, EKS, node groups, and the EBS CSI Driver add-on.
- `environments/platform`: cluster platform resources and add-ons, using the `k8s-base`, `namespaces`, and `argocd` modules.
- `manifests`: GitOps-managed sample workloads and team overlays.

The EKS node group launch template already encrypts worker node root EBS volumes. This feature focuses on workload data volumes created from Kubernetes PersistentVolumeClaims. The current base Redis StatefulSet requests a `gp2` StorageClass, so a workload PVC can still be provisioned without the explicit encrypted `gp3` safety rail required by this exercise.

The rollout will be canary-scoped to `team-d` only. Other team overlays keep their current PVC behavior until the encrypted storage flow is validated.

## Goals

- Add an encrypted EBS-backed StorageClass named `encrypted-gp3`.
- Make `team-d` DB workload PVCs use `encrypted-gp3`.
- Provide a diagnostic script that checks Kubernetes StorageClass, PVC, PV, and actual AWS EBS Volume encryption state together.
- Document the canary lab flow, including AWS account/region EBS encryption-by-default checks and cluster-level verification.

## Non-Goals

- Do not migrate existing production PVCs, PVs, or EBS volumes.
- Do not force every team overlay to use the encrypted StorageClass in this change.
- Do not replace the cluster default StorageClass.
- Do not configure a customer managed KMS key by default.

## Recommended Approach

Create the StorageClass as a platform-level cluster resource and apply it only from the `team-d` workload overlay.

This keeps cluster-scoped infrastructure ownership in `modules/k8s-base`, while the canary workload change stays in `manifests/overlays/team-d`. It also avoids making a team overlay responsible for a cluster-scoped StorageClass and avoids changing default storage behavior for unrelated workloads.

## Architecture

### Platform StorageClass

Add a Kubernetes StorageClass resource to `modules/k8s-base`:

- Name: `encrypted-gp3`
- Provisioner: `ebs.csi.aws.com`
- Volume binding mode: `WaitForFirstConsumer`
- Reclaim policy: `Delete`
- Parameters:
  - `type = "gp3"`
  - `encrypted = "true"`

The StorageClass will use the AWS managed `aws/ebs` key unless a future production change introduces a `kmsKeyId` parameter.

### Team-D Canary Workload

Patch only `manifests/overlays/team-d/db-statefulset-patch.yaml` so the Redis StatefulSet volume claim template requests:

```yaml
storageClassName: encrypted-gp3
```

The base manifest remains unchanged. Teams `team-a`, `team-b`, and `team-c` continue to render with the existing base `gp2` setting.

### Diagnostic Script

Add `scripts/check_ebs_volume_encryption.py`.

The script will:

- Check account/region EBS encryption-by-default using AWS CLI.
- Read the target StorageClass with `kubectl`.
- List PVCs in a namespace, or inspect a named PVC.
- Resolve PVCs to PVs.
- Extract the EBS volume ID from CSI-backed PVs.
- Query AWS EC2 `describe-volumes`.
- Print whether the actual EBS volume has `Encrypted=true`.

The first supported path will use local `kubectl` and `aws` CLI commands because this repository already relies on CLI-driven lab workflows. The script should fail clearly when a dependency, namespace, PVC, PV, or volume cannot be found.

## Data Flow

1. Platform Terraform applies `encrypted-gp3` to the cluster.
2. ArgoCD or `kubectl apply -k manifests/overlays/team-d` applies the team-d workload patch.
3. The `team-d` StatefulSet creates a PVC using `encrypted-gp3`.
4. The EBS CSI Driver provisions an EBS gp3 volume with encryption enabled.
5. Kubernetes PV status records the CSI volume handle.
6. The diagnostic script maps PVC -> PV -> EBS Volume and verifies AWS reports `Encrypted=true`.

## Error Handling

The diagnostic script should return a non-zero exit code when:

- `kubectl` or `aws` is unavailable.
- The StorageClass is missing or does not contain `encrypted: "true"`.
- A PVC is not bound to a PV.
- The PV is not backed by the EBS CSI Driver.
- AWS EC2 cannot find the referenced EBS volume.
- The EBS volume exists but reports `Encrypted=false`.

Warnings are acceptable for account-level EBS encryption-by-default being disabled, because the StorageClass itself is the primary per-workload control in this lab. The warning should still be visible because account/region default encryption is an important safety net.

## Testing

Add focused static tests in the repository's existing Python unittest style:

- `modules/k8s-base/main.tf` declares `encrypted-gp3`.
- The StorageClass includes `ebs.csi.aws.com`, `gp3`, and `encrypted = "true"`.
- `team-d` overlay patches the DB StatefulSet to use `encrypted-gp3`.
- Other team overlays do not opt into the canary StorageClass.
- The diagnostic script exposes CLI options for namespace, StorageClass, and PVC selection.

Run the relevant unit tests after implementation:

```bash
python -m unittest tests.test_k8s_base_module tests.test_team_overlay_consistency tests.test_workload_storage_encryption
```

Run Terraform module tests when the Terraform changes are complete:

```bash
terraform test
```

For live verification in an applied EKS environment, run:

```bash
python scripts/check_ebs_volume_encryption.py \
  --namespace team-d \
  --storage-class encrypted-gp3
```

Expected result: the team-d PVC resolves to an EBS volume whose AWS EC2 volume metadata reports `Encrypted=true`.

## Rollout

1. Apply the platform layer so `encrypted-gp3` exists.
2. Sync only the team-d workload overlay.
3. Confirm the Redis PVC binds successfully.
4. Run the diagnostic script.
5. Document the observed `Encrypted=true` result.
6. After validation, a separate change can expand the patch to other teams or make the encrypted StorageClass the default.

## Security Notes

- Existing unencrypted EBS volumes are not encrypted by changing a StorageClass. They require snapshot copy or data migration into a new encrypted volume.
- Customer managed KMS keys can be added later with `kmsKeyId` for sensitive workloads.
- Account/region EBS encryption-by-default should still be enabled as a defense-in-depth safety net.
