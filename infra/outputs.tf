output "game_events_topic_arn" {
  value = aws_sns_topic.game_events.arn
}

output "level_updates_queue_url" {
  value = module.level_updates.queue_url
}

output "chat_notices_queue_url" {
  value = aws_sqs_queue.chat_notices.url
}
