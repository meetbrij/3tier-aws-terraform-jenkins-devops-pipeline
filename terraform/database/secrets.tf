resource "aws_secretsmanager_secret" "db_credentials" {
  name = "${var.project_name}/${var.environment}/database"

  tags = {
    Name        = "${var.project_name}-db-credentials"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
  })
}

resource "random_password" "db" {
  length  = 32

  special = true
}