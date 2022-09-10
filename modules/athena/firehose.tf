
locals {
  jq_dt_format        = var.use_hive_partitions == true ? "strftime(\"%Y-%m-%d-%H\")" : "strftime(\"%Y/%m/%d/%H\")"
  firehose_partitions = var.use_hive_partitions == true ? "application=!{partitionKeyFromQuery:application}/dt=!{partitionKeyFromQuery:dt}" : "!{partitionKeyFromQuery:application}/!{partitionKeyFromQuery:dt}"
}

resource "aws_cloudwatch_log_group" "firehose" {
  name = "/aws/kinesisfirehose/${local.resource_name}"
}

resource "aws_cloudwatch_log_stream" "firehose" {
  name           = "DestinationDelivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

resource "aws_kinesis_firehose_delivery_stream" "s3" {
  destination = "extended_s3"
  name        = local.resource_name

  extended_s3_configuration {
    bucket_arn      = local.s3_bucket_arn
    role_arn        = aws_iam_role.firehose_role.arn
    buffer_size     = 128 # MBs
    buffer_interval = 300 # seconds

    # Using a prefix that contains Dynamic Partitioning namespaces (partitionKeyFromQuery)
    # requires dynamic partitioning to be enabled for this Firehose (see below)
    # The resulting date/time partitioning format is YYYY/MM/DD/HH
    # Reference: https://docs.aws.amazon.com/athena/latest/ug/partition-projection-kinesis-firehose-example.html#partition-projection-kinesis-firehose-example-iso-formatted-dates
    prefix              = "${local.table_location}/${local.firehose_partitions}/"
    error_output_prefix = "${local.table_location}_failures/!{firehose:error-output-type}/"

    dynamic_partitioning_configuration {
      enabled = true # this setting cannot be toggled post-creation
    }

    processing_configuration {
      enabled = "true"

      # Partition extraction (for application, dt); used in the prefix attribute above
      # The date is extracted from the record and dynamically used to partition the data
      # Dates from gsuite logs are in the format: 2022-07-25T00:05:53.167Z
      # Special handling is required for milliseconds due to a limitation with jq
      # Reference: https://github.com/stedolan/jq/issues/1409
      processors {
        type = "MetadataExtraction"
        parameters {
          parameter_name = "MetadataExtractionQuery"
          # Do not remove the escape characters below; they are required
          # Substituting "unknown" for missing id.applicationName fields ensures partitioning
          # still works. See the additional notes in glue.tf about this field
          parameter_value = "{application: (.id.applicationName // \"unknown\"), dt: .id.time | sub(\"(?<time>.*)\\\\..*Z\"; \"\\(.time)Z\") | strptime(\"%Y-%m-%dT%H:%M:%SZ\") | ${local.jq_dt_format}}"
        }
        parameters {
          parameter_name  = "JsonParsingEngine"
          parameter_value = "JQ-1.6"
        }
      }

      dynamic "processors" {
        for_each = var.deduplicate == true ? [1] : []

        content {
          type = "Lambda"

          parameters {
            parameter_name  = "LambdaArn"
            parameter_value = module.deduplication_function_alias.lambda_alias_arn
          }
          parameters {
            parameter_name  = "BufferSizeInMBs"
            parameter_value = "6" # 6 MB max for Lambda synchronous invocation, default = 3
          }
          parameters {
            parameter_name  = "BufferIntervalInSeconds"
            parameter_value = "300" # seconds, default = 60
          }
        }
      }
    }

    data_format_conversion_configuration {
      input_format_configuration {
        deserializer {
          open_x_json_ser_de {}
        }
      }

      output_format_configuration {
        serializer {
          parquet_ser_de {}
        }
      }

      schema_configuration {
        database_name = aws_glue_catalog_table.logs.database_name
        role_arn      = aws_iam_role.firehose_role.arn
        table_name    = aws_glue_catalog_table.logs.name
      }
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose.name
    }
  }
}

resource "aws_iam_role" "firehose_role" {
  name               = "${local.resource_name}-firehose"
  assume_role_policy = data.aws_iam_policy_document.firehose_arp.json
}

data "aws_iam_policy_document" "firehose_arp" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "firehose" {
  name   = "DefaultPolicy"
  role   = aws_iam_role.firehose_role.id
  policy = data.aws_iam_policy_document.firehose.json
}

data "aws_iam_policy_document" "firehose" {
  statement {
    actions = [
      "glue:GetTable",
      "glue:GetTableVersion",
      "glue:GetTableVersions"
    ]
    resources = [
      "arn:aws:glue:${local.region}:${local.account_id}:catalog",
      "arn:aws:glue:${local.region}:${local.account_id}:database/${aws_glue_catalog_table.logs.database_name}",
      aws_glue_catalog_table.logs.arn
    ]
  }

  statement {
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject"
    ]
    resources = [
      local.s3_bucket_arn,
      "${local.s3_bucket_arn}/*"
    ]
  }

  statement {
    actions   = ["logs:PutLogEvents"]
    resources = [aws_cloudwatch_log_stream.firehose.arn]
  }

  dynamic "statement" {
    for_each = var.s3_sse_kms_arn != "" ? [1] : []

    content {
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
      ]

      resources = [var.s3_sse_kms_arn]

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${local.region}.amazonaws.com"]
      }

      condition {
        test     = "StringLike"
        variable = "kms:EncryptionContext:aws:s3:arn"
        values   = ["${local.s3_bucket_arn}/${local.table_location}/*"]
      }
    }
  }
}
