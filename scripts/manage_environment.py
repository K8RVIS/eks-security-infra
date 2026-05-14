import argparse
import copy
import datetime as dt
import json
import os
import subprocess
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
INFRA_DIR = REPO_ROOT / "environments" / "infra"
PLATFORM_DIR = REPO_ROOT / "environments" / "platform"
EKS_CLUSTER_ADMIN_POLICY_ARN = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
SSO_RESERVED_ROLE_PATH = ":role/aws-reserved/sso.amazonaws.com/"
GENERIC_SSO_ACCESS_ENTRY_KEY = "team_user"


def default_state() -> dict[str, Any]:
    return {
        "infra_status": "stopped",
        "active_users": {},
        "active_namespaces": [],
        "pending_operation": None,
        "last_error": None,
        "updated_at": None,
    }


def utc_now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def normalize_eks_access_user_arns(values: dict[str, Any], role_to_assume: str = "") -> dict[str, str]:
    candidates: list[tuple[str, str]] = []

    for raw_name, raw_arn in values.items():
        name = str(raw_name).strip()
        arn = str(raw_arn).strip()
        if not arn:
            continue

        if (name.startswith("team_") or name.startswith("team-")) and SSO_RESERVED_ROLE_PATH in arn:
            name = GENERIC_SSO_ACCESS_ENTRY_KEY

        candidates.append((name or GENERIC_SSO_ACCESS_ENTRY_KEY, arn))

    role_to_assume = role_to_assume.strip()
    if role_to_assume:
        candidates.append(("github_actions", role_to_assume))

    def priority(name: str) -> tuple[int, str]:
        preferred = {GENERIC_SSO_ACCESS_ENTRY_KEY: 0, "github_actions": 1, "bot": 2}
        return (preferred.get(name, 3), name)

    preferred_name_by_arn: dict[str, str] = {}
    for name, arn in candidates:
        current_name = preferred_name_by_arn.get(arn)
        if current_name is None or priority(name) < priority(current_name):
            preferred_name_by_arn[arn] = name

    normalized: dict[str, str] = {}
    for arn, name in sorted(preferred_name_by_arn.items(), key=lambda item: priority(item[1])):
        final_name = name
        suffix = 2
        while final_name in normalized:
            final_name = f"{name}_{suffix}"
            suffix += 1

        normalized[final_name] = arn

    return normalized


def desired_eks_access_user_arns_from_env() -> dict[str, str]:
    raw = os.environ.get("TF_VAR_user_iam_arn", "").strip()
    if not raw:
        return {}

    try:
        values = json.loads(raw)
    except json.JSONDecodeError:
        return {}

    if not isinstance(values, dict):
        return {}

    return normalize_eks_access_user_arns(values)


def normalize_eks_access_user_arns_env() -> dict[str, str]:
    normalized = desired_eks_access_user_arns_from_env()
    if normalized:
        os.environ["TF_VAR_user_iam_arn"] = json.dumps(normalized, separators=(",", ":"))
    return normalized


class S3StateStore:
    def __init__(self, bucket: str, key: str, region_name: str | None = None):
        self.bucket = bucket
        self.key = key
        self.region_name = region_name

    @property
    def client(self):
        import boto3

        return boto3.client("s3", region_name=self.region_name)

    def read_state(self) -> dict[str, Any]:
        try:
            response = self.client.get_object(Bucket=self.bucket, Key=self.key)
        except Exception as exc:
            error_response = getattr(exc, "response", {}) or {}
            error_code = error_response.get("Error", {}).get("Code")
            if error_code in {"NoSuchKey", "404", "NoSuchBucket"}:
                return default_state()
            raise

        body = response["Body"].read().decode("utf-8")
        if not body.strip():
            return default_state()

        state = default_state()
        state.update(json.loads(body))
        return state

    def write_state(self, state: dict[str, Any]) -> None:
        self.client.put_object(
            Bucket=self.bucket,
            Key=self.key,
            Body=json.dumps(state, ensure_ascii=False, sort_keys=True).encode("utf-8"),
            ContentType="application/json",
        )


