# Athena Table for GSuite Logs

This is meant to be used in conjunction with an instance of the
[channeler module](https://github.com/ryandeivert/terraform-aws-gsuite-reports-channeler).

For the below examples, assume a configuration such as the one below exists:
```hcl
module "channeler" {
  source = "ryandeivert/gsuite-reports-channeler/aws"

  delegation_email = "svc-acct-email@domain.com"
  secret_name      = "google-reports-jwt"
  applications     = ["drive", "admin", "calendar", "token"]
}
```

## Usage

### All logs from all enabled apps
```hcl
module "athena" {
  source = "ryandeivert/gsuite-reports-channeler/aws//modules/athena"

  prefix         = "<custom-prefix>"
  table_name     = "all-logs"
  s3_bucket_name = "<s3-bucket-name>"
  s3_sse_kms_arn = "<s3-kms-key-arn>"
  sns_topic_arn  = module.channeler.sns_topic_arn # channeler module instance
}
```

### Only logs from admin and token apps
```hcl
module "athena" {
  source = "ryandeivert/gsuite-reports-channeler/aws//modules/athena"

  prefix         = "<custom-prefix>"
  table_name     = "admin-and-token-logs"
  s3_bucket_name = "<s3-bucket-name>"
  s3_sse_kms_arn = "<s3-kms-key-arn>"
  sns_topic_arn  = module.channeler.sns_topic_arn # channeler module instance
  filter_policy = jsonencode({
    application = ["admin", "token"]
  })
}
```

### Logs from all apps for user "important@domain.com"
```hcl
module "athena" {
  source = "ryandeivert/gsuite-reports-channeler/aws//modules/athena"

  prefix         = "<custom-prefix>"
  table_name     = "important-user-logs"
  s3_bucket_name = "<s3-bucket-name>"
  s3_sse_kms_arn = "<s3-kms-key-arn>"
  sns_topic_arn  = module.channeler.sns_topic_arn # channeler module instance
  filter_policy = jsonencode({
    actor_email = ["important@domain.com"]
  })
}
```

### Perform Best-Effort Deduplication

Setting the `deduplicate` variable to `true` will enabling best-effort deduplication of logs.

This feature applies [Kinesis Data Transformation](https://docs.aws.amazon.com/firehose/latest/dev/data-transformation.html)
to the Firehose resource. It uses a Lambda function to inspect incoming logs, and mark any
that appear to be duplicates as `Dropped`.

```hcl
module "athena" {
  source = "ryandeivert/gsuite-reports-channeler/aws//modules/athena"

  prefix         = "<custom-prefix>"
  table_name     = "important-user-logs"
  s3_bucket_name = "<s3-bucket-name>"
  s3_sse_kms_arn = "<s3-kms-key-arn>"
  sns_topic_arn  = module.channeler.sns_topic_arn # channeler module instance
  deduplicate    = true 
}
```

#### How It Works

Incoming logs contain values for `id.time` and `id.uniqueQualifier` which, according to [Google documentation](https://developers.google.com/admin-sdk/reports/v1/guides/push),
should be useful in uniquely identifying logs.

The Lambda function will construct a composite key from the `id.time` and `id.uniqueQualifier` values in each log,
and use this composite key in a best-effort deduplication strategy.

In testing, with deduplication disabled, **roughly 4%** of resulting logs were duplicates. A second instance of
this module was then added alongside the existing module, with deduplication enabled. The total unique events in
each pipeline remained the same, while duplicate records in the "deduplicated" results dropped to **roughly 0.5%**
(an 80% reduction in total duplicates).

#### Notes
- The deduplication feature should be used at your own risk, and no guarantees are offered as to the validity of dropped events.
- The Kinesis Data Transformation feature may incur additional cost.
