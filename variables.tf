variable "prefix" {
  type        = string
  description = "Custom prefix to prepend to resources created in this module"
}

variable "delegation_email" {
  type        = string
  description = "Google Service Account delegation email used for domain-wide delegation. See: https://developers.google.com/admin-sdk/reports/v1/guides/delegation"
}

variable "refresh_treshold_min" {
  type        = number
  description = "Number of minutes before the channel expiration to wait until the channel is refreshed"
  default     = 15
}

variable "secret_name" {
  type        = string
  description = "Name of secret stored in Secrets Manager. This should be the contents of the Google Service Account json credentials file"
}

variable "sfn_cloudwatch_logs_retention_in_days" {
  type        = number
  description = "The number of days to retain log events in the Step Function CloudWatch Log group"
  default     = 30
}

variable "applications" {
  type        = list(string)
  description = "List of applications names for which logging channels should be created. See: https://developers.google.com/admin-sdk/reports/reference/rest/v1/activities/watch#ApplicationName"
  default     = []
}

variable "stop_applications" {
  type        = list(string)
  description = "List of applications names for which logging channels should be stopped. Note that entries to this list must have been applied as an entry in the application variable's list before they may be added here"
  default     = []
}

variable "auto_recover" {
  type        = bool
  description = "Whether Step Function failures should trigger an automatic attempt to recover"
  default     = true
}

variable "lambda_settings" {
  type = object({
    endpoint = optional(object({
      timeout            = optional(number, 30)
      memory             = optional(number, 128)
      log_level          = optional(string, "INFO")
      log_retention_days = optional(number, 30)
    }), {})
    channel_renewer = optional(object({
      timeout            = optional(number, 30)
      memory             = optional(number, 128)
      log_level          = optional(string, "INFO")
      log_retention_days = optional(number, 30)
    }), {})
  })
  description = <<EOT
lambda_settings = {
  endpoint = {
    timeout            = "Timeout for Lambda function"
    memory             = "Memory, in MB, for Lambda function"
    log_level          = "String version of the Python logging levels (eg: INFO, DEBUG, CRITICAL) "
    log_retention_days = "Number of days for which this Lambda function's CloudWatch Logs should be retained"

  }
  channel_renewer = {} # Same settings apply to this object as endpoint object above
}
EOT
  default     = {}
}

