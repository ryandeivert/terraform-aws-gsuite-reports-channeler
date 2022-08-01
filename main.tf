
// Current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id        = data.aws_caller_identity.current.account_id
  region            = data.aws_region.current.name
  metrics_namespace = "gsuite-logs-channeler"
}

# Token used when creating channels
# This is used to validate input from the channel when it
# arrives in the endpoint lambda and is not truly a "secret"
resource "random_password" "token" {
  length  = 16
  special = false
}

resource "aws_sns_topic" "logs" {
  name              = "${var.prefix}-gsuite-admin-reports-logs"
  kms_master_key_id = aws_kms_key.logs.arn
}

resource "aws_kms_key" "logs" {
  description = "Key for sns topic encryption"
  policy      = data.aws_iam_policy_document.kms.json
}

data "aws_iam_policy_document" "sns_kms" {
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
}
