variable "alarm_email" {
  description = "Email address to receive alarm notifications. Leave empty to skip email subscription."
  type        = string
  default     = ""
}

resource "aws_sns_topic" "alarms" {
  name = "${local.name_prefix}-alarms"
}

# Email subscription only if an address was provided
resource "aws_sns_topic_subscription" "alarm_email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ---------------------------------------------------------------------------
# Operational alarms — these publish to SNS when triggered
# ---------------------------------------------------------------------------

# DLQ has any messages at all (something is failing)
resource "aws_cloudwatch_metric_alarm" "dlq_has_messages" {
  alarm_name          = "${local.name_prefix}-dlq-has-messages"
  alarm_description   = "Dead letter queue has messages — job processing is failing"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.jobs_dlq.name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# Lambda error rate on the submit_job function
resource "aws_cloudwatch_metric_alarm" "submit_job_errors" {
  alarm_name          = "${local.name_prefix}-submit-job-errors"
  alarm_description   = "submit_job Lambda is throwing errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 3
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.submit_job.function_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
}
