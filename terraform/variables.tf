variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project name used as a prefix for all resources"
  type        = string
  default     = "cloud-job-queue"
}

variable "environment" {
  description = "Deployment environment (dev, prod, etc.)"
  type        = string
  default     = "dev"
}

variable "sqs_visibility_timeout_seconds" {
  description = "How long a message is invisible after a worker receives it"
  type        = number
  default     = 120
}

variable "sqs_max_receive_count" {
  description = "Number of times a message is retried before going to the DLQ"
  type        = number
  default     = 3
}
