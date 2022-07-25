
# Initialize a channel renewer for each desired app
resource "aws_lambda_invocation" "invoke" {
  for_each      = toset(var.app_names)
  function_name = module.channel_renewer_function.lambda_function_name
  qualifier     = module.channel_renewer_function_alias.lambda_alias_name

  input = jsonencode({
    app_name = each.value
  })

  depends_on = [time_sleep.wait]
}

# wait a few seconds for necessary policy to propagate
resource "time_sleep" "wait" {
  depends_on      = [aws_iam_role_policy.channel_renewer]
  create_duration = "10s"
}
