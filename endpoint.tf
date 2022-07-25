
module "endpoint_function" {
  source = "terraform-aws-modules/lambda/aws"

  function_name = "${var.prefix}-gsuite-admin-reports-endpoint"
  role_name     = "${var.prefix}-gsuite-admin-reports-endpoint-role"
  handler       = "main.handler"
  runtime       = "python3.9"
  publish       = true
  memory_size   = 128
  timeout       = 30
  source_path = [
    {
      path             = "${path.module}/functions/endpoint"
      pip_requirements = true
    }
  ]

  environment_variables = {
    LOG_LEVEL     = var.log_level
    CHANNEL_TOKEN = random_password.token.result
    SNS_TOPIC_ARN = aws_sns_topic.logs.arn
  }
}

module "endpoint_function_alias" {
  source = "terraform-aws-modules/lambda/aws//modules/alias"

  name             = "production"
  description      = "production alias for ${module.endpoint_function.lambda_function_name}"
  function_name    = module.endpoint_function.lambda_function_name
  function_version = module.endpoint_function.lambda_function_version
  refresh_alias    = false
}

resource "aws_lambda_permission" "public_invoke" {
  statement_id           = "FunctionURLAllowPublicAccess"
  principal              = "*"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = module.endpoint_function.lambda_function_name
  qualifier              = module.endpoint_function_alias.lambda_alias_name
  function_url_auth_type = "NONE"
}

# The lambda module does not support an alias (only version) for
# public URLs, so this resource exists outside of the module
resource "aws_lambda_function_url" "endpoint" {
  function_name      = module.endpoint_function.lambda_function_name
  qualifier          = module.endpoint_function_alias.lambda_alias_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"]
    allow_methods = ["POST"]
  }
}

data "aws_iam_policy_document" "kms" {
  statement {
    sid    = "Enable Key Management"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }
}

# The lambda module does not support in-line policies,
# so this resource exists outside of the module
resource "aws_iam_role_policy" "sns_kms" {
  name   = "SNSAndKMS"
  role   = module.endpoint_function.lambda_role_name
  policy = data.aws_iam_policy_document.sns_kms.json
}
