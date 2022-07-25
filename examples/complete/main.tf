/*

Module configuration for the gsuite log channeler

Note that the secret referenced was manually added to secrets manager

*/

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  prefix     = "rd01" # customize this
}

module "channeler" {
  source           = "ryandeivert/gsuite-logs-channeler/aws"
  prefix           = local.prefix
  delegation_email = "svc-acct-email@domain.com"

  # NOTE: this secret was manually added to secrets manager
  secret_name = "google-reports-jwt"

  # NOTE: the above secret MUST be added to Secrets Manager before the below list
  # can have any entries. Otherwise applies will fail until the secret is available.
  app_names = ["admin"]
}
