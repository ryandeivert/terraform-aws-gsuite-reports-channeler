# Google Workspace (formerly G Suite) Admin Reports Collector

Lightweight serverless pipeline, leveraging AWS Lambda and Step Functions,
to collect Google Workspace Admin Reports via [Push Notifications](https://developers.google.com/admin-sdk/reports/v1/guides/push).

## Setup - Google

1. Ensure [these prerequisites](https://developers.google.com/admin-sdk/reports/v1/guides/prerequisites) are met
2. Create Google service account credentials that use domain-wide delegation by following [these instructions](https://developers.google.com/admin-sdk/reports/v1/guides/delegation).
2. Download the service account credentials as a JSON file that can be more easily
used with the Google API client library (**note: do not download in P12 format**).

## Setup - AWS

1. Create a new secret in [AWS Secrets Manager](https://us-east-1.console.aws.amazon.com/secretsmanager/newsecret?region=us-east-1).
  * Choose "Other type of secret"
  * Under "Key/value pairs", choose "Plaintext"
  * Copy JSON file content downloaded in # 2 above and paste the value into the form
  * (optional) Choose existing encryption key for the secret or create a new one
  * Follow prompts and save secret with desired name and **make note of the name used**

## Usage

```hcl
module "channeler" {
  source = "ryandeivert/gsuite-logs-channeler/aws"
  delegation_email = "svc-acct-email@domain.com"
  secret_name      = "google-reports-jwt" # name of secret from setup above
  app_names        = ["drive", "admin", "calendar", "token"]
}
```

## Optional Athena Submodule

The `modules/athena` directory contains the necessary components to make the logs
from this module searchable.

## Examples

See the `examples` directory for a end-to-end implementation of this module and the
optional athena submodule.
