#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import os
import re
import sys
import uuid
from typing import Any

import boto3
from botocore.exceptions import ClientError


ADMIN_POLICY_ARN = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0)


def iso(value: dt.datetime) -> str:
    return value.isoformat().replace("+00:00", "Z")


def is_not_found(exc: ClientError) -> bool:
    code = exc.response.get("Error", {}).get("Code")
    return code in {"ResourceNotFoundException", "NotFoundException"}


def is_conflict(exc: ClientError) -> bool:
    code = exc.response.get("Error", {}).get("Code")
    return code in {"ResourceInUseException", "ConflictException"}


def safe_name(value: str, max_length: int = 64) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_.-]", "-", value)
    return cleaned[:max_length].strip("-") or f"break-glass-{uuid.uuid4().hex[:12]}"


def github_output(values: dict[str, str]) -> None:
    path = os.environ.get("GITHUB_OUTPUT")
    if not path:
        return

    with open(path, "a", encoding="utf-8") as file:
        for key, value in values.items():
            file.write(f"{key}={value}\n")


def publish(region: str, topic_arn: str | None, subject: str, payload: dict[str, Any]) -> None:
    if not topic_arn:
        return

    boto3.client("sns", region_name=region).publish(
        TopicArn=topic_arn,
        Subject=subject[:100],
        Message=json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True),
    )


def ensure_access_entry(eks: Any, cluster_name: str, principal_arn: str) -> None:
    try:
        eks.describe_access_entry(clusterName=cluster_name, principalArn=principal_arn)
        return
    except ClientError as exc:
        if not is_not_found(exc):
            raise

    try:
        eks.create_access_entry(
            clusterName=cluster_name,
            principalArn=principal_arn,
            type="STANDARD",
        )
    except ClientError as exc:
        if not is_conflict(exc):
            raise


def associate_admin_policy(eks: Any, cluster_name: str, principal_arn: str) -> None:
    try:
        eks.associate_access_policy(
            clusterName=cluster_name,
            principalArn=principal_arn,
            policyArn=ADMIN_POLICY_ARN,
            accessScope={"type": "cluster"},
        )
    except ClientError as exc:
        if not is_conflict(exc):
            raise


def schedule_revoke(
    scheduler: Any,
    schedule_name: str,
    schedule_group: str,
    expires_at: dt.datetime,
    lambda_arn: str,
    scheduler_role_arn: str,
    payload: dict[str, Any],
) -> None:
    expression_time = expires_at.strftime("%Y-%m-%dT%H:%M:%S")
    request = {
        "Name": schedule_name,
        "GroupName": schedule_group,
        "ScheduleExpression": f"at({expression_time})",
        "FlexibleTimeWindow": {"Mode": "OFF"},
        "Target": {
            "Arn": lambda_arn,
            "RoleArn": scheduler_role_arn,
            "Input": json.dumps(payload, ensure_ascii=False),
        },
        "Description": f"Auto revoke break-glass grant {payload['grant_id']}",
    }

    try:
        request["ActionAfterCompletion"] = "DELETE"
        scheduler.create_schedule(**request)
    except scheduler.exceptions.ConflictException:
        scheduler.update_schedule(**request)
    except Exception as exc:
        if "Unknown parameter" not in str(exc):
            raise
        request.pop("ActionAfterCompletion", None)
        scheduler.create_schedule(**request)


def grant(args: argparse.Namespace) -> dict[str, Any]:
    now = utc_now()
    expires_at = now + dt.timedelta(minutes=args.ttl_minutes)
    ttl_epoch = int((now + dt.timedelta(days=args.state_retention_days)).timestamp())
    grant_id = args.request_id or f"bg-{now.strftime('%Y%m%d%H%M%S')}-{uuid.uuid4().hex[:8]}"
    schedule_name = safe_name(f"{grant_id}-revoke")

    eks = boto3.client("eks", region_name=args.region)
    dynamodb = boto3.resource("dynamodb", region_name=args.region)
    scheduler = boto3.client("scheduler", region_name=args.region)

    ensure_access_entry(eks, args.cluster_name, args.principal_arn)
    associate_admin_policy(eks, args.cluster_name, args.principal_arn)

    item = {
        "grant_id": grant_id,
        "status": "ACTIVE",
        "cluster_name": args.cluster_name,
        "principal_arn": args.principal_arn,
        "requested_by": args.requested_by,
        "approved_by": args.approved_by,
        "reason": args.reason,
        "created_at": iso(now),
        "expires_at": iso(expires_at),
        "ttl_minutes": args.ttl_minutes,
        "ttl_epoch": ttl_epoch,
        "github_run_id": args.github_run_id or "",
        "scheduler_group": args.scheduler_group,
        "scheduler_name": schedule_name,
    }
    dynamodb.Table(args.table_name).put_item(Item=item)

    revoke_payload = {
        "grant_id": grant_id,
        "cluster_name": args.cluster_name,
        "principal_arn": args.principal_arn,
        "requested_by": args.requested_by,
        "reason": args.reason,
    }
    schedule_revoke(
        scheduler,
        schedule_name,
        args.scheduler_group,
        expires_at,
        args.revoker_lambda_arn,
        args.scheduler_role_arn,
        revoke_payload,
    )

    publish(
        args.region,
        args.sns_topic_arn,
        f"Break-glass JIT granted: {args.cluster_name}",
        item,
    )

    outputs = {
        "grant_id": grant_id,
        "expires_at": iso(expires_at),
        "schedule_name": schedule_name,
        "principal_arn": args.principal_arn,
    }
    github_output(outputs)
    return {"result": "granted", **item}


