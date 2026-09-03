terraform {
  backend "s3" {
    bucket = "3tier-aws-terraform-jenkins-devops-pipeline"
    key    = "network/terraform.tfstate"
    region = "us-east-1"
    use_lockfile = true
  }
} 