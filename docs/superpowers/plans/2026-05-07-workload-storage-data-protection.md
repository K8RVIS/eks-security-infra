# Workload Storage Data Protection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a team-d canary lab that provisions EKS workload PVCs with an encrypted EBS gp3 StorageClass and verifies the real AWS EBS volume encryption state.

**Architecture:** The encrypted StorageClass is a platform-owned cluster resource in `modules/k8s-base`. Only the `team-d` overlay opts into it by patching the Redis StatefulSet PVC template. A Python diagnostic script uses `kubectl` and `aws` CLI JSON output to map StorageClass -> PVC -> PV -> EBS volume and fail when encryption is missing.

**Tech Stack:** Terraform, Kubernetes provider, Kustomize overlays, Python `unittest`, Python standard library, `kubectl`, AWS CLI.

---

## File Structure

- Modify `modules/k8s-base/main.tf`: add a Kubernetes provider requirement and an encrypted gp3 `kubernetes_storage_class_v1`.
- Modify `modules/k8s-base/outputs.tf`: expose the encrypted StorageClass name.
- Modify `modules/k8s-base/tests/core-addons.tftest.hcl`: mock the Kubernetes provider and assert the StorageClass contract.
- Modify `tests/test_k8s_base_module.py`: add static checks for the Terraform StorageClass.
- Modify `manifests/overlays/team-d/db-statefulset-patch.yaml`: canary only the Redis PVC template to `encrypted-gp3`.
- Modify `tests/test_team_overlay_consistency.py`: assert team-d opts in and other overlays do not.
- Create `scripts/check_ebs_volume_encryption.py`: diagnostic CLI for StorageClass, PVC, PV, and AWS EBS volume state.
- Create `tests/test_workload_storage_encryption.py`: static tests for the diagnostic script and canary manifests.
- Create `docs/team-d-workload-storage-encryption.md`: lab guide and live verification commands.

## Task 1: Platform Encrypted StorageClass

**Files:**
- Modify: `modules/k8s-base/main.tf`
- Modify: `modules/k8s-base/outputs.tf`
- Modify: `modules/k8s-base/tests/core-addons.tftest.hcl`
- Modify: `tests/test_k8s_base_module.py`

- [ ] **Step 1: Write failing static tests for the StorageClass**

Add this test method to `tests/test_k8s_base_module.py`:

```python
    def test_encrypted_gp3_storage_class_is_declared(self):
        main_tf = K8S_BASE_MAIN.read_text()

        self.assertIn('kubernetes_storage_class_v1" "encrypted_gp3"', main_tf)
        self.assertIn('metadata {', main_tf)
        self.assertIn('name = "encrypted-gp3"', main_tf)
        self.assertIn('storage_provisioner = "ebs.csi.aws.com"', main_tf)
        self.assertIn('reclaim_policy      = "Delete"', main_tf)
        self.assertIn('volume_binding_mode = "WaitForFirstConsumer"', main_tf)
        self.assertIn('type      = "gp3"', main_tf)
        self.assertIn('encrypted = "true"', main_tf)
```

- [ ] **Step 2: Run the static test and verify it fails**

Run:

```bash
python -m unittest tests.test_k8s_base_module
```

Expected: FAIL because `kubernetes_storage_class_v1" "encrypted_gp3"` is not present.

- [ ] **Step 3: Write failing Terraform module assertions**

Modify the top of `modules/k8s-base/tests/core-addons.tftest.hcl` to mock the Kubernetes provider:

```hcl
mock_provider "helm" {
  override_during = plan
}

mock_provider "kubernetes" {
  override_during = plan
}
```

Add these assertions inside `run "plan_deploys_core_addons"`:

```hcl
  assert {
    condition     = kubernetes_storage_class_v1.encrypted_gp3.metadata[0].name == "encrypted-gp3"
    error_message = "The platform module must create the encrypted-gp3 StorageClass."
  }

  assert {
    condition     = kubernetes_storage_class_v1.encrypted_gp3.storage_provisioner == "ebs.csi.aws.com"
    error_message = "The encrypted StorageClass must use the AWS EBS CSI Driver."
  }

  assert {
    condition     = kubernetes_storage_class_v1.encrypted_gp3.parameters.type == "gp3"
    error_message = "The encrypted StorageClass must provision gp3 volumes."
  }

  assert {
    condition     = kubernetes_storage_class_v1.encrypted_gp3.parameters.encrypted == "true"
    error_message = "The encrypted StorageClass must explicitly enable EBS encryption."
  }

  assert {
    condition     = output.encrypted_storage_class_name == "encrypted-gp3"
    error_message = "The module must expose the encrypted StorageClass name."
  }
```