def revoke(args: argparse.Namespace) -> dict[str, Any]:
    eks = boto3.client("eks", region_name=args.region)
    dynamodb = boto3.resource("dynamodb", region_name=args.region)
    table = dynamodb.Table(args.table_name)

    item = table.get_item(Key={"grant_id": args.grant_id}).get("Item")
    if not item:
        raise RuntimeError(f"grant_id not found: {args.grant_id}")

    cluster_name = item["cluster_name"]
    principal_arn = item["principal_arn"]
    revoked_at = iso(utc_now())

    try:
        eks.disassociate_access_policy(
            clusterName=cluster_name,
            principalArn=principal_arn,
            policyArn=ADMIN_POLICY_ARN,
        )
    except ClientError as exc:
        if not is_not_found(exc):
            raise

    try:
        eks.delete_access_entry(clusterName=cluster_name, principalArn=principal_arn)
    except ClientError as exc:
        if not is_not_found(exc):
            raise

    table.update_item(
        Key={"grant_id": args.grant_id},
        UpdateExpression="SET #status = :status, revoked_at = :revoked_at, revoked_by = :revoked_by",
        ExpressionAttributeNames={"#status": "status"},
        ExpressionAttributeValues={
            ":status": "REVOKED",
            ":revoked_at": revoked_at,
            ":revoked_by": args.revoked_by,
        },
    )

    result = {
        "result": "revoked",
        "grant_id": args.grant_id,
        "cluster_name": cluster_name,
        "principal_arn": principal_arn,
        "revoked_at": revoked_at,
    }
    publish(args.region, args.sns_topic_arn, f"Break-glass JIT revoked: {cluster_name}", result)
    return result


def update_review(args: argparse.Namespace) -> dict[str, Any]:
    dynamodb = boto3.resource("dynamodb", region_name=args.region)
    dynamodb.Table(args.table_name).update_item(
        Key={"grant_id": args.grant_id},
        UpdateExpression="SET review_issue_url = :url",
        ExpressionAttributeValues={":url": args.review_issue_url},
    )
    return {"result": "review-updated", "grant_id": args.grant_id, "review_issue_url": args.review_issue_url}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Manage JIT break-glass access for EKS.")
    subparsers = parser.add_subparsers(dest="operation", required=True)

    grant_parser = subparsers.add_parser("grant")
    grant_parser.add_argument("--region", required=True)
    grant_parser.add_argument("--cluster-name", required=True)
    grant_parser.add_argument("--principal-arn", required=True)
    grant_parser.add_argument("--table-name", required=True)
    grant_parser.add_argument("--scheduler-group", required=True)
    grant_parser.add_argument("--scheduler-role-arn", required=True)
    grant_parser.add_argument("--revoker-lambda-arn", required=True)
    grant_parser.add_argument("--ttl-minutes", type=int, required=True)
    grant_parser.add_argument("--state-retention-days", type=int, default=30)
    grant_parser.add_argument("--requested-by", required=True)
    grant_parser.add_argument("--approved-by", required=True)
    grant_parser.add_argument("--reason", required=True)
    grant_parser.add_argument("--request-id", default="")
    grant_parser.add_argument("--github-run-id", default="")
    grant_parser.add_argument("--sns-topic-arn", default="")

    revoke_parser = subparsers.add_parser("revoke")
    revoke_parser.add_argument("--region", required=True)
    revoke_parser.add_argument("--table-name", required=True)
    revoke_parser.add_argument("--grant-id", required=True)
    revoke_parser.add_argument("--revoked-by", default="manual")
    revoke_parser.add_argument("--sns-topic-arn", default="")

    review_parser = subparsers.add_parser("update-review")
    review_parser.add_argument("--region", required=True)
    review_parser.add_argument("--table-name", required=True)
    review_parser.add_argument("--grant-id", required=True)
    review_parser.add_argument("--review-issue-url", required=True)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    if args.operation == "grant" and args.ttl_minutes <= 0:
        parser.error("--ttl-minutes must be greater than 0")

    if args.operation == "grant":
        result = grant(args)
    elif args.operation == "revoke":
        result = revoke(args)
    elif args.operation == "update-review":
        result = update_review(args)
    else:
        raise RuntimeError(f"Unsupported operation: {args.operation}")

    print(json.dumps(result, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"::error::{exc}", file=sys.stderr)
        raise
