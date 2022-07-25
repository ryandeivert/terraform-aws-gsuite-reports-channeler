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

variable "log_level" {
  type        = string
  description = "Log level for the deployed Lambda functions. This should be a string version of the Python logging levels (eg: INFO, DEBUG, CRITICAL)"
  default     = "INFO"
}

variable "app_names" {
  type        = list(string)
  description = "List of app names for which logging channels should be created. See: https://developers.google.com/admin-sdk/reports/reference/rest/v1/activities/watch#ApplicationName"
  default     = []
}
