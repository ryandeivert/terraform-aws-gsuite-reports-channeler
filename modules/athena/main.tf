data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  region        = data.aws_region.current.name
  s3_bucket_arn = "arn:aws:s3:::${var.s3_bucket_name}"
  resource_name = "${var.prefix}-gsuite-admin-reports-${var.table_name}"
}
