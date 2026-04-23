"""GET /metrics/history?window=1m|5m|15m|30m — historical system metrics.

Queries CloudWatch GetMetricStatistics for:
  - SQS ApproximateNumberOfMessagesVisible (queue depth)
  - ECS/ContainerInsights RunningTaskCount (active workers)

Period is fixed at 60s (matches CloudWatch SQS granularity). Returns both
series merged on timestamp so the frontend can chart them directly.

Response:
    {
        "window": "15m",
        "periodSeconds": 60,
        "points": [
            {"time": 1745400000000, "queueDepth": 0, "activeWorkers": 0},
            ...
        ]
    }
"""
import json
import os
from datetime import datetime, timedelta, timezone

import boto3

QUEUE_NAME = os.environ["QUEUE_NAME"]
CLUSTER_NAME = os.environ["CLUSTER_NAME"]
SERVICE_NAME = os.environ["SERVICE_NAME"]

cloudwatch = boto3.client("cloudwatch")

WINDOWS_MINUTES = {"1m": 1, "5m": 5, "15m": 15, "30m": 30}
DEFAULT_WINDOW = "15m"
PERIOD_SECONDS = 60


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


def _get_series(
    namespace: str,
    metric_name: str,
    dimensions: list,
    start: datetime,
    end: datetime,
) -> dict:
    """Returns {epoch_ms: value} for the given metric."""
    resp = cloudwatch.get_metric_statistics(
        Namespace=namespace,
        MetricName=metric_name,
        Dimensions=dimensions,
        StartTime=start,
        EndTime=end,
        Period=PERIOD_SECONDS,
        Statistics=["Maximum"],
    )
    points = {}
    for dp in resp.get("Datapoints", []):
        ts_ms = int(dp["Timestamp"].timestamp() * 1000)
        points[ts_ms] = int(dp["Maximum"])
    return points


def handler(event, context):
    qs = (event or {}).get("queryStringParameters") or {}
    window = qs.get("window", DEFAULT_WINDOW)
    if window not in WINDOWS_MINUTES:
        return _response(
            400,
            {
                "error": f"invalid window '{window}'",
                "accepted": list(WINDOWS_MINUTES.keys()),
            },
        )

    end = datetime.now(timezone.utc)
    start = end - timedelta(minutes=WINDOWS_MINUTES[window])

    queue_series = _get_series(
        namespace="AWS/SQS",
        metric_name="ApproximateNumberOfMessagesVisible",
        dimensions=[{"Name": "QueueName", "Value": QUEUE_NAME}],
        start=start,
        end=end,
    )
    worker_series = _get_series(
        namespace="ECS/ContainerInsights",
        metric_name="RunningTaskCount",
        dimensions=[
            {"Name": "ClusterName", "Value": CLUSTER_NAME},
            {"Name": "ServiceName", "Value": SERVICE_NAME},
        ],
        start=start,
        end=end,
    )

    all_timestamps = sorted(set(queue_series) | set(worker_series))
    points = [
        {
            "time": ts,
            "queueDepth": queue_series.get(ts, 0),
            "activeWorkers": worker_series.get(ts, 0),
        }
        for ts in all_timestamps
    ]

    return _response(
        200,
        {
            "window": window,
            "periodSeconds": PERIOD_SECONDS,
            "points": points,
        },
    )
