output "endpoint_function_url" {
  value = aws_lambda_function_url.endpoint.function_url
}

output "sns_topic_arn" {
  value = aws_sns_topic.logs.arn
}
