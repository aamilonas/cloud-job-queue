"""GET /metrics — get real-time system metrics.

Returns:
    {
        "queueDepth": 12,        # SQS ApproximateNumberOfMessages
        "dlqDepth": 0,           # Dead letter queue depth
        "activeWorkers": 3,      # ECS running task count
        "desiredWorkers": 3,
        "timestamp": "2026-..."
    }
"""
import json
import os
from datetime import datetime, timezone

import boto3

QUEUE_URL = os.environ["QUEUE_URL"]
DLQ_URL = os.environ["DLQ_URL"]
CLUSTER_NAME = os.environ["CLUSTER_NAME"]
SERVICE_NAME = os.environ["SERVICE_NAME"]

sqs = boto3.client("sqs")
ecs = boto3.client("ecs")


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Methods": "GET,OPTIONS",
        },
        "body": json.dumps(body),
    }


def _get_queue_depth(queue_url: str) -> int:
    resp = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=["ApproximateNumberOfMessages"],
    )
    return int(resp["Attributes"]["ApproximateNumberOfMessages"])


def handler(event, context):
    queue_depth = _get_queue_depth(QUEUE_URL)
    dlq_depth = _get_queue_depth(DLQ_URL)

    svc_resp = ecs.describe_services(
        cluster=CLUSTER_NAME, services=[SERVICE_NAME]
    )
    services = svc_resp.get("services", [])
    if services:
        svc = services[0]
        running = svc.get("runningCount", 0)
        desired = svc.get("desiredCount", 0)
        pending = svc.get("pendingCount", 0)
    else:
        running = desired = pending = 0

    return _response(
        200,
        {
            "queueDepth": queue_depth,
            "dlqDepth": dlq_depth,
            "activeWorkers": running,
            "pendingWorkers": pending,
            "desiredWorkers": desired,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    )
