# ---------------------------------------------------------------------------
# Task Execution Role
# Used by ECS itself to pull images from ECR and write logs to CloudWatch.
# This role is assumed by the ECS agent, NOT by the worker code.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.name_prefix}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------------------------------------------------------------------------
# Worker Task Role
# Assumed by the worker container itself. Grants the permissions the
# worker code needs: read/write S3, read/delete SQS messages, write DynamoDB.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "worker_task" {
  name               = "${local.name_prefix}-worker-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

data "aws_iam_policy_document" "worker_task" {
  # S3: read inputs, write outputs
  statement {
    sid    = "S3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.images.arn}/*"]
  }

  statement {
    sid       = "S3ListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.images.arn]
  }

  # SQS: receive, delete, change visibility on the main queue
  statement {
    sid    = "SQSAccess"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [aws_sqs_queue.jobs.arn]
  }

  # DynamoDB: update job status
  statement {
    sid    = "DynamoDBAccess"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
    ]
    resources = [aws_dynamodb_table.jobs.arn]
  }
}

resource "aws_iam_role_policy" "worker_task" {
  name   = "${local.name_prefix}-worker-task-policy"
  role   = aws_iam_role.worker_task.id
  policy = data.aws_iam_policy_document.worker_task.json
}

# ---------------------------------------------------------------------------
# Local-dev user policy
# Attached to your personal IAM user so you can run the worker locally
# against the real AWS resources (same permissions as the worker task role).
# This is optional but makes local testing painless.
# ---------------------------------------------------------------------------
# NOTE: we don't create the user itself — you already have terraform-admin
# which has AdministratorAccess, so local dev already works.
