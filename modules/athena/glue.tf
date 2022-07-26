
# columns for glue table
locals {
  # Combined details below links:
  # https://developers.google.com/admin-sdk/reports/v1/guides/push#understanding-the-notification-message-format
  # https://developers.google.com/admin-sdk/reports/reference/rest/v1/activities/list#activity
  columns = {
    "kind"        = "string"
    "ownerdomain" = "string"
    "ipaddress"   = "string"
    "etag"        = "string"
    "actor"       = "struct<callertype:string,email:string,profileid:string,key:string>"
    "id"          = "struct<applicationname:string,customerid:string,time:string,uniquequalifier:bigint>"
    "events"      = "array<struct<type:string,name:string,parameters:array<string>>>"
  }

  # The current existing set, plus any user supplied apps
  all_apps = setunion([
    "access_transparency",
    "admin",
    "calendar",
    "chat",
    "drive",
    "gcp",
    "gplus",
    "groups",
    "groups_enterprise",
    "jamboard",
    "login",
    "meet",
    "mobile",
    "rules",
    "saml",
    "token",
    "user_accounts",
    "context_aware_access",
    "chrome",
    "data_studio",
    "keep",
    # Occasionally the id.applicationName value in a log is empty, so partition as "unknown"
    # NOTE: This appears to be specific to the "chrome" application, which omits this field
    # when returning events through the "watch" API, but includes it when using the "list" API
    "unknown",
    ],
    var.extra_applications
  )
}

resource "time_static" "current" {}

resource "aws_glue_catalog_table" "logs" {
  name          = var.table_name
  database_name = var.database

  parameters = {
    "classification"     = "parquet"
    "projection.enabled" = "true"

    # application partition enum values
    # Reference: https://developers.google.com/admin-sdk/reports/reference/rest/v1/activities/watch#ApplicationName
    "projection.application.type"   = "enum"
    "projection.application.values" = join(",", local.all_apps)

    # date partition
    # Use current date as start of partitions because there cannot be data before now
    # Reference: https://docs.aws.amazon.com/athena/latest/ug/partition-projection-kinesis-firehose-example.html#partition-projection-kinesis-firehose-example-using-the-date-type
    "projection.dt.type"          = "date"
    "projection.dt.format"        = "yyyy/MM/dd/HH"
    "projection.dt.range"         = "${formatdate("YYYY/MM/DD/hh", time_static.current.rfc3339)},NOW"
    "projection.dt.interval"      = "1"
    "projection.dt.interval.unit" = "HOURS"

    "storage.location.template" = "s3://${var.s3_bucket_name}/${local.table_location}/$${application}/$${dt}/"
  }

  storage_descriptor {
    location      = "s3://${var.s3_bucket_name}/${local.table_location}"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters            = { "serialization.format" = 1 }
    }

    dynamic "columns" {
      for_each = local.columns
      content {
        name = columns.key
        type = columns.value
      }
    }
  }

  partition_keys {
    name = "application"
    type = "string"
  }

  partition_keys {
    name = "dt"
    type = "string"
  }
}
