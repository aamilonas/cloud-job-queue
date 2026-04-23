"""GET /jobs/{jobId} — get a single job by ID
GET /jobs — list jobs (most recent first, paginated via ?limit=N)

Returns DynamoDB records shaped as plain JSON. For completed jobs, also
returns presigned S3 URLs for each output variant (valid for 1 hour).
"""
import json
import os
from decimal import Decimal

import boto3

BUCKET_NAME = os.environ["BUCKET_NAME"]
TABLE_NAME = os.environ["TABLE_NAME"]

PRESIGNED_URL_TTL_SECONDS = 3600  # 1 hour

# Use the resource-level DynamoDB client for cleaner item parsing
dynamodb_resource = boto3.resource("dynamodb")
table = dynamodb_resource.Table(TABLE_NAME)
s3 = boto3.client("s3")


def _response(status_code: int, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Methods": "GET,OPTIONS",
        },
        "body": json.dumps(body, default=_json_default),
    }


def _json_default(o):
    if isinstance(o, Decimal):
        return int(o) if o % 1 == 0 else float(o)
    raise TypeError(f"Not JSON serializable: {type(o)}")


def _presign_outputs(item: dict) -> dict:
    outputs = item.get("outputs")
    if not outputs:
        return item

    presigned = {}
    for variant, key in outputs.items():
        presigned[variant] = s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": BUCKET_NAME, "Key": key},
            ExpiresIn=PRESIGNED_URL_TTL_SECONDS,
        )
    item["outputUrls"] = presigned
    return item


def _scan_all_jobs(max_items: int = 500) -> list:
    """Scan the full table with pagination.

    DynamoDB scan returns items in partition order, not sorted order.
    To reliably get the most recent N jobs we scan everything and sort
    client-side. For a demo-scale table this is fine — pay-per-request
    billing charges per item scanned but at <10k items it's fractions
    of a cent. A production build would use a GSI with a fixed partition
    key so Query replaces Scan entirely.
    """
    items = []
    last_key = None
    pages = 0
    max_pages = 10  # safety cap

    while pages < max_pages:
        scan_kwargs = {}
        if last_key:
            scan_kwargs["ExclusiveStartKey"] = last_key

        resp = table.scan(**scan_kwargs)
        items.extend(resp.get("Items", []))
        last_key = resp.get("LastEvaluatedKey")
        pages += 1

        if not last_key:
            break

    return items


def handler(event, context):
    path_params = event.get("pathParameters") or {}
    query_params = event.get("queryStringParameters") or {}
    job_id = path_params.get("jobId")

    # Single job lookup
    if job_id:
        resp = table.get_item(Key={"jobId": job_id})
        item = resp.get("Item")
        if not item:
            return _response(404, {"error": f"Job not found: {job_id}"})
        return _response(200, _presign_outputs(item))

    # List jobs — full scan, sort by createdAt desc, trim to limit
    try:
        limit = min(int(query_params.get("limit", "50")), 200)
    except ValueError:
        limit = 50

    all_items = _scan_all_jobs()
    all_items.sort(key=lambda x: x.get("createdAt", ""), reverse=True)
    items = all_items[:limit]

    return _response(
        200,
        {
            "jobs": items,
            "count": len(items),
            "totalJobs": len(all_items),
        },
    )