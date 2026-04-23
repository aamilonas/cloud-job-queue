output "aws_region" {
  description = "Region everything is deployed to"
  value       = var.aws_region
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for images"
  value       = aws_s3_bucket.images.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for images"
  value       = aws_s3_bucket.images.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB jobs table"
  value       = aws_dynamodb_table.jobs.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB jobs table"
  value       = aws_dynamodb_table.jobs.arn
}

output "sqs_queue_url" {
  description = "URL of the main SQS jobs queue"
  value       = aws_sqs_queue.jobs.url
}

output "sqs_queue_arn" {
  description = "ARN of the main SQS jobs queue"
  value       = aws_sqs_queue.jobs.arn
}

output "sqs_dlq_url" {
  description = "URL of the dead-letter queue"
  value       = aws_sqs_queue.jobs_dlq.url
}

output "sqs_dlq_arn" {
  description = "ARN of the dead-letter queue"
  value       = aws_sqs_queue.jobs_dlq.arn
}

output "ecr_repository_url" {
  description = "URL of the ECR repository for the worker image"
  value       = aws_ecr_repository.worker.repository_url
}

output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "worker_task_role_arn" {
  description = "ARN of the worker task role"
  value       = aws_iam_role.worker_task.arn
}

output "worker_log_group_name" {
  description = "CloudWatch log group for worker logs"
  value       = aws_cloudwatch_log_group.worker.name
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS worker service"
  value       = aws_ecs_service.worker.name
}

output "api_endpoint" {
  description = "Base URL of the HTTP API"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "sns_alarm_topic_arn" {
  description = "SNS topic that receives alarm notifications"
  value       = aws_sns_topic.alarms.arn
}
