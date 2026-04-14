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
    ):
        self.aws_region = aws_region
        self.terraform_state_bucket = terraform_state_bucket
        self.terraform_state_region = terraform_state_region
        self.infra_state_key = infra_state_key
        self.platform_state_key = platform_state_key
        self.platform_infra_state_bucket = platform_infra_state_bucket or terraform_state_bucket
        self.platform_infra_state_region = platform_infra_state_region or terraform_state_region

    def _run(self, args: list[str], cwd: Path) -> None:
        subprocess.run(args, cwd=cwd, check=True)

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
        self._init(INFRA_DIR, self.infra_state_key)
        self._run(["terraform", "apply", "-input=false", "-auto-approve"], cwd=INFRA_DIR)

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

    def destroy_platform(self) -> None:
        self._init(PLATFORM_DIR, self.platform_state_key)
        self._run(
            [
                "terraform",
                "destroy",
                "-input=false",
                "-auto-approve",
                f"-var=infra_state_bucket_name={self.platform_infra_state_bucket}",
                f"-var=infra_state_region={self.platform_infra_state_region}",
            ],
            cwd=PLATFORM_DIR,
        )

    def destroy_infra(self) -> None:
        self._init(INFRA_DIR, self.infra_state_key)
        self._run(["terraform", "destroy", "-input=false", "-auto-approve"], cwd=INFRA_DIR)


class EnvironmentOrchestrator:
    def __init__(self, state_store: Any, terraform_runner: Any):
        self.state_store = state_store
        self.terraform_runner = terraform_runner

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

        should_apply_infra = current_state.get("infra_status") != "running" or not current_state["active_users"]
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
            self.terraform_runner.destroy_platform()
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
