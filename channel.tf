
locals {
  channel_function_name = "${var.prefix}-gsuite-admin-reports-channel-renewer"
  state_machine_arn     = "arn:aws:states:${local.region}:${local.account_id}:stateMachine:${local.channel_function_name}"
}

moved {
  from = module.channel_renewer_function.aws_cloudwatch_log_group.lambda[0]
  to   = aws_cloudwatch_log_group.channeler_lambda
}
moved {
  from = module.channel_renewer_function.aws_iam_role.lambda[0]
  to   = aws_iam_role.channeler
}

moved {
  from = module.channel_renewer_function.aws_lambda_function.this[0]
  to   = aws_lambda_function.channeler
}

moved {
  from = module.channel_renewer_function_alias.aws_lambda_alias.with_refresh[0]
  to   = aws_lambda_alias.channeler
}

resource "aws_cloudwatch_log_group" "channeler_lambda" {
  name              = "/aws/lambda/${local.channel_function_name}"
  retention_in_days = var.lambda_settings.channel_renewer.log_retention_days
}

resource "aws_iam_role" "channeler" {
  name               = "${local.channel_function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_lambda_function" "channeler" {
  function_name    = local.channel_function_name
  handler          = "main.handler"
  memory_size      = var.lambda_settings.channel_renewer.memory
  publish          = true
  role             = aws_iam_role.channeler.arn
  runtime          = "python3.9"
  timeout          = var.lambda_settings.channel_renewer.timeout
  filename         = data.archive_file.channeler.output_path
  source_code_hash = data.archive_file.channeler.output_base64sha256

  # Public Lambda layer corresponding to semantic version v2.84.0 of oogle-api-python-client
  layers = ["arn:aws:lambda:${local.region}:770693421928:layer:Klayers-p39-google-api-python-client:1"]

  environment {
    variables = {
      LOG_LEVEL             = var.lambda_settings.channel_renewer.log_level
      CHANNEL_TOKEN         = random_password.token.result
      LAMBDA_URL            = aws_lambda_function_url.endpoint.function_url
      DELEGATION_EMAIL      = var.delegation_email
      SECRET_NAME           = var.secret_name
      REFRESH_THRESHOLD_MIN = var.refresh_treshold_min
      STATE_MACHINE_ARN     = local.state_machine_arn
    }
  }
}

resource "aws_lambda_alias" "channeler" {
  description      = "production alias for ${aws_lambda_function.channeler.function_name}"
  function_name    = aws_lambda_function.channeler.function_name
  function_version = aws_lambda_function.channeler.version
  name             = "production"
}

data "archive_file" "channeler" {
  type        = "zip"
  source_dir  = "${path.module}/functions/channel_renewer"
  output_path = "${path.module}/builds/channel_renewer.zip"
}

data "aws_iam_policy_document" "channeler" {
  statement {
    effect = "Allow"
    actions = [
      "states:ListExecutions",
      "states:StartExecution",
    ]
    resources = [aws_sfn_state_machine.channeler.arn]
  }
  statement {
    effect = "Allow"
    actions = [
      "states:DescribeExecution",
      "states:StopExecution",
    ]
    resources = ["arn:aws:states:${local.region}:${local.account_id}:execution:${local.channel_function_name}:*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${var.secret_name}*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "${aws_cloudwatch_log_group.channeler_lambda.arn}:*",
      "${aws_cloudwatch_log_group.channeler_lambda.arn}:*:*",
    ]
  }
}

resource "aws_iam_role_policy" "channeler" {
  name   = "DefaultPolicy"
  role   = aws_iam_role.channeler.name
  policy = data.aws_iam_policy_document.channeler.json
}