class TerraformRunner:
    def __init__(
        self,
        aws_region: str,
        terraform_state_bucket: str,
        terraform_state_region: str,
        infra_state_key: str = "infra/terraform.tfstate",
        platform_state_key: str = "platform/terraform.tfstate",
        platform_infra_state_bucket: str | None = None,
        platform_infra_state_region: str | None = None,
        eks_cluster_name: str | None = None,
        eks_client: Any | None = None,
    ):
        self.aws_region = aws_region
        self.terraform_state_bucket = terraform_state_bucket
        self.terraform_state_region = terraform_state_region
        self.infra_state_key = infra_state_key
        self.platform_state_key = platform_state_key
        self.platform_infra_state_bucket = platform_infra_state_bucket or terraform_state_bucket
        self.platform_infra_state_region = platform_infra_state_region or terraform_state_region
        self.eks_cluster_name = eks_cluster_name
        self._eks_client = eks_client

    def _run(self, args: list[str], cwd: Path) -> None:
        subprocess.run(args, cwd=cwd, check=True)

    def _run_capture(self, args: list[str], cwd: Path) -> str:
        result = subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True)
        return result.stdout

    def _init(self, cwd: Path, state_key: str) -> None:
        self._run(
            [
                "terraform",
                "init",
                "-input=false",
                f"-backend-config=bucket={self.terraform_state_bucket}",
                f"-backend-config=key={state_key}",
                f"-backend-config=region={self.terraform_state_region}",
            ],
            cwd=cwd,
        )

    def apply_infra(self) -> None:
        desired_access_entries = normalize_eks_access_user_arns_env()
        self._init(INFRA_DIR, self.infra_state_key)
        self._import_existing_eks_access_entries(desired_access_entries)
        self._run(["terraform", "apply", "-input=false", "-auto-approve"], cwd=INFRA_DIR)

    @property
    def eks_client(self):
        if self._eks_client is None:
            import boto3

            self._eks_client = boto3.client("eks", region_name=self.aws_region)
        return self._eks_client

    def _terraform_state_addresses(self) -> set[str]:
        try:
            output = self._run_capture(["terraform", "state", "list"], cwd=INFRA_DIR)
        except subprocess.CalledProcessError:
            return set()

        return {line.strip() for line in output.splitlines() if line.strip()}

    def _is_resource_not_found(self, exc: Exception) -> bool:
        error_response = getattr(exc, "response", {}) or {}
        error_code = error_response.get("Error", {}).get("Code")
        return error_code in {"ResourceNotFoundException", "NotFoundException"}

    def _access_entry_exists(self, principal_arn: str) -> bool:
        if not self.eks_cluster_name:
            return False

        try:
            self.eks_client.describe_access_entry(
                clusterName=self.eks_cluster_name,
                principalArn=principal_arn,
            )
            return True
        except Exception as exc:
            if self._is_resource_not_found(exc) or exc.__class__.__name__ == "ResourceNotFoundException":
                return False
            raise

    def _admin_policy_association_exists(self, principal_arn: str) -> bool:
        if not self.eks_cluster_name:
            return False

        try:
            response = self.eks_client.list_associated_access_policies(
                clusterName=self.eks_cluster_name,
                principalArn=principal_arn,
            )
        except Exception as exc:
            if self._is_resource_not_found(exc) or exc.__class__.__name__ == "ResourceNotFoundException":
                return False
            raise

        return any(
            policy.get("policyArn") == EKS_CLUSTER_ADMIN_POLICY_ARN
            for policy in response.get("associatedAccessPolicies", [])
        )

    def _import_existing_eks_access_entries(self, desired_access_entries: dict[str, str] | None = None) -> None:
        if not self.eks_cluster_name:
            return

        desired_access_entries = desired_access_entries or desired_eks_access_user_arns_from_env()
        if not desired_access_entries:
            return

        state_addresses = self._terraform_state_addresses()
        for name, principal_arn in desired_access_entries.items():
            access_entry_address = f'module.eks.aws_eks_access_entry.this["{name}"]'
            if access_entry_address not in state_addresses and self._access_entry_exists(principal_arn):
                self._run(
                    [
                        "terraform",
                        "import",
                        access_entry_address,
                        f"{self.eks_cluster_name}:{principal_arn}",
                    ],
                    cwd=INFRA_DIR,
                )
                state_addresses.add(access_entry_address)

            policy_association_address = f'module.eks.aws_eks_access_policy_association.this["{name}-admin"]'
            if (
                policy_association_address not in state_addresses
                and self._admin_policy_association_exists(principal_arn)
            ):
                self._run(
                    [
                        "terraform",
                        "import",
                        policy_association_address,
                        f"{self.eks_cluster_name}#{principal_arn}#{EKS_CLUSTER_ADMIN_POLICY_ARN}",
                    ],
                    cwd=INFRA_DIR,
                )
                state_addresses.add(policy_association_address)

    def apply_platform(self, namespaces: list[str]) -> None:
        self._init(PLATFORM_DIR, self.platform_state_key)
        self._run(
            [
                "terraform",
                "apply",
                "-input=false",
                "-auto-approve",
                f"-var=infra_state_bucket_name={self.platform_infra_state_bucket}",
                f"-var=infra_state_region={self.platform_infra_state_region}",
                f"-var=team_names={json.dumps(namespaces)}",
            ],
            cwd=PLATFORM_DIR,
        )

    def _platform_var_args(self, namespaces: list[str] | None = None) -> list[str]:
        args = [
            f"-var=infra_state_bucket_name={self.platform_infra_state_bucket}",
            f"-var=infra_state_region={self.platform_infra_state_region}",
        ]
        if namespaces is not None:
            args.append(f"-var=team_names={json.dumps(namespaces)}")
        return args

    def destroy_platform(self, namespaces: list[str] | None = None) -> None:
        self._init(PLATFORM_DIR, self.platform_state_key)
        platform_var_args = self._platform_var_args(namespaces)
        if namespaces:
            self._run(
                [
                    "terraform",
                    "apply",
                    "-input=false",
                    "-auto-approve",
                    "-target=module.argocd.helm_release.argocd_apps",
                    *platform_var_args,
                ],
                cwd=PLATFORM_DIR,
            )
        self._run(
            [
                "terraform",
                "destroy",
                "-input=false",
                "-auto-approve",
                "-target=module.argocd.helm_release.argocd_apps",
                *platform_var_args,
            ],
            cwd=PLATFORM_DIR,
        )
        self._run(
            [
                "terraform",
                "destroy",
                "-input=false",
                "-auto-approve",
                *platform_var_args,
            ],
            cwd=PLATFORM_DIR,
        )

    def destroy_infra(self) -> None:
        self._init(INFRA_DIR, self.infra_state_key)
        self._run(["terraform", "destroy", "-input=false", "-auto-approve"], cwd=INFRA_DIR)


