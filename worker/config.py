"""Configuration loaded from environment variables.

Set these when running locally (via a .env file or PowerShell env vars)
and they're automatically injected by ECS in Fargate.
"""
import os


class Config:
    # AWS
    AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

    # Resource identifiers
    QUEUE_URL = os.environ["QUEUE_URL"]
    BUCKET_NAME = os.environ["BUCKET_NAME"]
    TABLE_NAME = os.environ["TABLE_NAME"]

    # Worker tuning
    POLL_WAIT_SECONDS = int(os.environ.get("POLL_WAIT_SECONDS", "20"))
    MAX_MESSAGES_PER_POLL = int(os.environ.get("MAX_MESSAGES_PER_POLL", "1"))
    VISIBILITY_TIMEOUT = int(os.environ.get("VISIBILITY_TIMEOUT", "120"))

    # Logging
    LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")
