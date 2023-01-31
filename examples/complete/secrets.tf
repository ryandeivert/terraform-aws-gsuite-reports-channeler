/*

OPTIONAL: KMS Key + Alias to be used for decrypting Secrets Manager secret

The default AWS managed KMS key (aws/secretsmanager) may be used if desired

*/

resource "aws_kms_key" "secrets" {
  description = "Key for gsuite key file encryption in secrets manager"
  policy      = data.aws_iam_policy_document.secrets.json
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/gsuite-service-api-key"
  target_key_id = aws_kms_key.secrets.arn
}

data "aws_iam_policy_document" "secrets" {
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

  statement {
    sid    = "Allow access through AWS Secrets Manager"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${local.region}.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [local.account_id]
    }

    actions = [
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:CreateGrant",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }
}

resource "aws_secretsmanager_secret" "this" {
  name       = "${local.prefix}-google-reports-api-jwt"
  kms_key_id = aws_kms_key.secrets.arn
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = try(file(var.gsuite_reports_jwt_file), "")

  # Remove below lifecycle block if rotating the JWT value, then run:
  # terraform apply -var="gsuite_reports_jwt_file=/path/to/jwt_file.json"
  lifecycle {
    ignore_changes = [
      secret_string
    ]
  }
}