class EnvironmentOrchestrator:
    def __init__(self, state_store: Any, terraform_runner: Any, refresh_infra_on_start: bool = False):
        self.state_store = state_store
        self.terraform_runner = terraform_runner
        self.refresh_infra_on_start = refresh_infra_on_start

    def run(self, operation: str, slack_user_id: str, namespace: str, request_id: str) -> dict[str, Any]:
        current_state = self._normalize_state(self.state_store.read_state())
        pending_state = copy.deepcopy(current_state)
        pending_state["pending_operation"] = {
            "operation": operation,
            "slack_user_id": slack_user_id,
            "namespace": namespace,
            "request_id": request_id,
            "updated_at": utc_now_iso(),
        }
        self.state_store.write_state(pending_state)

        try:
            if operation == "start":
                next_state = self._handle_start(current_state, slack_user_id, namespace)
            elif operation == "stop":
                next_state = self._handle_stop(current_state, slack_user_id)
            else:
                raise ValueError(f"Unsupported operation: {operation}")
        except Exception as exc:
            failed_state = copy.deepcopy(current_state)
            failed_state["pending_operation"] = None
            failed_state["last_error"] = {
                "request_id": request_id,
                "operation": operation,
                "slack_user_id": slack_user_id,
                "namespace": namespace,
                "message": str(exc),
                "updated_at": utc_now_iso(),
            }
            self.state_store.write_state(failed_state)
            raise

        next_state["pending_operation"] = None
        next_state["last_error"] = None
        next_state["updated_at"] = utc_now_iso()
        self.state_store.write_state(next_state)
        return next_state

    def _normalize_state(self, state: dict[str, Any]) -> dict[str, Any]:
        normalized = default_state()
        normalized.update(state or {})
        normalized["active_users"] = dict(normalized.get("active_users") or {})
        normalized["active_namespaces"] = sorted(set(normalized.get("active_namespaces") or []))
        return normalized

    def _handle_start(self, current_state: dict[str, Any], slack_user_id: str, namespace: str) -> dict[str, Any]:
        next_state = copy.deepcopy(current_state)
        next_state["active_users"][slack_user_id] = namespace
        next_state["active_namespaces"] = sorted(set(next_state["active_users"].values()))

        should_apply_infra = (
            current_state.get("infra_status") != "running"
            or not current_state["active_users"]
            or self.refresh_infra_on_start
        )
        if should_apply_infra:
            self.terraform_runner.apply_infra()

        if should_apply_infra or next_state["active_users"] != current_state["active_users"]:
            self.terraform_runner.apply_platform(next_state["active_namespaces"])

        next_state["infra_status"] = "running"
        return next_state

    def _handle_stop(self, current_state: dict[str, Any], slack_user_id: str) -> dict[str, Any]:
        next_state = copy.deepcopy(current_state)
        next_state["active_users"].pop(slack_user_id, None)
        next_state["active_namespaces"] = sorted(set(next_state["active_users"].values()))

        if current_state.get("infra_status") != "running":
            next_state["infra_status"] = "stopped"
            return next_state

        if not next_state["active_users"]:
            self.terraform_runner.destroy_platform(current_state["active_namespaces"])
            self.terraform_runner.destroy_infra()
            next_state["infra_status"] = "stopped"
            return next_state

        if next_state["active_users"] != current_state["active_users"]:
            self.terraform_runner.apply_platform(next_state["active_namespaces"])

        next_state["infra_status"] = "running"
        return next_state


