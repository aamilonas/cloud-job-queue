# ---------------------------------------------------------------------------
# CloudWatch Dashboard
# Single-pane view of the entire system. Shown live during the professor
# demo to visualize the auto-scaling arc.
#
# Widget layout (24 cols x 24 rows grid):
#   Row 1:  [Queue Depth (12)]          [Worker Count (12)]
#   Row 2:  [Messages Sent Rate (8)]    [Job Duration p50/p90 (8)]    [Lambda Invocations (8)]
#   Row 3:  [DLQ Depth (8)]             [Lambda Errors (8)]           [API Gateway 5xx (8)]
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # -------------- Row 1: the hero widgets --------------
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "SQS Queue Depth"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Maximum"
          metrics = [
            [
              "AWS/SQS",
              "ApproximateNumberOfMessagesVisible",
              "QueueName",
              aws_sqs_queue.jobs.name,
              { label = "Main Queue" }
            ],
          ]
          yAxis = {
            left = {
              min   = 0
              label = "Messages"
            }
          }
          annotations = {
            horizontal = [
              { label = "Scale-up threshold", value = 1, color = "#2ca02c" },
              { label = "Step 2 threshold", value = 10, color = "#ff7f0e" },
              { label = "Step 3 threshold", value = 25, color = "#d62728" },
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "ECS Worker Count"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          period  = 60
          metrics = [
            [
              "ECS/ContainerInsights",
              "RunningTaskCount",
              "ServiceName",
              aws_ecs_service.worker.name,
              "ClusterName",
              aws_ecs_cluster.main.name,
              { label = "Running Tasks", stat = "Maximum" }
            ],
            [
              ".",
              "DesiredTaskCount",
              ".",
              ".",
              ".",
              ".",
              { label = "Desired Tasks", stat = "Maximum" }
            ],
          ]
          yAxis = {
            left = {
              min   = 0
              max   = 6
              label = "Tasks"
            }
          }
        }
      },

      # -------------- Row 2: throughput and performance --------------
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "Job Submission Rate"
          region = var.aws_region
          view   = "timeSeries"
          period = 60
          stat   = "Sum"
          metrics = [
            [
              "AWS/SQS",
              "NumberOfMessagesSent",
              "QueueName",
              aws_sqs_queue.jobs.name,
              { label = "Sent/min" }
            ],
            [
              ".",
              "NumberOfMessagesDeleted",
              ".",
              ".",
              { label = "Processed/min" }
            ],
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Invocations (submit_job)"
          region = var.aws_region
          view   = "timeSeries"
          period = 60
          stat   = "Sum"
          metrics = [
            [
              "AWS/Lambda",
              "Invocations",
              "FunctionName",
              aws_lambda_function.submit_job.function_name,
              { label = "Invocations" }
            ],
            [
              ".",
              "Duration",
              ".",
              ".",
              { label = "Avg duration (ms)", stat = "Average", yAxis = "right" }
            ],
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Invocations (get_job / get_metrics)"
          region = var.aws_region
          view   = "timeSeries"
          period = 60
          stat   = "Sum"
          metrics = [
            [
              "AWS/Lambda",
              "Invocations",
              "FunctionName",
              aws_lambda_function.get_job.function_name,
              { label = "get_job" }
            ],
            [
              ".",
              ".",
              ".",
              aws_lambda_function.get_metrics.function_name,
              { label = "get_metrics" }
            ],
          ]
        }
      },

      # -------------- Row 3: errors and health --------------
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 8
        height = 6
        properties = {
          title   = "Dead Letter Queue Depth"
          region  = var.aws_region
          view    = "timeSeries"
          period  = 60
          stat    = "Maximum"
          metrics = [
            [
              "AWS/SQS",
              "ApproximateNumberOfMessagesVisible",
              "QueueName",
              aws_sqs_queue.jobs_dlq.name,
              { label = "DLQ messages", color = "#d62728" }
            ],
          ]
          yAxis = {
            left = { min = 0, label = "Messages" }
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 12
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Errors"
          region = var.aws_region
          view   = "timeSeries"
          period = 60
          stat   = "Sum"
          metrics = [
            [
              "AWS/Lambda",
              "Errors",
              "FunctionName",
              aws_lambda_function.submit_job.function_name,
              { label = "submit_job", color = "#d62728" }
            ],
            [
              ".",
              ".",
              ".",
              aws_lambda_function.get_job.function_name,
              { label = "get_job", color = "#ff7f0e" }
            ],
            [
              ".",
              ".",
              ".",
              aws_lambda_function.get_metrics.function_name,
              { label = "get_metrics", color = "#bcbd22" }
            ],
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 12
        width  = 8
        height = 6
        properties = {
          title  = "API Gateway 4xx / 5xx"
          region = var.aws_region
          view   = "timeSeries"
          period = 60
          stat   = "Sum"
          metrics = [
            [
              "AWS/ApiGateway",
              "4xx",
              "ApiId",
              aws_apigatewayv2_api.main.id,
              { label = "4xx errors", color = "#ff7f0e" }
            ],
            [
              ".",
              "5xx",
              ".",
              ".",
              { label = "5xx errors", color = "#d62728" }
            ],
          ]
        }
      },
    ]
  })
}
