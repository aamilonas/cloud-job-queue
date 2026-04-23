resource "aws_dynamodb_table" "jobs" {
  name         = "${local.name_prefix}-jobs"
  billing_mode = "PAY_PER_REQUEST" # on-demand pricing, stays in free tier for this workload
  hash_key     = "jobId"

  attribute {
    name = "jobId"
    type = "S"
  }

  # Secondary index to query jobs by status (useful for the "GET /jobs" listing endpoint)
  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  global_secondary_index {
    name            = "status-createdAt-index"
    hash_key        = "status"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = false # not needed for dev, adds cost
  }
}
