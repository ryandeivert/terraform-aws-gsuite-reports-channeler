
# Initialize a channel renewer for each desired app
resource "aws_lambda_invocation" "init" {
  for_each      = toset(var.applications)
  function_name = aws_lambda_function.channeler.function_name
  qualifier     = aws_lambda_alias.channeler.name

  input = jsonencode({
    application   = each.value
    lambda_action = "init"
  })

  depends_on = [time_sleep.wait]
}

# Stop a channel renewer for each desired app
resource "aws_lambda_invocation" "stop" {
  for_each      = toset(var.stop_applications)
  function_name = aws_lambda_function.channeler.function_name
  qualifier     = aws_lambda_alias.channeler.name

  input = jsonencode({
    application   = each.value
    lambda_action = "stop"
  })
}

# wait a few seconds for necessary policy to propagate
resource "time_sleep" "wait" {
  depends_on      = [aws_iam_role_policy.channeler]
  create_duration = "10s"
}
