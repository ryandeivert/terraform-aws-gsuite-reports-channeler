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

variable "table_name" {
  type        = string
  description = "Resulting table name to be created in specified database variable"
}

variable "database" {
  type        = string
  description = "Name of Athena database where table in table_name variable should be created"
  default     = "default"
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
