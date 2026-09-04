# ---------------------------------------------------------
# Frontend EC2 IAM Role
# ---------------------------------------------------------

resource "aws_iam_role" "frontend_ec2_role" {
  name = "${var.project_name}-frontend-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-frontend-ec2-role"
    Environment = var.environment
  }
}


# Allow frontend EC2 instances to use Systems Manager
resource "aws_iam_role_policy_attachment" "frontend_ssm" {
  role       = aws_iam_role.frontend_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


# ---------------------------------------------------------
# Backend EC2 IAM Role
# ---------------------------------------------------------

resource "aws_iam_role" "backend_ec2_role" {
  name = "${var.project_name}-backend-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-backend-ec2-role"
    Environment = var.environment
  }
}


# Allow backend EC2 instances to use Systems Manager
resource "aws_iam_role_policy_attachment" "backend_ssm" {
  role       = aws_iam_role.backend_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ---------------------------------------------------------
# Frontend EC2 Instance Profile
# ---------------------------------------------------------

resource "aws_iam_instance_profile" "frontend_ec2_profile" {
  name = "${var.project_name}-frontend-ec2-profile"
  role = aws_iam_role.frontend_ec2_role.name

  tags = {
    Name        = "${var.project_name}-frontend-ec2-profile"
    Environment = var.environment
  }
}


# ---------------------------------------------------------
# Backend EC2 Instance Profile
# ---------------------------------------------------------

resource "aws_iam_instance_profile" "backend_ec2_profile" {
  name = "${var.project_name}-backend-ec2-profile"
  role = aws_iam_role.backend_ec2_role.name

  tags = {
    Name        = "${var.project_name}-backend-ec2-profile"
    Environment = var.environment
  }
}

# ---------------------------------------------------------
# Backend Secrets Manager Access
# ---------------------------------------------------------

resource "aws_iam_role_policy" "backend_secrets_access" {
  name = "${var.project_name}-backend-secrets-access"
  role = aws_iam_role.backend_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "secretsmanager:GetSecretValue"
        ]

        Resource = data.terraform_remote_state.database.outputs.db_secret_arn
      }
    ]
  })
}