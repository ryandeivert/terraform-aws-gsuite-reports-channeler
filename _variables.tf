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