- [ ] **Step 4: Run Terraform test and verify it fails**

Run from `modules/k8s-base`:

```bash
terraform test
```

Expected: FAIL because `kubernetes_storage_class_v1.encrypted_gp3` and `output.encrypted_storage_class_name` do not exist.

- [ ] **Step 5: Add the Kubernetes provider and StorageClass**

Modify `modules/k8s-base/main.tf` provider requirements:

```hcl
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
```

Add this resource near the top-level add-on resources in `modules/k8s-base/main.tf`:

```hcl
resource "kubernetes_storage_class_v1" "encrypted_gp3" {
  metadata {
    name = "encrypted-gp3"
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}
```

- [ ] **Step 6: Expose the StorageClass name**

Append this output to `modules/k8s-base/outputs.tf`:

```hcl
output "encrypted_storage_class_name" {
  description = "Encrypted gp3 StorageClass name for EBS-backed workload PVCs."
  value       = kubernetes_storage_class_v1.encrypted_gp3.metadata[0].name
}
```

- [ ] **Step 7: Run tests and verify they pass**

Run:

```bash
python -m unittest tests.test_k8s_base_module
```

Expected: PASS.

Run from `modules/k8s-base`:

```bash
terraform test
```

Expected: PASS.

- [ ] **Step 8: Commit Task 1**

```bash
git add modules/k8s-base/main.tf modules/k8s-base/outputs.tf modules/k8s-base/tests/core-addons.tftest.hcl tests/test_k8s_base_module.py
git commit -m "feat: add encrypted gp3 storage class"
```

## Task 2: Team-D Canary PVC Patch

**Files:**
- Modify: `manifests/overlays/team-d/db-statefulset-patch.yaml`
- Modify: `tests/test_team_overlay_consistency.py`
- Create: `tests/test_workload_storage_encryption.py`

- [ ] **Step 1: Write failing team overlay consistency test**

Add this method to `tests/test_team_overlay_consistency.py`:

```python
    def test_only_team_d_uses_encrypted_gp3_storage_canary(self):
        for team_name in ["team-a", "team-b", "team-c"]:
            db_statefulset_patch = read_overlay(team_name, "db-statefulset-patch.yaml")

            self.assertNotIn("encrypted-gp3", db_statefulset_patch)

        team_d_patch = read_overlay("team-d", "db-statefulset-patch.yaml")

        self.assertIn("volumeClaimTemplates:", team_d_patch)
        self.assertIn("storageClassName: encrypted-gp3", team_d_patch)
```

- [ ] **Step 2: Write failing workload storage test**

Create `tests/test_workload_storage_encryption.py`:

```python
import pathlib
import unittest


PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFESTS = PROJECT_ROOT / "manifests"


class WorkloadStorageEncryptionTests(unittest.TestCase):
    def test_team_d_statefulset_patch_uses_encrypted_storage_class(self):
        team_d_patch = (MANIFESTS / "overlays" / "team-d" / "db-statefulset-patch.yaml").read_text()

        self.assertIn("volumeClaimTemplates:", team_d_patch)
        self.assertIn("storageClassName: encrypted-gp3", team_d_patch)

    def test_base_workload_keeps_existing_storage_class_until_canary_expands(self):
        base_statefulset = (MANIFESTS / "base" / "db" / "statefulset.yaml").read_text()

        self.assertIn("storageClassName: gp2", base_statefulset)
        self.assertNotIn("storageClassName: encrypted-gp3", base_statefulset)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run tests and verify they fail**

Run:

```bash
python -m unittest tests.test_team_overlay_consistency tests.test_workload_storage_encryption
```

Expected: FAIL because `team-d` does not patch `volumeClaimTemplates` yet.

- [ ] **Step 4: Patch team-d StatefulSet volume claim template**

Replace `manifests/overlays/team-d/db-statefulset-patch.yaml` with:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: db
spec:
  template:
    spec:
      serviceAccountName: db-workload
      automountServiceAccountToken: false
  volumeClaimTemplates:
    - metadata:
        name: redis-data
      spec:
        storageClassName: encrypted-gp3
```

- [ ] **Step 5: Run tests and verify they pass**

Run:

```bash
python -m unittest tests.test_team_overlay_consistency tests.test_workload_storage_encryption
```

Expected: PASS.

- [ ] **Step 6: Render the team-d overlay**

Run:

```bash
kubectl kustomize manifests/overlays/team-d
```

