"""POST /jobs — submit a new image processing job.

Expects a JSON body:
    {
        "imageBase64": "<base64-encoded image bytes>",
        "filename": "photo.jpg",
        "operations": ["thumbnail", "grayscale", "blur"]   # optional
    }

Returns:
    {
        "jobId": "<uuid>",
        "status": "pending"
    }
"""
import base64
import json
import os
import uuid
from datetime import datetime, timezone

import boto3

BUCKET_NAME = os.environ["BUCKET_NAME"]
TABLE_NAME = os.environ["TABLE_NAME"]
QUEUE_URL = os.environ["QUEUE_URL"]

DEFAULT_OPERATIONS = ["thumbnail", "medium", "grayscale", "blur", "edges"]

s3 = boto3.client("s3")
dynamodb = boto3.client("dynamodb")
sqs = boto3.client("sqs")


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Methods": "POST,GET,OPTIONS",
        },
        "body": json.dumps(body),
    }


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def handler(event, context):
    # Parse body (API Gateway may base64-encode it if binary media types are set)
    try:
        raw_body = event.get("body") or "{}"
        if event.get("isBase64Encoded"):
            raw_body = base64.b64decode(raw_body).decode("utf-8")
        body = json.loads(raw_body)
    except (json.JSONDecodeError, ValueError) as e:
        return _response(400, {"error": f"Invalid JSON: {e}"})

    image_b64 = body.get("imageBase64")
    if not image_b64:
        return _response(400, {"error": "imageBase64 is required"})

    filename = body.get("filename", "upload.jpg")
    operations = body.get("operations") or DEFAULT_OPERATIONS

    # Decode image
    try:
        image_bytes = base64.b64decode(image_b64)
    except Exception as e:
        return _response(400, {"error": f"Invalid base64 image: {e}"})

    if len(image_bytes) == 0:
        return _response(400, {"error": "Empty image"})

    # Generate job ID and S3 key
    job_id = str(uuid.uuid4())
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else "jpg"
    if ext not in ("jpg", "jpeg", "png", "gif", "webp", "bmp"):
        ext = "jpg"
    input_key = f"inputs/{job_id}/original.{ext}"

    # Upload to S3
    content_type = "image/jpeg" if ext in ("jpg", "jpeg") else f"image/{ext}"
    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=input_key,
        Body=image_bytes,
        ContentType=content_type,
    )

    # Write DynamoDB record
    now = _now_iso()
    dynamodb.put_item(
        TableName=TABLE_NAME,
        Item={
            "jobId": {"S": job_id},
            "status": {"S": "pending"},
            "createdAt": {"S": now},
            "inputKey": {"S": input_key},
            "originalFilename": {"S": filename},
        },
    )

    # Send SQS message
    message = {
        "jobId": job_id,
        "inputKey": input_key,
        "operations": operations,
        "submittedAt": now,
    }
    sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps(message))

    return _response(202, {"jobId": job_id, "status": "pending"})
