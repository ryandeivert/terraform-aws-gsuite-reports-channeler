
resource "aws_sns_topic_subscription" "firehose" {
  count                 = var.enable == true ? 1 : 0
  topic_arn             = var.sns_topic_arn
  protocol              = "firehose"
  endpoint              = aws_kinesis_firehose_delivery_stream.s3.arn
  subscription_role_arn = aws_iam_role.sns_firehose_role.arn
  raw_message_delivery  = true
  filter_policy_scope   = "MessageBody"
  filter_policy         = var.filter_policy # default = null
}

resource "aws_iam_role" "sns_firehose_role" {
  name               = "${local.resource_name}-sns"
  assume_role_policy = data.aws_iam_policy_document.sns_arp.json
}

data "aws_iam_policy_document" "sns_arp" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "sns" {
  name   = "SNSFirehose"
  role   = aws_iam_role.sns_firehose_role.id
  policy = data.aws_iam_policy_document.sns.json
}

data "aws_iam_policy_document" "sns" {
  statement {
    actions = [
      "firehose:DescribeDeliveryStream",
      "firehose:ListDeliveryStreams",
      "firehose:ListTagsForDeliveryStream",
      "firehose:PutRecord",
      "firehose:PutRecordBatch",
    ]
    resources = [aws_kinesis_firehose_delivery_stream.s3.arn]
  }
}
