packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

# ---------------------------------------------------------
# Variables
# ---------------------------------------------------------

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


# ---------------------------------------------------------
# Amazon EBS Builder
# ---------------------------------------------------------

source "amazon-ebs" "backend" {

  region = var.aws_region

  source_ami    = var.source_ami
  instance_type = var.instance_type

  ssh_username = var.ssh_username

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

  ami_name        = "three-tier-backend-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  ami_description = "Backend AMI with Apache, PHP, AWS SDK for PHP and application"

  tags = {
    Name        = "three-tier-backend"
    Environment = "dev"
    Component   = "backend"
  }
}


# ---------------------------------------------------------
# Backend AMI Build
# ---------------------------------------------------------

build {
  name = "three-tier-backend"

  sources = [
    "source.amazon-ebs.backend"
  ]


  # -------------------------------------------------------
  # Install Apache, PHP and required dependencies
  # -------------------------------------------------------

  provisioner "shell" {

    inline = [

      "sudo dnf update -y",

      "sudo dnf install -y httpd php php-fpm php-mysqli php-json php-mbstring php-cli php-curl php-xml git unzip",

      "sudo systemctl enable httpd",

      "sudo usermod -a -G apache ec2-user"
    ]
  }


  # -------------------------------------------------------
  # Install Composer
  # -------------------------------------------------------

  provisioner "shell" {

    inline = [

      "curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php",

      "sudo php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer",

      "composer --version"
    ]
  }


  # -------------------------------------------------------
  # Prepare application directory
  # -------------------------------------------------------

  provisioner "shell" {

    inline = [

      "sudo mkdir -p /var/www/html/api",

      "sudo chown -R ec2-user:apache /var/www/html"
    ]
  }


  # -------------------------------------------------------
  # Clone application repository
  # -------------------------------------------------------

  provisioner "shell" {

    inline = [

      "cd /tmp",

      "git clone https://github.com/meetbrij/3tier-app-code.git",

      "cd /tmp/3tier-app-code",

      "composer install --no-dev --optimize-autoloader"
    ]
  }


  # -------------------------------------------------------
  # Copy backend application into AMI
  # -------------------------------------------------------

  provisioner "shell" {

    inline = [

      "sudo cp -r /tmp/3tier-app-code/backend/api/* /var/www/html/api/",

      "sudo cp -r /tmp/3tier-app-code/vendor /var/www/html/vendor",

      "sudo chown -R apache:apache /var/www/html",

      "sudo find /var/www/html -type d -exec chmod 755 {} \\;",

      "sudo find /var/www/html -type f -exec chmod 644 {} \\;"
    ]
  }


  # -------------------------------------------------------
  # Clean up build artifacts
  # -------------------------------------------------------

  provisioner "shell" {

    inline = [

      "sudo rm -rf /tmp/3tier-app-code",

      "sudo rm -f /tmp/composer-setup.php",

      "sudo dnf remove -y git"
    ]
  }


  # -------------------------------------------------------
  # Generate AMI manifest
  # -------------------------------------------------------

  post-processor "manifest" {

    output = "manifest.json"
  }
}