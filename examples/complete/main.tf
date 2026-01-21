/*

Example module configuration for the gsuite log channeler

*/

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  prefix     = "rd01" # customize this
}

module "channeler" {
  source = "ryandeivert/gsuite-reports-channeler/aws"

  prefix           = local.prefix
  delegation_email = "svc-acct-email@domain.com"

  secret_name = aws_secretsmanager_secret.this.name

  # NOTE: the above secret MUST be added to Secrets Manager before the below list
  # can have any entries. Otherwise applies will fail until the secret is available.
  applications = ["admin"]

  depends_on = [aws_secretsmanager_secret.this]
}
