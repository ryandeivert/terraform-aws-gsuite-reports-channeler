
locals {
  function_name = "${var.prefix}-gsuite-admin-reports-deduplication"
}

module "deduplication_function" {
  count  = var.deduplicate == true ? 1 : 0
  source = "terraform-aws-modules/lambda/aws"

  function_name = local.function_name
  role_name     = "${local.function_name}-role"
  handler       = "main.handler"
  runtime       = "python3.9"
  publish       = true
  memory_size   = 128
  timeout       = 30
  source_path   = "${path.module}/functions/deduplication"

  environment_variables = {
    LOG_LEVEL = var.log_level
  }
}

module "deduplication_function_alias" {
  count  = var.deduplicate == true ? 1 : 0
  source = "terraform-aws-modules/lambda/aws//modules/alias"

  name             = "production"
  description      = "production alias for ${module.deduplication_function[0].lambda_function_name}"
  function_name    = module.deduplication_function[0].lambda_function_name
  function_version = module.deduplication_function[0].lambda_function_version
  refresh_alias    = false
}
