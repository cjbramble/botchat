resource "aws_ecr_repository" "app" {
  for_each = toset(["chat", "game", "bots"])

  name                 = "botchat/${each.key}"
  image_tag_mutability = "IMMUTABLE" # a tag always means the same image
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 20 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 20 }
      action       = { type = "expire" }
    }]
  })
}
