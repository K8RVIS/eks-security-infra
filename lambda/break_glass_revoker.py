import datetime as dt
import json
import os
import traceback
from typing import Any

import boto3
from botocore.exceptions import ClientError


ADMIN_POLICY_ARN = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"


def utc_now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def is_not_found(exc: ClientError) -> bool:
    code = exc.response.get("Error", {}).get("Code")
    return code in {"ResourceNotFoundException", "NotFoundException"}


def publish(region: str, topic_arn: str | None, subject: str, payload: dict[str, Any]) -> None:
    if not topic_arn:
        return

    boto3.client("sns", region_name=region).publish(
        TopicArn=topic_arn,
        Subject=subject[:100],
        Message=json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True),
    )


def handler(event: dict[str, Any], _context: Any) -> dict[str, Any]:
    print(json.dumps({"message": "break-glass revoke started", "event": event}, ensure_ascii=False))

    table_name = os.environ["BREAK_GLASS_TABLE_NAME"]
    topic_arn = os.environ.get("SNS_TOPIC_ARN")
    region = os.environ.get("AWS_REGION_NAME") or os.environ.get("AWS_REGION") or "ap-northeast-2"

    grant_id = event["grant_id"]
    cluster_name = event["cluster_name"]
    principal_arn = event["principal_arn"]
    requested_by = event.get("requested_by", "unknown")
    reason = event.get("reason", "")

    eks = boto3.client("eks", region_name=region)
    table = boto3.resource("dynamodb", region_name=region).Table(table_name)
    revoked_at = utc_now_iso()

    disassociated = False
    deleted_entry = False

    try:
        print(json.dumps({"message": "disassociating access policy", "grant_id": grant_id}, ensure_ascii=False))
        try:
            eks.disassociate_access_policy(
                clusterName=cluster_name,
                principalArn=principal_arn,
                policyArn=ADMIN_POLICY_ARN,
            )
            disassociated = True
        except ClientError as exc:
            if not is_not_found(exc):
                raise
            print(json.dumps({"message": "access policy already absent", "grant_id": grant_id}, ensure_ascii=False))

        print(json.dumps({"message": "deleting access entry", "grant_id": grant_id}, ensure_ascii=False))
        try:
            eks.delete_access_entry(
                clusterName=cluster_name,
                principalArn=principal_arn,
            )
            deleted_entry = True
        except ClientError as exc:
            if not is_not_found(exc):
                raise
            print(json.dumps({"message": "access entry already absent", "grant_id": grant_id}, ensure_ascii=False))

        print(json.dumps({"message": "updating grant state", "grant_id": grant_id}, ensure_ascii=False))
        table.update_item(
            Key={"grant_id": grant_id},
            UpdateExpression=(
                "SET #status = :status, revoked_at = :revoked_at, "
                "revoked_by = :revoked_by, revoke_result = :revoke_result"
            ),
            ExpressionAttributeNames={"#status": "status"},
            ExpressionAttributeValues={
                ":status": "REVOKED",
                ":revoked_at": revoked_at,
                ":revoked_by": "eventbridge-scheduler",
                ":revoke_result": {
                    "disassociated": disassociated,
                    "deleted_access_entry": deleted_entry,
                },
            },
        )

        result = {
            "grant_id": grant_id,
            "cluster_name": cluster_name,
            "principal_arn": principal_arn,
            "requested_by": requested_by,
            "reason": reason,
            "revoked_at": revoked_at,
            "disassociated": disassociated,
            "deleted_access_entry": deleted_entry,
        }
        publish(region, topic_arn, f"Break-glass access revoked: {cluster_name}", result)
        print(json.dumps({"message": "break-glass revoke completed", **result}, ensure_ascii=False))
        return result
    except Exception as exc:
        print(
            json.dumps(
                {
                    "message": "break-glass revoke failed",
                    "grant_id": grant_id,
                    "cluster_name": cluster_name,
                    "principal_arn": principal_arn,
                    "error_type": type(exc).__name__,
                    "error": str(exc),
                    "traceback": traceback.format_exc(),
                },
                ensure_ascii=False,
            )
        )
        raise
