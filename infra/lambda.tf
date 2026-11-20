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

# Read/delete from SQS and write CloudWatch logs.
# Broader than needed (it covers every queue): the infrastructure QA plan has you tighten it.
resource "aws_iam_role_policy_attachment" "announcer_sqs" {
  role       = aws_iam_role.announcer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
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
