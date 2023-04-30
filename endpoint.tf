
locals {
  endpoint_function_name = "${var.prefix}-gsuite-admin-reports-endpoint"
}

moved {
  from = module.endpoint_function.aws_cloudwatch_log_group.lambda[0]
  to   = aws_cloudwatch_log_group.endpoint_lambda
}
moved {
  from = module.endpoint_function.aws_iam_role.lambda[0]
  to   = aws_iam_role.endpoint
}

moved {
  from = module.endpoint_function.aws_lambda_function.this[0]
  to   = aws_lambda_function.endpoint
}

moved {
  from = module.endpoint_function_alias.aws_lambda_alias.with_refresh[0]
  to   = aws_lambda_alias.endpoint
}

resource "aws_cloudwatch_log_group" "endpoint_lambda" {
  name              = "/aws/lambda/${local.endpoint_function_name}"
  retention_in_days = var.lambda_settings.endpoint.log_retention_days
}

resource "aws_iam_role" "endpoint" {
  name               = "${local.endpoint_function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_lambda_function" "endpoint" {
  function_name    = local.endpoint_function_name
  handler          = "main.handler"
  memory_size      = var.lambda_settings.endpoint.memory
  publish          = true
  role             = aws_iam_role.endpoint.arn
  runtime          = "python3.9"
  timeout          = var.lambda_settings.endpoint.timeout
  filename         = data.archive_file.endpoint.output_path
  source_code_hash = data.archive_file.endpoint.output_base64sha256

  # Public Lambda layer corresponding to semantic version v2.14.1 of aws-lambda-powertools
  # Reference: https://awslabs.github.io/aws-lambda-powertools-python/2.14.1/#lambda-layer
  layers = ["arn:aws:lambda:${local.region}:017000801446:layer:AWSLambdaPowertoolsPythonV2:31"]

  environment {
    variables = {
      PREFIX                       = var.prefix
      LOG_LEVEL                    = var.lambda_settings.endpoint.log_level
      CHANNEL_TOKEN                = random_password.token.result
      SNS_TOPIC_ARN                = aws_sns_topic.logs.arn
      POWERTOOLS_METRICS_NAMESPACE = local.metrics_namespace
    }
  }
}

resource "aws_lambda_alias" "endpoint" {
  description      = "production alias for ${aws_lambda_function.endpoint.function_name}"
  function_name    = aws_lambda_function.endpoint.function_name
  function_version = aws_lambda_function.endpoint.version
  name             = "production"
}

data "archive_file" "endpoint" {
  type        = "zip"
  source_dir  = "${path.module}/functions/endpoint"
  output_path = "${path.module}/builds/endpoint.zip"
}

resource "aws_lambda_permission" "public_invoke" {
  statement_id           = "FunctionURLAllowPublicAccess"
  principal              = "*"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.endpoint.function_name
  qualifier              = aws_lambda_alias.endpoint.name
  function_url_auth_type = "NONE"
}

# The lambda module does not support an alias (only version) for
# public URLs, so this resource exists outside of the module
resource "aws_lambda_function_url" "endpoint" {
  function_name      = aws_lambda_function.endpoint.function_name
  qualifier          = aws_lambda_alias.endpoint.name
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
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "endpoint" {
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.logs.arn]
  }
  statement {
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
    ]
    resources = [aws_kms_key.logs.arn]
  }
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "${aws_cloudwatch_log_group.endpoint_lambda.arn}:*",
      "${aws_cloudwatch_log_group.endpoint_lambda.arn}:*:*",
    ]
  }
}

resource "aws_iam_role_policy" "endpoint" {
  name   = "DefaultPolicy"
  role   = aws_iam_role.endpoint.name
  policy = data.aws_iam_policy_document.endpoint.json
}
