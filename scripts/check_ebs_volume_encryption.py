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
    kms_key_id = volume.get("KmsKeyId", "aws/ebs or account default")
    print(f"EBS Volume {volume_id}: Encrypted={encrypted}, KmsKeyId={kms_key_id}")
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
