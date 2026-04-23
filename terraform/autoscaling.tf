# ---------------------------------------------------------------------------
# Application Auto Scaling target
# Registers the ECS service as a scalable target. Note: min_capacity = 0
# is supported by Application Auto Scaling for ECS, which gives us true
# scale-to-zero behavior.
# ---------------------------------------------------------------------------
resource "aws_appautoscaling_target" "worker" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.worker.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 0
  max_capacity       = 5
}

# ---------------------------------------------------------------------------
# Scale-UP policy (step scaling)
# Why step scaling and not target tracking?
# Target tracking on SQS doesn't naturally scale to zero — it can't compute
# a ratio when the metric is 0. Step scaling with CloudWatch alarms gives
# us explicit control at the boundaries, including scale-to-zero.
#
# Steps:
#   queueDepth >= 1   → at least 1 worker
#   queueDepth >= 10  → add 1 more (total 2)
#   queueDepth >= 25  → add 2 more (total up to max)
# ---------------------------------------------------------------------------
resource "aws_appautoscaling_policy" "scale_up" {
  name               = "${local.name_prefix}-scale-up"
  service_namespace  = aws_appautoscaling_target.worker.service_namespace
  resource_id        = aws_appautoscaling_target.worker.resource_id
  scalable_dimension = aws_appautoscaling_target.worker.scalable_dimension
  policy_type        = "StepScaling"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    # Cooldown spans the typical Fargate cold start. Without this, the alarm
    # re-fires every minute while the queue is non-empty during cold start
    # and queues up extra workers for jobs the first one will handle alone.
    cooldown                = 180
    metric_aggregation_type = "Maximum"

    # Messages 1 → 9: ensure at least 1 worker
    step_adjustment {
      metric_interval_lower_bound = 0
      metric_interval_upper_bound = 9
      scaling_adjustment          = 1
    }

    # Messages 10 → 24: add 1 more
    step_adjustment {
      metric_interval_lower_bound = 9
      metric_interval_upper_bound = 24
      scaling_adjustment          = 2
    }

    # Messages 25+: scale aggressively
    step_adjustment {
      metric_interval_lower_bound = 24
      scaling_adjustment          = 4
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "queue_has_messages" {
  alarm_name          = "${local.name_prefix}-queue-has-messages"
  alarm_description   = "Triggers scale-up when SQS has pending messages"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.jobs.name
  }

  alarm_actions = [aws_appautoscaling_policy.scale_up.arn]
}

# ---------------------------------------------------------------------------
# Scale-DOWN policy
# When queue is empty, remove all workers. The -999 step scaling adjustment
# with ExactCapacity says "set to exactly 0".
# ---------------------------------------------------------------------------
resource "aws_appautoscaling_policy" "scale_down" {
  name               = "${local.name_prefix}-scale-down"
  service_namespace  = aws_appautoscaling_target.worker.service_namespace
  resource_id        = aws_appautoscaling_target.worker.resource_id
  scalable_dimension = aws_appautoscaling_target.worker.scalable_dimension
  policy_type        = "StepScaling"

  step_scaling_policy_configuration {
    adjustment_type         = "ExactCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    # When alarm fires (queue empty), set capacity to 0
    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = 0
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "queue_empty" {
  alarm_name          = "${local.name_prefix}-queue-empty"
  alarm_description   = "Triggers scale-to-zero after 1 minute of empty queue"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.jobs.name
  }

  alarm_actions = [aws_appautoscaling_policy.scale_down.arn]
}