Expected: command exits 0 and rendered output contains `storageClassName: encrypted-gp3`.

- [ ] **Step 7: Commit Task 2**

```bash
git add manifests/overlays/team-d/db-statefulset-patch.yaml tests/test_team_overlay_consistency.py tests/test_workload_storage_encryption.py
git commit -m "feat: canary encrypted storage for team-d"
```

## Task 3: EBS Encryption Diagnostic Script

**Files:**
- Create: `scripts/check_ebs_volume_encryption.py`
- Modify: `tests/test_workload_storage_encryption.py`

- [ ] **Step 1: Add failing static tests for the diagnostic CLI**

Append these methods to `WorkloadStorageEncryptionTests` in `tests/test_workload_storage_encryption.py`:

```python
    def test_diagnostic_script_exposes_expected_cli_options(self):
        script = (PROJECT_ROOT / "scripts" / "check_ebs_volume_encryption.py").read_text()

        self.assertIn("--namespace", script)
        self.assertIn("--storage-class", script)
        self.assertIn("--pvc", script)
        self.assertIn("--region", script)
        self.assertIn("get-ebs-encryption-by-default", script)
        self.assertIn("describe-volumes", script)

    def test_diagnostic_script_checks_storage_class_pvc_pv_and_volume(self):
        script = (PROJECT_ROOT / "scripts" / "check_ebs_volume_encryption.py").read_text()

        self.assertIn("check_storage_class", script)
        self.assertIn("list_pvcs", script)
        self.assertIn("get_pv", script)
        self.assertIn("extract_ebs_volume_id", script)
        self.assertIn("check_aws_volume", script)
        self.assertIn("Encrypted", script)
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
python -m unittest tests.test_workload_storage_encryption
```

Expected: ERROR because `scripts/check_ebs_volume_encryption.py` does not exist.

- [ ] **Step 3: Create the diagnostic script**

Create `scripts/check_ebs_volume_encryption.py`:

