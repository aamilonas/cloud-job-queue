# ---------------------------------------------------------------------------
# Package Lambda source code into zip files at terraform-apply time.
# This avoids needing a separate build step — Terraform handles it.
# ---------------------------------------------------------------------------
data "archive_file" "submit_job" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/submit_job"
  output_path = "${path.module}/.builds/submit_job.zip"
}

data "archive_file" "get_job" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/get_job"
  output_path = "${path.module}/.builds/get_job.zip"
}

data "archive_file" "get_metrics" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/get_metrics"
  output_path = "${path.module}/.builds/get_metrics.zip"
}

data "archive_file" "get_metrics_history" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/get_metrics_history"
  output_path = "${path.module}/.builds/get_metrics_history.zip"
}

# ---------------------------------------------------------------------------
# Lambda execution role — shared by all three functions
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${local.name_prefix}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Basic Lambda logging permissions
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# App-specific permissions for all Lambdas
data "aws_iam_policy_document" "lambda_app" {
  # S3 read/write for job submission and presigned URL generation
  statement {
    sid    = "S3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.images.arn}/*"]
  }

  # DynamoDB read/write
  statement {
    sid    = "DynamoDBAccess"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Scan",
      "dynamodb:Query",
    ]
    resources = [
      aws_dynamodb_table.jobs.arn,
      "${aws_dynamodb_table.jobs.arn}/index/*",
    ]
  }

  # SQS send + read attributes (for metrics)
  statement {
    sid    = "SQSAccess"
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [
      aws_sqs_queue.jobs.arn,
      aws_sqs_queue.jobs_dlq.arn,
    ]
  }

  # ECS describe for metrics endpoint
  statement {
    sid       = "ECSDescribe"
    effect    = "Allow"
    actions   = ["ecs:DescribeServices"]
    resources = ["*"] # DescribeServices doesn't support resource-level IAM
  }

  # CloudWatch read for metrics history endpoint
  statement {
    sid       = "CloudWatchRead"
    effect    = "Allow"
    actions   = ["cloudwatch:GetMetricStatistics"]
    resources = ["*"] # GetMetricStatistics doesn't support resource-level IAM
  }
}

resource "aws_iam_role_policy" "lambda_app" {
  name   = "${local.name_prefix}-lambda-app-policy"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_app.json
}

# ---------------------------------------------------------------------------
# Lambda: submit_job
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "submit_job" {
  function_name    = "${local.name_prefix}-submit-job"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.submit_job.output_path
  source_code_hash = data.archive_file.submit_job.output_base64sha256
  timeout          = 30
  memory_size      = 512 # image upload needs some headroom

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.images.id
      TABLE_NAME  = aws_dynamodb_table.jobs.name
      QUEUE_URL   = aws_sqs_queue.jobs.url
    }
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}

resource "aws_cloudwatch_log_group" "submit_job" {
  name              = "/aws/lambda/${aws_lambda_function.submit_job.function_name}"
  retention_in_days = 7
}

# ---------------------------------------------------------------------------
# Lambda: get_job
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "get_job" {
  function_name    = "${local.name_prefix}-get-job"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.get_job.output_path
  source_code_hash = data.archive_file.get_job.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.images.id
      TABLE_NAME  = aws_dynamodb_table.jobs.name
    }
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}

resource "aws_cloudwatch_log_group" "get_job" {
  name              = "/aws/lambda/${aws_lambda_function.get_job.function_name}"
  retention_in_days = 7
}

# ---------------------------------------------------------------------------
# Lambda: get_metrics
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "get_metrics" {
  function_name    = "${local.name_prefix}-get-metrics"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.get_metrics.output_path
  source_code_hash = data.archive_file.get_metrics.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      QUEUE_URL    = aws_sqs_queue.jobs.url
      DLQ_URL      = aws_sqs_queue.jobs_dlq.url
      CLUSTER_NAME = aws_ecs_cluster.main.name
      SERVICE_NAME = aws_ecs_service.worker.name
    }
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}

resource "aws_cloudwatch_log_group" "get_metrics" {
  name              = "/aws/lambda/${aws_lambda_function.get_metrics.function_name}"
  retention_in_days = 7
}

# ---------------------------------------------------------------------------
# Lambda: get_metrics_history
# Reads historical metrics from CloudWatch for the frontend chart.
# Survives page refresh because the data lives in CloudWatch, not the browser.
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "get_metrics_history" {
  function_name    = "${local.name_prefix}-get-metrics-history"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.get_metrics_history.output_path
  source_code_hash = data.archive_file.get_metrics_history.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      QUEUE_NAME   = aws_sqs_queue.jobs.name
      CLUSTER_NAME = aws_ecs_cluster.main.name
      SERVICE_NAME = aws_ecs_service.worker.name
    }
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}

resource "aws_cloudwatch_log_group" "get_metrics_history" {
  name              = "/aws/lambda/${aws_lambda_function.get_metrics_history.function_name}"
  retention_in_days = 7
}
