resource "aws_cloudwatch_event_rule" "failures" {
  count       = var.auto_recover == true ? 1 : 0
  name        = "${local.channel_function_name}-sfn-failures"
  description = "Capture any failures in the gsuite-channeler step function and restart it using the Lambda"

  event_pattern = jsonencode({
    source      = ["aws.states"]
    detail-type = ["Step Functions Execution Status Change"]
    detail = {
      status          = ["FAILED"]
      stateMachineArn = [aws_sfn_state_machine.channeler.arn]
    }
  })
}

resource "aws_cloudwatch_event_target" "lambda" {
  count     = var.auto_recover == true ? 1 : 0
  target_id = "${local.channel_function_name}-recover"
  rule      = aws_cloudwatch_event_rule.failures[0].name
  arn       = aws_lambda_alias.channeler.arn

  input_transformer {
    input_paths = {
      input = "$.detail.input",
    }
    input_template = <<EOF
{
  "input": <input>,
  "lambda_action": "recover"
}
EOF
  }
}

resource "aws_lambda_permission" "cloudwatch" {
  count         = var.auto_recover == true ? 1 : 0
  statement_id  = "CloudWatchExecution"
  principal     = "events.amazonaws.com"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.channeler.function_name
  qualifier     = aws_lambda_alias.channeler.name
  source_arn    = aws_cloudwatch_event_rule.failures[0].arn
}
