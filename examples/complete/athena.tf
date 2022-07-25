/*

This creates an S3 bucket for storing logs, along with a KMS key to encrypt S3 objects

It then passes the bucket, KMS key, and SNS topic to the athena module which is
responsbile for creating the necessary resources to make the gsuite logs searchable:
  * Firehose
  * Firehose <> SNS subscription
  * Glue Table
  * Dependent roles

NOTE: This is an example and should be modified to suit specific requirements

*/

module "athena" {
  source = "ryandeivert/gsuite-logs-channeler/aws//modules/athena"

  prefix         = local.prefix
  table_name     = "all-logs"
  s3_bucket_name = module.s3_bucket.s3_bucket_id
  s3_sse_kms_arn = aws_kms_key.s3.arn
  sns_topic_arn  = module.channeler.sns_topic_arn
}

resource "aws_kms_key" "s3" {
  description             = "KMS key is used to encrypt bucket objects"
  deletion_window_in_days = 7
}

module "s3_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket                                = "${local.prefix}-gsuite-admin-reports-logs"
  acl                                   = "private"
  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  # S3 bucket-level Public Access Block configuration
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # S3 Bucket Ownership Controls
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls
  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"

  expected_bucket_owner = local.account_id

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = aws_kms_key.s3.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  versioning = {
    enabled = true
  }
}
