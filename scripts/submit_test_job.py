"""Submit a test job directly to SQS (bypasses Lambda/API).

Usage:
    py submit_test_job.py path/to/image.jpg

This does what the Lambda will eventually do:
  1. Upload the image to S3 at inputs/{jobId}/original.{ext}
  2. Create a DynamoDB record with status=pending
  3. Send an SQS message to trigger a worker

Reads AWS resource names from Terraform outputs, so it Just Works
as long as terraform apply has completed.
"""
import json
import os
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

import boto3


def get_terraform_outputs() -> dict:
    """Run `terraform output -json` to get resource names."""
    tf_dir = Path(__file__).parent.parent / "terraform"
    result = subprocess.run(
        ["terraform", "output", "-json"],
        cwd=tf_dir,
        capture_output=True,
        text=True,
        check=True,
    )
    raw = json.loads(result.stdout)
    return {k: v["value"] for k, v in raw.items()}


def main():
    if len(sys.argv) != 2:
        print("Usage: py submit_test_job.py path/to/image.jpg")
        sys.exit(1)

    image_path = Path(sys.argv[1])
    if not image_path.is_file():
        print(f"Not a file: {image_path}")
        sys.exit(1)

    outputs = get_terraform_outputs()
    bucket = outputs["s3_bucket_name"]
    table = outputs["dynamodb_table_name"]
    queue_url = outputs["sqs_queue_url"]
    region = outputs["aws_region"]

    print(f"Bucket: {bucket}")
    print(f"Table:  {table}")
    print(f"Queue:  {queue_url}")

    s3 = boto3.client("s3", region_name=region)
    dynamodb = boto3.client("dynamodb", region_name=region)
    sqs = boto3.client("sqs", region_name=region)

    job_id = str(uuid.uuid4())
    ext = image_path.suffix.lstrip(".").lower() or "jpg"
    input_key = f"inputs/{job_id}/original.{ext}"
    now = datetime.now(timezone.utc).isoformat()

    # 1. Upload to S3
    print(f"\nUploading {image_path} to s3://{bucket}/{input_key}")
    s3.upload_file(str(image_path), bucket, input_key)

    # 2. Create DynamoDB record
    print(f"Creating DynamoDB record: jobId={job_id}")
    dynamodb.put_item(
        TableName=table,
        Item={
            "jobId": {"S": job_id},
            "status": {"S": "pending"},
            "createdAt": {"S": now},
            "inputKey": {"S": input_key},
        },
    )

    # 3. Enqueue
    message = {
        "jobId": job_id,
        "inputKey": input_key,
        "operations": ["thumbnail", "medium", "grayscale", "blur", "edges"],
        "submittedAt": now,
    }
    print("Sending SQS message")
    sqs.send_message(QueueUrl=queue_url, MessageBody=json.dumps(message))

    print(f"\n✓ Job submitted. jobId={job_id}")
    print(f"\nCheck status with:")
    print(f"  aws dynamodb get-item --table-name {table} --key '{{\"jobId\":{{\"S\":\"{job_id}\"}}}}'")


if __name__ == "__main__":
    main()
