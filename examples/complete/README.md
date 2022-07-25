# Complete Example, with Athena Table

This example creates the required channeler module, as well as an instance
of the `athena` submodule for searching the resulting logs.

A few dependent resources are also created that these modules directly, or indirectly, use:
* KMS key + alias used for encrypting the Secrets Manager secret
  * This is used to encrypt the contents of the Google JWT credentials file
  * The KMS key's policy allows Secrets Manager to decrypt the key
* S3 bucket, and KMS key for object encryption, used by Firehose for data storage and by Athena for searching logs

## Channeler Module
```hcl
module "channeler" {
  source = "ryandeivert/gsuite-reports-channeler/aws"

  prefix           = local.prefix
  delegation_email = "svc-acct-email@domain.com"

  # NOTE: this secret was manually added to secrets manager
  secret_name = "google-reports-jwt"

  # NOTE: the above secret MUST be added to Secrets Manager before the below list
  # can have any entries. Otherwise applies will fail until the secret is available.
  applications = ["admin"]
}
```

## Athena Submodule
```hcl
module "athena" {
  source = "ryandeivert/gsuite-reports-channeler/aws//modules/athena"

  prefix         = local.prefix
  table_name     = "all-logs"
  s3_bucket_name = module.s3_bucket.s3_bucket_id # bucket created for storing logs
  s3_sse_kms_arn = aws_kms_key.s3.arn            # kms key for encrypting objects in above bucket
  sns_topic_arn  = module.channeler.sns_topic_arn
}
```
