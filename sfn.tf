resource "aws_cloudwatch_log_group" "channeler" {
  name              = "/aws/states/${local.channel_function_name}"
  retention_in_days = var.sfn_cloudwatch_logs_retention_in_days
}

# State Machine for gsuite channeler
resource "aws_sfn_state_machine" "channeler" {
  name     = local.channel_function_name
  role_arn = aws_iam_role.sfn.arn

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.channeler.arn}:*"
    include_execution_data = false
    level                  = "ALL"
  }

  definition = <<EOF
{
  "Comment": "GSuite channel renewer step function",
  "StartAt": "Wait for Expiration",
  "States": {
    "Wait for Expiration": {
      "Type": "Wait",
      "Next": "Invoke Renewer Function",
      "TimestampPath": "$.expiration"
    },
    "Invoke Renewer Function": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "OutputPath": "$.Payload",
      "Parameters": {
        "Payload.$": "$",
        "FunctionName": "${module.channel_renewer_function_alias.lambda_alias_arn}"
      },
      "Retry": [
        {
          "ErrorEquals": [
            "Lambda.ServiceException",
            "Lambda.AWSLambdaException",
            "Lambda.SdkClientException",
            "Lambda.Unknown",
            "Lambda.TooManyRequestsException"
          ],
          "IntervalSeconds": 2,
          "MaxAttempts": 6,
          "BackoffRate": 2
        }
      ],
      "Next": "Start SFN"
    },
    "Start SFN": {
      "Type": "Task",
      "Resource": "arn:aws:states:::states:startExecution",
      "Parameters": {
        "StateMachineArn": "${local.state_machine_arn}",
        "Input.$": "$",
        "Name.$": "States.Format('{}_{}', $.application, $.channel_id)"
      },
      "End": true
    }
  }
}
EOF
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
    resources = [module.channel_renewer_function_alias.lambda_alias_arn]
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
