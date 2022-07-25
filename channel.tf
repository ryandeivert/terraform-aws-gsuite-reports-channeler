
locals {
  channel_function_name = "${var.prefix}-gsuite-admin-reports-channel-renewer"
  state_machine_arn     = "arn:aws:states:${local.region}:${local.account_id}:stateMachine:${local.channel_function_name}"
}

module "channel_renewer_function" {
  source = "terraform-aws-modules/lambda/aws"

  function_name = local.channel_function_name
  role_name     = "${local.channel_function_name}-role"
  handler       = "main.handler"
  runtime       = "python3.9"
  publish       = true
  memory_size   = 128
  timeout       = 30
  source_path = [
    {
      path             = "${path.module}/functions/channel_renewer"
      pip_requirements = true
    }
  ]

  environment_variables = {
    LOG_LEVEL             = var.log_level
    CHANNEL_TOKEN         = random_password.token.result
    LAMBDA_URL            = aws_lambda_function_url.endpoint.function_url
    DELEGATION_EMAIL      = var.delegation_email
    SECRET_NAME           = var.secret_name
    REFRESH_THRESHOLD_MIN = var.refresh_treshold_min
    STATE_MACHINE_ARN     = local.state_machine_arn
  }
}

module "channel_renewer_function_alias" {
  source = "terraform-aws-modules/lambda/aws//modules/alias"

  name             = "production"
  description      = "production alias for ${module.channel_renewer_function.lambda_function_name}"
  function_name    = module.channel_renewer_function.lambda_function_name
  function_version = module.channel_renewer_function.lambda_function_version
  refresh_alias    = false
}

data "aws_iam_policy_document" "channel_renewer" {
  statement {
    effect    = "Allow"
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.channeler.arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${var.secret_name}*"]
  }
}

# The lambda module does not support in-line policies,
# so this resource exists outside of the module
resource "aws_iam_role_policy" "channel_renewer" {
  name   = "SFNAndSecrets"
  role   = module.channel_renewer_function.lambda_role_name
  policy = data.aws_iam_policy_document.channel_renewer.json
}