```python
#!/usr/bin/env python3
import argparse
import json
import re
import shutil
import subprocess
import sys


def run_json(command):
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True)
    except FileNotFoundError:
        raise RuntimeError(f"Required command not found: {command[0]}")
    except subprocess.CalledProcessError as error:
        stderr = error.stderr.strip()
        raise RuntimeError(f"Command failed: {' '.join(command)}\n{stderr}")

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"Command did not return JSON: {' '.join(command)}\n{error}")


def require_command(name):
    if shutil.which(name) is None:
        raise RuntimeError(f"Required command not found: {name}")


def aws_command(args, region):
    command = ["aws", *args, "--output", "json"]
    if region:
        command.extend(["--region", region])
    return command


def kubectl_get(resource, name=None, namespace=None):
    command = ["kubectl", "get", resource]
    if name:
        command.append(name)
    if namespace:
        command.extend(["-n", namespace])
    command.extend(["-o", "json"])
    return run_json(command)


def check_ebs_encryption_by_default(region):
    data = run_json(aws_command(["ec2", "get-ebs-encryption-by-default"], region))
    enabled = bool(data.get("EbsEncryptionByDefault"))
    status = "enabled" if enabled else "disabled"
    print(f"Account/region EBS encryption by default: {status}")
    if not enabled:
        print("WARNING: account/region EBS encryption by default is disabled.")
    return enabled


def check_storage_class(name):
    storage_class = kubectl_get("storageclass", name)
    parameters = storage_class.get("parameters", {})
    provisioner = storage_class.get("provisioner")
    encrypted = parameters.get("encrypted")

    print(f"StorageClass {name}: provisioner={provisioner}, encrypted={encrypted}")

    if provisioner != "ebs.csi.aws.com":
        raise RuntimeError(f"StorageClass {name} does not use ebs.csi.aws.com.")
    if encrypted != "true":
        raise RuntimeError(f"StorageClass {name} does not set encrypted=true.")

    return storage_class


def list_pvcs(namespace, pvc_name=None):
    if pvc_name:
        return [kubectl_get("pvc", pvc_name, namespace)]

    pvc_list = kubectl_get("pvc", namespace=namespace)
    return pvc_list.get("items", [])


def pvc_uses_storage_class(pvc, storage_class_name):
    pvc_name = pvc["metadata"]["name"]
    pvc_storage_class = pvc.get("spec", {}).get("storageClassName")
    if pvc_storage_class != storage_class_name:
        print(f"Skipping PVC {pvc_name}: storageClassName={pvc_storage_class}")
        return False
    return True


def get_bound_pv_name(pvc):
    pvc_name = pvc["metadata"]["name"]
    pv_name = pvc.get("spec", {}).get("volumeName")
    if not pv_name:
        raise RuntimeError(f"PVC {pvc_name} is not bound to a PV.")
    return pv_name


def get_pv(name):
    return kubectl_get("pv", name)


def extract_ebs_volume_id(pv):
    pv_name = pv["metadata"]["name"]
    csi = pv.get("spec", {}).get("csi")
    if not csi:
        raise RuntimeError(f"PV {pv_name} is not CSI-backed.")

    driver = csi.get("driver")
    if driver != "ebs.csi.aws.com":
        raise RuntimeError(f"PV {pv_name} uses CSI driver {driver}, not ebs.csi.aws.com.")

    handle = csi.get("volumeHandle", "")
    match = re.search(r"(vol-[0-9a-fA-F]+)$", handle)
    if not match:
        raise RuntimeError(f"PV {pv_name} volumeHandle does not contain an EBS volume ID: {handle}")
    return match.group(1)


def check_aws_volume(volume_id, region):
    data = run_json(aws_command(["ec2", "describe-volumes", "--volume-ids", volume_id], region))
    volumes = data.get("Volumes", [])
    if not volumes:
        raise RuntimeError(f"AWS did not return EBS volume {volume_id}.")

    volume = volumes[0]
    encrypted = bool(volume.get("Encrypted"))
    print(f"EBS Volume {volume_id}: Encrypted={encrypted}, KmsKeyId={volume.get('KmsKeyId', 'aws/ebs or account default')}")
    if not encrypted:
        raise RuntimeError(f"EBS volume {volume_id} is not encrypted.")
    return volume


def check_pvcs(namespace, storage_class_name, pvc_name, region):
    pvcs = list_pvcs(namespace, pvc_name)
    checked = 0

    for pvc in pvcs:
        if not pvc_uses_storage_class(pvc, storage_class_name):
            continue

        pvc_name_value = pvc["metadata"]["name"]
        pv_name = get_bound_pv_name(pvc)
        pv = get_pv(pv_name)
        volume_id = extract_ebs_volume_id(pv)
        check_aws_volume(volume_id, region)
        print(f"PVC {namespace}/{pvc_name_value} -> PV {pv_name} -> {volume_id}: encrypted")
        checked += 1

    if checked == 0:
        raise RuntimeError(f"No PVCs in namespace {namespace} use StorageClass {storage_class_name}.")

    return checked


def parse_args(argv):
    parser = argparse.ArgumentParser(description="Check EKS PVC-backed EBS volume encryption.")
    parser.add_argument("--namespace", default="team-d", help="Namespace containing workload PVCs.")
    parser.add_argument("--storage-class", default="encrypted-gp3", help="Expected encrypted StorageClass name.")
    parser.add_argument("--pvc", help="Optional PVC name to inspect. Defaults to every PVC in the namespace.")
    parser.add_argument("--region", help="AWS region. Uses the AWS CLI default region when omitted.")
    return parser.parse_args(argv)


def main(argv):
    args = parse_args(argv)
    require_command("kubectl")
    require_command("aws")

    check_ebs_encryption_by_default(args.region)
    check_storage_class(args.storage_class)
    checked = check_pvcs(args.namespace, args.storage_class, args.pvc, args.region)
    print(f"PASS: verified {checked} PVC-backed EBS volume(s).")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except RuntimeError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
```

- [ ] **Step 4: Make the script executable**

Run:

```bash
chmod +x scripts/check_ebs_volume_encryption.py
```

- [ ] **Step 5: Run tests and verify they pass**

Run:

```bash
python -m unittest tests.test_workload_storage_encryption
```

Expected: PASS.

- [ ] **Step 6: Run the script help output**

Run:

```bash
python scripts/check_ebs_volume_encryption.py --help
```

Expected: exits 0 and displays `--namespace`, `--storage-class`, `--pvc`, and `--region`.

- [ ] **Step 7: Commit Task 3**

```bash
git add scripts/check_ebs_volume_encryption.py tests/test_workload_storage_encryption.py
git commit -m "feat: add ebs encryption diagnostic script"
```

## Task 4: Canary Lab Documentation and Final Verification

**Files:**
- Create: `docs/team-d-workload-storage-encryption.md`
- Modify: `README.md` only if this branch's existing README changes are part of the current task; otherwise leave it untouched.

- [ ] **Step 1: Create the lab guide**

Create `docs/team-d-workload-storage-encryption.md`:

