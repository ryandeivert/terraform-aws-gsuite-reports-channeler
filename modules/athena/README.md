# Athena Table for GSuite Logs

This is meant to be used in conjunction with the an instance of the
[channeler module](https://github.com/ryandeivert/terraform-aws-gsuite-logs-channeler).

For the below examples, assume a configuration such as the one below exists:
```hcl
module "channeler" {
  source = "ryandeivert/gsuite-logs-channeler/aws"
  delegation_email = "svc-acct-email@domain.com"
  secret_name      = "google-reports-jwt"
  app_names        = ["drive", "admin", "calendar", "token"]
}
```

## Usage

### All logs from all enabled apps
```hcl
module "athena" {
  source = "ryandeivert/gsuite-logs-channeler/aws//modules/athena"

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
  source = "ryandeivert/gsuite-logs-channeler/aws//modules/athena"

  prefix         = "<custom-prefix>"
  table_name     = "admin-and-token-logs"
  s3_bucket_name = "<s3-bucket-name>"
  s3_sse_kms_arn = "<s3-kms-key-arn>"
  sns_topic_arn  = module.channeler.sns_topic_arn # channeler module instance
  filter_policy = jsonencode({
    app_name = ["admin", "token"]
  })
}
```

### Logs from all apps for user "important@domain.com"
```hcl
module "athena" {
  source = "ryandeivert/gsuite-logs-channeler/aws//modules/athena"

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
