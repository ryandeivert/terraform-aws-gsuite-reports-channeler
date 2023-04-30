output "endpoint_function_name" {
  value       = aws_lambda_function.endpoint.function_name
  description = "Name of Lambda function used as an endpoint for receiving events"
}

output "endpoint_function_arn" {
  value       = aws_lambda_function.endpoint.arn
  description = "ARN of Lambda function used as an endpoint for receiving events"
}

output "endpoint_function_alias_name" {
  value       = aws_lambda_alias.endpoint.name
  description = "Lambda function alias name for function used as an endpoint for receiving events"
}

output "endpoint_function_alias_arn" {
  value       = aws_lambda_alias.endpoint.arn
  description = "Lambda function alias ARN for function used as an endpoint for receiving events"
}

output "endpoint_function_url" {
  value       = aws_lambda_function_url.endpoint.function_url
  description = "HTTPS Lambda function url for function used as an endpoint for receiving events"
}

output "channel_renewer_function_name" {
  value       = aws_lambda_function.channeler.function_name
  description = "Name of Lambda function used for renewing channels"
}

output "channel_renewer_function_arn" {
  value       = aws_lambda_function.channeler.arn
  description = "ARN of Lambda function used for renewing channels"
}

output "channel_renewer_function_alias_name" {
  value       = aws_lambda_alias.channeler.name
  description = "Lambda function alias name for function used for renewing channels"
}

output "channel_renewer_function_alias_arn" {
  value       = aws_lambda_alias.channeler.arn
  description = "Lambda function alias ARN for function used for renewing channels"
}

output "step_function_name" {
  value       = aws_sfn_state_machine.channeler.name
  description = "Name of Step Function used for renewing channels"
}

output "step_function_arn" {
  value       = aws_sfn_state_machine.channeler.arn
  description = "ARN of Step Function used for renewing channels"
}

output "sns_topic_arn" {
  value       = aws_sns_topic.logs.arn
  description = "SNS topic ARN to which logs are forwarded. This can be used to fan out to other services like Lambda, Firehose, etc"
}

output "metrics_namespace" {
  value       = local.metrics_namespace
  description = "Custom namespace in CloudWatch Metrics to which service metrics are published"
}
