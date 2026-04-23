# ---------------------------------------------------------------------------
# API Gateway HTTP API (v2)
# HTTP APIs are cheaper and simpler than REST APIs (v1). For a dev project
# they're the right choice — less config, lower latency, automatic CORS.
# ---------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "main" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"
  description   = "Cloud Job Queue API"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 3600
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }
}

# ---------------------------------------------------------------------------
# Lambda integrations
# ---------------------------------------------------------------------------
resource "aws_apigatewayv2_integration" "submit_job" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.submit_job.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "get_job" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.get_job.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "get_metrics" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.get_metrics.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "get_metrics_history" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.get_metrics_history.invoke_arn
  payload_format_version = "2.0"
}

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
resource "aws_apigatewayv2_route" "submit_job" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /jobs"
  target    = "integrations/${aws_apigatewayv2_integration.submit_job.id}"
}

resource "aws_apigatewayv2_route" "get_job_by_id" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /jobs/{jobId}"
  target    = "integrations/${aws_apigatewayv2_integration.get_job.id}"
}

resource "aws_apigatewayv2_route" "list_jobs" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /jobs"
  target    = "integrations/${aws_apigatewayv2_integration.get_job.id}"
}

resource "aws_apigatewayv2_route" "get_metrics" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /metrics"
  target    = "integrations/${aws_apigatewayv2_integration.get_metrics.id}"
}

resource "aws_apigatewayv2_route" "get_metrics_history" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /metrics/history"
  target    = "integrations/${aws_apigatewayv2_integration.get_metrics_history.id}"
}

# ---------------------------------------------------------------------------
# Lambda invoke permissions for API Gateway
# ---------------------------------------------------------------------------
resource "aws_lambda_permission" "apigw_submit_job" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.submit_job.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_get_job" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_job.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_get_metrics" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_metrics.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_get_metrics_history" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_metrics_history.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
