output "game_events_topic_arn" {
  value = aws_sns_topic.game_events.arn
}

output "level_updates_queue_url" {
  value = module.level_updates.queue_url
}

output "chat_notices_queue_url" {
  value = aws_sqs_queue.chat_notices.url
}

output "instance_id" {
  value = aws_instance.k3s.id
}

output "public_ip" {
  value = aws_eip.instance.public_ip
}

output "ecr_registry" {
  value = split("/", aws_ecr_repository.app["chat"].repository_url)[0]
}

output "db_host" {
  value = aws_db_instance.main.address
}

output "db_master_secret_arn" {
  value = aws_db_instance.main.master_user_secret[0].secret_arn
}
