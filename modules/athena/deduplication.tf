
locals {
  function_name     = "${var.prefix}-gsuite-admin-reports-deduplication"
  metrics_namespace = "gsuite-logs-channeler"
}

module "deduplication_function" {
  count   = var.deduplication.enabled == true ? 1 : 0
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 4.9.0"

  function_name                     = local.function_name
  role_name                         = "${local.function_name}-role"
  handler                           = "main.handler"
  runtime                           = "python3.9"
  publish                           = true
  memory_size                       = var.deduplication.lambda.memory
  timeout                           = min(var.deduplication.lambda.timeout, 300) # max timeout of 5 min for firehose data transformation
  cloudwatch_logs_retention_in_days = var.deduplication.lambda.log_retention_days

  source_path = [
    {
      path             = "${path.module}/functions/deduplication"
      pip_requirements = true
    }
  ]
  environment_variables = {
    PREFIX                       = var.prefix
    LOG_LEVEL                    = var.deduplication.lambda.log_level
    POWERTOOLS_METRICS_NAMESPACE = local.metrics_namespace
  }
}

module "deduplication_function_alias" {
  count   = var.deduplication.enabled == true ? 1 : 0
  source  = "terraform-aws-modules/lambda/aws//modules/alias"
  version = "~> 4.9.0"

  name             = "production"
  description      = "production alias for ${module.deduplication_function[0].lambda_function_name}"
  function_name    = module.deduplication_function[0].lambda_function_name
  function_version = module.deduplication_function[0].lambda_function_version
  refresh_alias    = true
}
