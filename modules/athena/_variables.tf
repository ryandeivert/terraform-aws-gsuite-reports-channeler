variable "prefix" {
  type        = string
  description = "Custom prefix to prepend to resources created in this module"
}

variable "enable" {
  type        = bool
  description = "Boolean to indicate if logs should be sent to the Firehose delivery stream. Disabling this will retain the Firehose, Athena table, and other dependent resources"
  default     = true
}

variable "sns_topic_arn" {
  type        = string
  description = "SNS Topic ARN to which the AWS Firehose will be subscribed"
}

variable "s3_bucket_name" {
  type        = string
  description = "Existing S3 bucket name where data should be stored"
}

variable "s3_sse_kms_arn" {
  type        = string
  description = "KMS ARN use for encrypting objects in S3 bucket provided in s3_bucket_name variable"
}

variable "s3_prefix" {
  type        = string
  description = "Prefix at which data (table) should reside inside the specified S3 bucket"
  default     = ""
}

variable "use_hive_partitions" {
  type        = bool
  description = "Whether or not the data in S3 should be stored using a path that is compatible with Hive"
  default     = true
}

variable "database" {
  type        = string
  description = "Name of Athena database where table in table_name variable should be created"
  default     = "default"
}

variable "table_name" {
  type        = string
  description = "Resulting table name to be created in specified database variable"
}

variable "extra_applications" {
  type        = list(string)
  description = "Additional applications for which Athena partitions should be projected. This allows for extra applications to be injected without updating the static default list"
  default     = []
}

/*
Example filters:

* Resulting table will include events from both drive + calendar apps for the user "important@domain.com"
  {
     "application": ["drive", "calendar"],
     "actor_email": ["important@domain.com"]
  }

* Resulting table will include events from both admin + token apps for all users EXCEPT "noisy@domain.com"
  {
     "application": ["admin", "token"],
     "actor_email": [{"anything-but": "noisy@domain.com"}]
  }

*/
variable "filter_policy" {
  type        = string
  description = "SNS filter policy to apply to Firehose <> SNS subscription. This allows filtering only certain users or apps to the created table"
  default     = null
}

variable "firehose_cloudwatch_logs_retention_in_days" {
  type        = number
  description = "The number of days to retain log events in the Firehose CloudWatch Log group"
  default     = 30
}

variable "deduplication" {
  type = object({
    enabled = optional(bool, false)
    lambda = optional(object({
      timeout            = optional(number, 300)
      memory             = optional(number, 128)
      log_level          = optional(string, "INFO")
      log_retention_days = optional(number, 30)
    }), {})
  })
  description = <<EOT
deduplication = {
  enabled = "Boolean to indicate if logs should be deduplicated using a best-effort strategy with Kinesis Data Transformation and an intermediary Lambda function"
  lambda = {
    timeout            = "Timeout for Lambda function"
    memory             = "Memory, in MB, for Lambda function"
    log_level          = "String version of the Python logging levels (eg: INFO, DEBUG, CRITICAL) "
    log_retention_days = "Number of days for which this Lambda function's CloudWatch Logs should be retained"

  }
}
EOT
  default     = {}
}

