"""Worker main loop.

Long-polls SQS for job messages, processes images, updates status in DynamoDB.
Runs forever until SIGTERM (ECS stop) or Ctrl-C.

Flow for each job:
  1. Receive SQS message
  2. Parse jobId, inputKey, operations from body
  3. Update DynamoDB: status = "processing"
  4. Download input image from S3
  5. Run each requested operation, upload result to S3
  6. Update DynamoDB: status = "completed" (with output keys + duration)
  7. Delete SQS message
  8. On failure: log, skip delete (SQS will redeliver after visibility timeout)
"""
import json
import logging
import signal
import sys
import time
from datetime import datetime, timezone
from typing import Any, Dict

import boto3
from botocore.exceptions import ClientError

from config import Config
from processor import process_operation

# ---------------------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=Config.LOG_LEVEL,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger("worker")

# ---------------------------------------------------------------------------
# AWS clients (boto3 picks up credentials from env, ~/.aws, or IAM role)
# ---------------------------------------------------------------------------
sqs = boto3.client("sqs", region_name=Config.AWS_REGION)
s3 = boto3.client("s3", region_name=Config.AWS_REGION)
dynamodb = boto3.client("dynamodb", region_name=Config.AWS_REGION)

# ---------------------------------------------------------------------------
# Graceful shutdown
# ---------------------------------------------------------------------------
_shutdown = False


def _handle_signal(signum, _frame):
    global _shutdown
    logger.info("Received signal %s, shutting down after current job...", signum)
    _shutdown = True


signal.signal(signal.SIGTERM, _handle_signal)
signal.signal(signal.SIGINT, _handle_signal)


# ---------------------------------------------------------------------------
# DynamoDB helpers
# ---------------------------------------------------------------------------
def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def update_job_processing(job_id: str) -> None:
    """Mark a job as in-progress."""
    dynamodb.update_item(
        TableName=Config.TABLE_NAME,
        Key={"jobId": {"S": job_id}},
        UpdateExpression="SET #s = :s, startedAt = :t",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={
            ":s": {"S": "processing"},
            ":t": {"S": _now_iso()},
        },
    )


def update_job_completed(
    job_id: str, output_keys: Dict[str, str], duration_ms: int
) -> None:
    """Mark a job as done and record where the outputs live."""
    # DynamoDB map of variant name -> S3 key
    output_map = {k: {"S": v} for k, v in output_keys.items()}

    dynamodb.update_item(
        TableName=Config.TABLE_NAME,
        Key={"jobId": {"S": job_id}},
        UpdateExpression="SET #s = :s, completedAt = :t, outputs = :o, durationMs = :d",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={
            ":s": {"S": "completed"},
            ":t": {"S": _now_iso()},
            ":o": {"M": output_map},
            ":d": {"N": str(duration_ms)},
        },
    )


def update_job_failed(job_id: str, error: str) -> None:
    """Mark a job as failed."""
    dynamodb.update_item(
        TableName=Config.TABLE_NAME,
        Key={"jobId": {"S": job_id}},
        UpdateExpression="SET #s = :s, failedAt = :t, errorMessage = :e",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={
            ":s": {"S": "failed"},
            ":t": {"S": _now_iso()},
            ":e": {"S": error[:1000]},  # cap error length
        },
    )


# ---------------------------------------------------------------------------
# Job processing
# ---------------------------------------------------------------------------
def process_job(message_body: Dict[str, Any]) -> None:
    """Process a single job message. Raises on any failure."""
    job_id = message_body["jobId"]
    input_key = message_body["inputKey"]
    operations = message_body.get("operations", ["thumbnail", "grayscale", "blur"])

    logger.info("Processing job %s (input=%s, ops=%s)", job_id, input_key, operations)
    start = time.time()

    update_job_processing(job_id)

    # Download input
    logger.info("Downloading s3://%s/%s", Config.BUCKET_NAME, input_key)
    obj = s3.get_object(Bucket=Config.BUCKET_NAME, Key=input_key)
    image_bytes = obj["Body"].read()
    logger.info("Downloaded %d bytes", len(image_bytes))

    # Process each operation and upload
    output_keys: Dict[str, str] = {}
    for op_name in operations:
        variant, output_bytes = process_operation(op_name, image_bytes)
        output_key = f"outputs/{job_id}/{variant}.jpg"
        s3.put_object(
            Bucket=Config.BUCKET_NAME,
            Key=output_key,
            Body=output_bytes,
            ContentType="image/jpeg",
        )
        output_keys[variant] = output_key
        logger.info("Uploaded s3://%s/%s", Config.BUCKET_NAME, output_key)

    duration_ms = int((time.time() - start) * 1000)
    update_job_completed(job_id, output_keys, duration_ms)
    logger.info("Completed job %s in %d ms", job_id, duration_ms)


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
def poll_once() -> int:
    """Poll SQS once. Returns number of messages processed."""
    resp = sqs.receive_message(
        QueueUrl=Config.QUEUE_URL,
        MaxNumberOfMessages=Config.MAX_MESSAGES_PER_POLL,
        WaitTimeSeconds=Config.POLL_WAIT_SECONDS,
        VisibilityTimeout=Config.VISIBILITY_TIMEOUT,
    )

    messages = resp.get("Messages", [])
    if not messages:
        return 0

    for msg in messages:
        receipt_handle = msg["ReceiptHandle"]
        message_id = msg["MessageId"]
        job_id = None

        try:
            body = json.loads(msg["Body"])
            job_id = body.get("jobId", "<unknown>")
            process_job(body)
            # Only delete on success. On failure, let SQS redeliver.
            sqs.delete_message(QueueUrl=Config.QUEUE_URL, ReceiptHandle=receipt_handle)
            logger.info("Deleted message %s from queue", message_id)
        except json.JSONDecodeError as e:
            logger.error("Invalid JSON in message %s: %s — deleting", message_id, e)
            # Malformed messages can never succeed on retry. Delete immediately
            # so they don't keep the queue alarm in ALARM state for 3 redelivery
            # cycles. (True DLQ-worthy errors come from valid messages that
            # fail during processing, which we let SQS redeliver below.)
            try:
                sqs.delete_message(QueueUrl=Config.QUEUE_URL, ReceiptHandle=receipt_handle)
            except Exception:
                logger.exception("Failed to delete malformed message %s", message_id)
        except ClientError as e:
            logger.exception("AWS error processing job %s: %s", job_id, e)
            if job_id and job_id != "<unknown>":
                try:
                    update_job_failed(job_id, str(e))
                except Exception:
                    logger.exception("Failed to update job status to failed")
        except Exception as e:
            logger.exception("Error processing job %s: %s", job_id, e)
            if job_id and job_id != "<unknown>":
                try:
                    update_job_failed(job_id, str(e))
                except Exception:
                    logger.exception("Failed to update job status to failed")

    return len(messages)


def main() -> None:
    logger.info("Worker starting")
    logger.info("  Region:     %s", Config.AWS_REGION)
    logger.info("  Queue URL:  %s", Config.QUEUE_URL)
    logger.info("  Bucket:     %s", Config.BUCKET_NAME)
    logger.info("  Table:      %s", Config.TABLE_NAME)

    while not _shutdown:
        try:
            n = poll_once()
            if n == 0:
                logger.debug("No messages received, continuing long poll")
        except Exception:
            logger.exception("Unexpected error in poll loop; sleeping 5s before retry")
            time.sleep(5)

    logger.info("Worker stopped")


if __name__ == "__main__":
    main()
