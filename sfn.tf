resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/states/${local.channel_function_name}"
  retention_in_days = var.sfn_cloudwatch_logs_retention_in_days
}

# State Machine for gsuite channeler
resource "aws_sfn_state_machine" "channeler" {
  name     = local.channel_function_name
  role_arn = aws_iam_role.sfn.arn

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = false
    level                  = "ALL"
  }

  definition = templatefile(
    "${path.module}/sfn_template.tftpl",
    {
      function_arn      = aws_lambda_alias.channeler.arn
      state_machine_arn = local.state_machine_arn
    }
  )
}

data "aws_iam_policy_document" "sfn_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

// Execution role for the SFN state machine
resource "aws_iam_role" "sfn" {
  name               = "${local.channel_function_name}-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume_role.json
}

resource "aws_iam_role_policy" "lambda_sfn" {
  name   = "LambdaAndSFN"
  role   = aws_iam_role.sfn.name
  policy = data.aws_iam_policy_document.lambda_sfn.json
}

data "aws_iam_policy_document" "lambda_sfn" {
  statement {
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_alias.channeler.arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.channeler.arn]
  }
}

resource "aws_iam_role_policy" "sfn_cloudwatch" {
  name   = "CloudWatch"
  role   = aws_iam_role.sfn.name
  policy = data.aws_iam_policy_document.sfn_cloudwatch.json
}

data "aws_iam_policy_document" "sfn_cloudwatch" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]

    resources = ["*"]
  }
}
