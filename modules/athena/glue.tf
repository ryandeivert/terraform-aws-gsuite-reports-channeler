
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
}

resource "aws_glue_catalog_table" "logs" {
  name          = var.table_name
  database_name = var.database

  parameters = {
    "classification"     = "parquet"
    "projection.enabled" = "true"

    # injected partitions
    "projection.application.type" = "injected" # must be supplied at query time

    # date partition
    "projection.day.type"          = "date"
    "projection.day.format"        = "yyyy-MM-dd"
    "projection.day.range"         = "NOW-3YEARS,NOW"
    "projection.day.interval"      = "1"
    "projection.day.interval.unit" = "DAYS"

    # hour partition
    "projection.hour.type"   = "integer"
    "projection.hour.range"  = "0,23"
    "projection.hour.digits" = "2"

    "storage.location.template" = "s3://${var.s3_bucket_name}/${var.table_name}/$${application}/$${day}/$${hour}/"
  }

  storage_descriptor {
    location      = "s3://${var.s3_bucket_name}/${var.table_name}"
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
    name = "day"
    type = "date"
  }

  partition_keys {
    name = "hour"
    type = "int"
  }
}