```markdown
# team-d Workload Storage Encryption Lab

This lab applies encrypted EBS-backed workload storage to `team-d` only. It validates the Kubernetes resource chain and the actual AWS EBS volume metadata before expanding the pattern to other teams.

## Scope

- Canary namespace: `team-d`
- StorageClass: `encrypted-gp3`
- Provisioner: `ebs.csi.aws.com`
- Volume type: `gp3`
- Encryption: `encrypted: "true"`

Existing PVCs and EBS volumes are not migrated by this lab.

## Check Account-Level Safety Net

```bash
aws ec2 get-ebs-encryption-by-default --region ap-northeast-2
```

Expected: `EbsEncryptionByDefault` should be `true` for defense in depth. The `encrypted-gp3` StorageClass still explicitly requests encrypted workload volumes.

## Apply Platform StorageClass

```bash
terraform -chdir=environments/platform plan
terraform -chdir=environments/platform apply
```

Confirm the StorageClass:

```bash
kubectl get storageclass encrypted-gp3 -o yaml
```

Expected fields:

- `provisioner: ebs.csi.aws.com`
- `parameters.type: gp3`
- `parameters.encrypted: "true"`
- `volumeBindingMode: WaitForFirstConsumer`

## Apply team-d Canary Workload

```bash
kubectl apply -k manifests/overlays/team-d
```

If ArgoCD manages the environment, sync only the `team-d` Application.

```bash
kubectl -n argocd get applications
kubectl -n argocd patch application team-d --type merge -p '{"operation":{"sync":{}}}'
```

## Verify Kubernetes PVC and PV

```bash
kubectl -n team-d get pvc
kubectl -n team-d get pvc -o wide
kubectl get pv
```

Find the Redis PVC and confirm it uses `encrypted-gp3`.

```bash
PVC_NAME=$(kubectl -n team-d get pvc -o jsonpath='{.items[0].metadata.name}')
PV_NAME=$(kubectl -n team-d get pvc "$PVC_NAME" -o jsonpath='{.spec.volumeName}')
kubectl get pv "$PV_NAME" -o jsonpath='{.spec.csi.volumeHandle}{"\n"}'
```

## Verify Actual EBS Volume Encryption

Run the diagnostic script:

```bash
python scripts/check_ebs_volume_encryption.py \
  --namespace team-d \
  --storage-class encrypted-gp3 \
  --region ap-northeast-2
```

Expected result:

- The StorageClass check passes.
- At least one team-d PVC using `encrypted-gp3` is found.
- The resolved EBS volume reports `Encrypted=True`.
- The script exits with `PASS`.

## Notes

- Changing a StorageClass does not encrypt an existing unencrypted EBS volume.
- Existing unencrypted volumes require snapshot copy or data migration into a new encrypted volume.
- Sensitive or production workloads can add a customer managed KMS key with the EBS CSI `kmsKeyId` StorageClass parameter in a later change.
```

- [ ] **Step 2: Run all focused Python tests**

Run:

```bash
python -m unittest tests.test_k8s_base_module tests.test_team_overlay_consistency tests.test_workload_storage_encryption
```

Expected: PASS.

- [ ] **Step 3: Run Terraform module test**

Run from `modules/k8s-base`:

```bash
terraform test
```

Expected: PASS.

- [ ] **Step 4: Validate Kustomize render**

Run:

```bash
kubectl kustomize manifests/overlays/team-d
```

Expected: exits 0 and rendered output contains `storageClassName: encrypted-gp3`.

- [ ] **Step 5: Check git diff for unrelated changes**

Run:

```bash
git status --short
git diff --stat
```

Expected: current task changes are limited to StorageClass, team-d canary patch, diagnostic script, docs, and tests. Pre-existing unrelated dirty files remain untouched.

- [ ] **Step 6: Commit Task 4**

```bash
git add docs/team-d-workload-storage-encryption.md
git commit -m "docs: add team-d storage encryption lab"
```

## Self-Review

- Spec coverage:
  - `encrypted-gp3` StorageClass: Task 1.
  - `encrypted: "true"` parameter: Task 1.
  - team-d canary PVC application: Task 2.
  - StorageClass/PVC/PV/EBS diagnostic script: Task 3.
  - account/region EBS encryption-by-default check: Task 3 and Task 4.
  - live AWS `Encrypted=true` verification path: Task 3 and Task 4.
- Placeholder scan: no red-flag placeholders or unspecified test work remains.
- Type consistency: plan consistently uses `kubernetes_storage_class_v1.encrypted_gp3`, `encrypted-gp3`, `check_ebs_volume_encryption.py`, `team-d`, and `storageClassName`.
