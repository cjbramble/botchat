module "level_updates" {
  source      = "./modules/fanout_queue"
  name        = "level-updates"
  topic_arn   = aws_sns_topic.game_events.arn
  event_types = ["player.leveled_up"]
}

module "announcements" {
  source             = "./modules/fanout_queue"
  name               = "announcements"
  topic_arn          = aws_sns_topic.game_events.arn
  event_types        = ["player.leveled_up"]
  visibility_timeout = 60 # at least 6x the Lambda's 10 s timeout
}

# Not subscribed to SNS: only the Lambda writes here, only chat reads.
resource "aws_sqs_queue" "chat_notices_dlq" {
  name = "chat-notices-dlq"
}

resource "aws_sqs_queue" "chat_notices" {
  name = "chat-notices"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.chat_notices_dlq.arn
    maxReceiveCount     = 5
  })
}
