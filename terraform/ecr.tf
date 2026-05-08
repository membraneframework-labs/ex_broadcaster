resource "aws_ecr_repository" "ex_broadcaster" {
  name                 = "ex-broadcaster"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "ex_broadcaster" {
  repository = aws_ecr_repository.ex_broadcaster.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      }
    ]
  })
}

output "ecr_repository_url" {
  value       = aws_ecr_repository.ex_broadcaster.repository_url
  description = "Use this as the image: prefix in k8s/deployment.yaml"
}
