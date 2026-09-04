#!/bin/bash

set -e

echo "Initializing Packer plugins..."
packer init .

VPC_ID=$(terraform -chdir=../../terraform/network output -raw vpc_id)
SUBNET_IDS=$(terraform -chdir=../../terraform/network output -json public_subnet_ids)
SUBNET_ID=$(echo "$SUBNET_IDS" | jq -r '.[0]')

if [ -z "$VPC_ID" ] || [ -z "$SUBNET_ID" ]; then
    echo "Error: Could not retrieve VPC ID or subnet ID from Terraform state"
    exit 1
fi

echo "Using VPC ID: $VPC_ID"
echo "Using Subnet ID: $SUBNET_ID"

echo "Creating security group for Packer..."

PACKER_SG_ID=$(aws ec2 create-security-group \
    --group-name "packer-frontend-sg-$(date +%s)" \
    --description "Temporary security group for frontend Packer build" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' \
    --output text)

echo "Created security group: $PACKER_SG_ID"

echo "Configuring temporary SSH access..."

aws ec2 authorize-security-group-ingress \
    --group-id "$PACKER_SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

SOURCE_AMI=$(aws ec2 describe-images \
    --owners amazon \
    --filters \
        "Name=name,Values=al2023-ami-2023.*-x86_64" \
        "Name=state,Values=available" \
    --query "sort_by(Images, &CreationDate)[-1].ImageId" \
    --output text)

if [ -z "$SOURCE_AMI" ] || [ "$SOURCE_AMI" = "None" ]; then
    echo "Error: Could not find Amazon Linux 2023 AMI"
    exit 1
fi

echo "Using latest Amazon Linux 2023 AMI: $SOURCE_AMI"

mkdir -p ../../terraform/compute/ami_ids

echo "Building frontend AMI..."

PACKER_LOG=1 PACKER_LOG_PATH=packer.log packer build \
  -var "aws_region=us-east-1" \
  -var "source_ami=$SOURCE_AMI" \
  -var "instance_type=t3.micro" \
  -var "vpc_id=$VPC_ID" \
  -var "subnet_id=$SUBNET_ID" \
  -var "ssh_username=ec2-user" \
  -var "security_group_id=$PACKER_SG_ID" \
  frontend.pkr.hcl | tee >(grep -Eo 'ami-[a-z0-9]{17}' | tail -n1 > ../../terraform/compute/ami_ids/frontend_ami.txt)

echo "Cleaning up Packer security group..."

aws ec2 delete-security-group \
    --group-id "$PACKER_SG_ID"

echo "Frontend AMI ID has been saved to ../../terraform/compute/ami_ids/frontend_ami.txt"