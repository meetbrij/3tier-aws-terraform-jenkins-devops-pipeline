packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "source_ami" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ssh_username" {
  type    = string
  default = "ec2-user"
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "backend_alb_dns_name" {
  type = string
}

source "amazon-ebs" "frontend" {
  region            = var.aws_region
  source_ami        = var.source_ami
  instance_type     = var.instance_type
  ssh_username      = var.ssh_username
  vpc_id            = var.vpc_id
  subnet_id         = var.subnet_id
  security_group_id = var.security_group_id

  associate_public_ip_address = true

  temporary_key_pair_name = "packer-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  ssh_interface          = "public_ip"
  ssh_timeout            = "10m"
  ssh_handshake_attempts = 30
  communicator           = "ssh"
  ssh_pty                = true

  ami_name        = "three-tier-frontend-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  ami_description = "Frontend AMI with Nginx and frontend application"

  tags = {
    Name        = "three-tier-frontend"
    Environment = "dev"
    Component   = "frontend"
  }
}

build {
  name = "three-tier-frontend"

  sources = [
    "source.amazon-ebs.frontend"
  ]

  provisioner "shell" {
    inline = [
      "sudo dnf update -y",
      "sudo dnf install -y nginx git"
    ]
  }

  provisioner "shell" {
    inline = [
      "cd /tmp",
      "git clone https://github.com/meetbrij/3tier-app-code.git"
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /usr/share/nginx/html",
      "sudo cp -r /tmp/3tier-app-code/frontend/* /usr/share/nginx/html/"
    ]
  }

  # Configure Nginx with the internal Backend ALB
  provisioner "shell" {
    inline = [
      "sudo sh -c \"sed 's|http://update-me|http://${var.backend_alb_dns_name}|' /tmp/3tier-app-code/infrastructure/nginx_config > /etc/nginx/conf.d/default.conf\"",
      "sudo nginx -t"
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo systemctl enable nginx",
      "sudo systemctl restart nginx"
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo rm -rf /tmp/3tier-app-code",
      "sudo dnf remove -y git"
    ]
  }

  post-processor "manifest" {
    output = "manifest.json"
  }
}