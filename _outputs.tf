output "endpoint_function_url" {
  value       = aws_lambda_function_url.endpoint.function_url
  description = "HTTPS url for the endpoint Lambda function"
}

output "sns_topic_arn" {
  value       = aws_sns_topic.logs.arn
  description = "SNS topic ARN to which logs are forwarded. This can be used to fan out to other services like Lambda, Firehose, etc"
}