def build_runner_from_env() -> TerraformRunner:
    return TerraformRunner(
        aws_region=os.environ.get("AWS_REGION", "ap-northeast-2"),
        terraform_state_bucket=os.environ["TERRAFORM_STATE_BUCKET"],
        terraform_state_region=os.environ.get("TERRAFORM_STATE_REGION", os.environ.get("AWS_REGION", "ap-northeast-2")),
        infra_state_key=os.environ.get("INFRA_TERRAFORM_STATE_KEY", "infra/terraform.tfstate"),
        platform_state_key=os.environ.get("PLATFORM_TERRAFORM_STATE_KEY", "platform/terraform.tfstate"),
        platform_infra_state_bucket=os.environ.get("PLATFORM_INFRA_STATE_BUCKET"),
        platform_infra_state_region=os.environ.get("PLATFORM_INFRA_STATE_REGION"),
        eks_cluster_name=os.environ.get("EKS_CLUSTER_NAME") or "eks-secure-infra-dev",
    )


def build_state_store_from_env() -> S3StateStore:
    return S3StateStore(
        bucket=os.environ["ORCHESTRATION_STATE_BUCKET"],
        key=os.environ["ORCHESTRATION_STATE_KEY"],
        region_name=os.environ.get("AWS_REGION", "ap-northeast-2"),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Manage infra/platform environment lifecycle.")
    parser.add_argument("--operation", required=True, choices=["start", "stop"])
    parser.add_argument("--slack-user-id", required=True)
    parser.add_argument("--namespace", required=True)
    parser.add_argument("--request-id", required=True)
    args = parser.parse_args()

    orchestrator = EnvironmentOrchestrator(
        state_store=build_state_store_from_env(),
        terraform_runner=build_runner_from_env(),
        refresh_infra_on_start=bool(os.environ.get("TF_VAR_user_iam_arn", "").strip()),
    )
    result = orchestrator.run(
        operation=args.operation,
        slack_user_id=args.slack_user_id,
        namespace=args.namespace,
        request_id=args.request_id,
    )
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
