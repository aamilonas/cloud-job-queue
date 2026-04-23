# ---------------------------------------------------------------------------
# ECS Cluster
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ---------------------------------------------------------------------------
# Networking: default VPC + default subnets
# For a dev/learning project we use the default VPC. A production setup
# would create a dedicated VPC with private subnets + NAT Gateway, but
# that's out of scope and NAT Gateways cost $32/month just to exist.
# ---------------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security group for the worker: allows all outbound, nothing inbound
# (workers don't need to accept incoming connections, they only poll SQS)
resource "aws_security_group" "worker" {
  name        = "${local.name_prefix}-worker-sg"
  description = "Worker task security group"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------------------
# Task Definition
# Defines the container, its resources, env vars, and IAM roles.
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "worker" {
  family                   = "${local.name_prefix}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"  # 0.25 vCPU
  memory                   = "512"  # 0.5 GB

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.worker_task.arn

  container_definitions = jsonencode([
    {
      name      = "worker"
      image     = "${aws_ecr_repository.worker.repository_url}:latest"
      essential = true

      environment = [
        { name = "AWS_REGION", value = var.aws_region },
        { name = "QUEUE_URL", value = aws_sqs_queue.jobs.url },
        { name = "BUCKET_NAME", value = aws_s3_bucket.images.id },
        { name = "TABLE_NAME", value = aws_dynamodb_table.jobs.name },
        { name = "LOG_LEVEL", value = "INFO" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.worker.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "worker"
        }
      }

      # If worker.py crashes, the container exits, ECS starts a new one
      stopTimeout = 30
    }
  ])
}

# ---------------------------------------------------------------------------
# ECS Service
# Runs the worker task and keeps it alive. Starts at desired_count = 0
# so we pay nothing until we deliberately turn it on. Phase 4 will add
# auto-scaling on SQS queue depth.
# ---------------------------------------------------------------------------
resource "aws_ecs_service" "worker" {
  name            = "${local.name_prefix}-worker-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = 0 # Start off. Phase 4 will auto-scale this.
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.worker.id]
    assign_public_ip = true # required in public subnets to reach ECR/SQS/S3
  }

  # Don't let Terraform fight with the auto-scaler (once Phase 4 is in place)
  lifecycle {
    ignore_changes = [desired_count]
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200
}
