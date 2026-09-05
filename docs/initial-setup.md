# Initial Setup Guide

This document describes the tools and environment required to work with the three-tier AWS Terraform/Packer project from a local development machine.

## 1. Prerequisites

You need:

- An AWS account
- An IAM identity with permissions required to create and manage the project resources
- GitHub access to the infrastructure and application repositories
- A local terminal
- Internet connectivity

The current project is deployed in the AWS `us-east-1` region.

---

## 2. Install Git

Verify whether Git is already installed:

```bash
git --version
```

If it is not installed, install Git using the package manager appropriate for your operating system.

Verify:

```bash
git --version
```

Clone the infrastructure repository:

```bash
git clone https://github.com/meetbrij/3tier-aws-terraform-jenkins-devops-pipeline.git
cd 3tier-aws-terraform-jenkins-devops-pipeline
```

Clone the application repository separately:

```bash
git clone https://github.com/meetbrij/3tier-app-code.git
```

---

## 3. Install AWS CLI

Install AWS CLI v2 using the official installation method for your operating system.

Verify:

```bash
aws --version
```

Configure credentials:

```bash
aws configure
```

Provide the required AWS credentials and default region when prompted.

For this project, the infrastructure is deployed in:

```text
us-east-1
```

Verify the configured identity:

```bash
aws sts get-caller-identity
```

It is recommended to use an IAM role or appropriately scoped IAM identity for real deployments. The learning environment may temporarily use broader permissions while the project is being built.

---

## 4. Install Terraform

Install a current Terraform version compatible with the project.

Verify:

```bash
terraform version
```

The repository contains Terraform lock files so that provider dependency versions can be reproduced consistently.

---

## 5. Install Packer

Install HashiCorp Packer.

Verify:

```bash
packer version
```

Packer is used to create the frontend and backend EC2 AMIs.

---

## 6. Install jq

The Packer build scripts use `jq` to process Terraform JSON output.

Verify:

```bash
jq --version
```

Install it using the package manager appropriate for your operating system if necessary.

---

## 7. Verify AWS Region

The current infrastructure is built in `us-east-1`.

You can explicitly set the region for commands when required:

```bash
export AWS_DEFAULT_REGION=us-east-1
```

Verify:

```bash
aws configure get region
```

The Packer scripts also explicitly pass `us-east-1` to the Packer build.

---

## 8. Verify Terraform and AWS Access

Before creating resources, verify that Terraform can initialize and that AWS credentials are available.

For example:

```bash
cd terraform/network
terraform init
```

Then:

```bash
terraform validate
```

A successful validation confirms that the Terraform configuration is syntactically valid.

---

## 9. Initial Terraform Deployment

The Terraform stacks are deployed in dependency order.

### Network

```bash
cd terraform/network
terraform init
terraform validate
terraform plan
terraform apply
```

### Database

```bash
cd ../database
terraform init
terraform validate
terraform plan
terraform apply
```

### Compute

```bash
cd ../compute
terraform init
terraform validate
terraform plan
terraform apply
```

The database stack consumes network outputs, and the compute stack consumes network and database outputs.

---

## 10. Build the Frontend AMI

After the required Terraform dependencies exist, build the frontend AMI:

```bash
cd ../../packer/frontend
AWS_DEFAULT_REGION=us-east-1 ./build_ami.sh
```

The script:

1. Initializes the Packer plugin.
2. Reads required Terraform outputs.
3. Creates temporary build security infrastructure.
4. Finds the latest Amazon Linux 2023 base AMI.
5. Builds the frontend AMI.
6. Saves the resulting AMI ID for Terraform compute configuration.
7. Removes the temporary Packer security group.

The generated AMI ID is written to:

```text
terraform/compute/ami_ids/frontend_ami.txt
```

---

## 11. Build the Backend AMI

Build the backend AMI:

```bash
cd ../backend
AWS_DEFAULT_REGION=us-east-1 ./build_ami.sh
```

The script builds the backend image and saves its AMI ID to:

```text
terraform/compute/ami_ids/backend_ami.txt
```

The backend AMI contains the required Apache/PHP runtime, Composer dependencies, AWS SDK for PHP, backend API code, and database client.

---

## 12. Deploy or Update Compute

Once the required AMI IDs are available, deploy or update the compute stack:

```bash
cd ../../terraform/compute
terraform plan
terraform apply
```

Terraform uses the AMI IDs to configure the frontend and backend Launch Templates.

The Auto Scaling Groups then launch instances from those images.

---

## 13. Verify the Deployment

After deployment, verify the main infrastructure components in AWS:

- Frontend Application Load Balancer
- Frontend Auto Scaling Group
- Backend internal Application Load Balancer
- Backend Auto Scaling Group
- RDS MySQL instance
- Secrets Manager secret
- EC2 Systems Manager managed instances

The application is accessed through the DNS name of the public frontend ALB.

---

## 14. Important Local Tools Summary

| Tool | Why it is required |
|---|---|
| Git | Source control and repository management |
| AWS CLI | AWS authentication, inspection, and supporting deployment scripts |
| Terraform | Infrastructure provisioning and lifecycle management |
| Packer | Creation of immutable EC2 AMIs |
| jq | Parsing Terraform JSON output in build scripts |
| Terminal / shell | Running Terraform, Packer, and supporting scripts |

---

## 15. Credentials and Security

Do not commit AWS access keys, passwords, secret values, `.tfvars` files containing sensitive data, or other credentials to Git.

The project uses IAM roles for EC2 workloads and AWS Secrets Manager for runtime database credentials.

The current Packer scripts create temporary security groups with SSH access for the image-building process. This is acceptable for the current learning environment but should be restricted to the build environment in a production implementation.

---

## 16. Next Step

After completing the initial manual setup and confirming the infrastructure works, the next phase is to introduce Jenkins and automate the deployment workflow.
