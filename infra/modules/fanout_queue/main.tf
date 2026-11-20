variable "name" {
  type = string
}

variable "topic_arn" {
  type = string
}

variable "event_types" {
  type        = list(string)
  description = "Only messages whose `type` attribute is in this list are delivered."
}

variable "visibility_timeout" {
  type    = number
  default = 30
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-dlq"
  message_retention_seconds = 1209600 # 14 days to investigate failures
}

resource "aws_sqs_queue" "this" {
  name                       = var.name
  visibility_timeout_seconds = var.visibility_timeout
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })
}

data "aws_iam_policy_document" "allow_topic" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.this.arn]
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [var.topic_arn]
    }
  }
}

resource "aws_sqs_queue_policy" "this" {
  queue_url = aws_sqs_queue.this.id
  policy    = data.aws_iam_policy_document.allow_topic.json
}

resource "aws_sns_topic_subscription" "this" {
  topic_arn            = var.topic_arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.this.arn
  raw_message_delivery = true
  filter_policy        = jsonencode({ type = var.event_types })
}

output "queue_url" {
  value = aws_sqs_queue.this.url
}

output "queue_arn" {
  value = aws_sqs_queue.this.arn
}
