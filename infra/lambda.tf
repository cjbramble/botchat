locals {
  announcer_zip = "${path.module}/../lambdas/announcer/function.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "announcer" {
  name               = "botchat-announcer"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  # Lambda logs to /aws/lambda/<function name>.
  announcer_log_group_arn = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/botchat-announcer"
}

# Read/delete from the announcements queue only, and write logs to the function's own log group only.
resource "aws_iam_role_policy" "announcer_consume" {
  role = aws_iam_role.announcer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
        ]
        Resource = module.announcements.queue_arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        # The bare ARN is the group itself; ":*" covers the log streams inside it.
        Resource = [local.announcer_log_group_arn, "${local.announcer_log_group_arn}:*"]
      },
    ]
  })
}

# ...and send to exactly one queue
resource "aws_iam_role_policy" "announcer_send" {
  role = aws_iam_role.announcer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.chat_notices.arn
    }]
  })
}

resource "aws_lambda_function" "announcer" {
  function_name    = "botchat-announcer"
  role             = aws_iam_role.announcer.arn
  runtime          = "provided.al2023"
  handler          = "bootstrap"
  architectures    = ["arm64"]
  filename         = local.announcer_zip
  source_code_hash = filebase64sha256(local.announcer_zip)
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      CHAT_NOTICES_QUEUE_URL = aws_sqs_queue.chat_notices.url
    }
  }
}

resource "aws_lambda_event_source_mapping" "announcer" {
  event_source_arn        = module.announcements.queue_arn
  function_name           = aws_lambda_function.announcer.arn
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]
}
