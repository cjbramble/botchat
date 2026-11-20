# What the game may do: publish game events, nothing else.
resource "aws_iam_policy" "game_publisher" {
  name        = "botchat-game-publisher"
  description = "botchat game: publish to the game-events topic"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = aws_sns_topic.game_events.arn
    }]
  })
}

# What chat may do: read and delete from its two queues, nothing else.
resource "aws_iam_policy" "chat_consumer" {
  name        = "botchat-chat-consumer"
  description = "botchat chat: consume level-updates and chat-notices"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
        "sqs:GetQueueAttributes",
      ]
      Resource = [module.level_updates.queue_arn, aws_sqs_queue.chat_notices.arn]
    }]
  })
}
