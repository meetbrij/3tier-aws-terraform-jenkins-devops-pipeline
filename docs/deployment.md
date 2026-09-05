# Deployment Architecture

## 1. Overview

The project uses Terraform and Packer to provision and deploy a highly available three-tier application on AWS.

The deployment is split into two related workflows:

```text
Infrastructure workflow
Terraform → AWS infrastructure

Image workflow
Application code → Packer → AMI → Terraform → EC2
```

The current implementation is designed so that networking, database infrastructure, machine images, and compute resources have clearly separated responsibilities.

---

## 2. Repositories

The project uses two repositories:

### Infrastructure repository

```text
3tier-aws-terraform-jenkins-devops-pipeline
```

Contains:

- Terraform
- Packer
- Deployment scripts
- Documentation
- Jenkins automation in the next phase

### Application repository

```text
3tier-app-code
```

Contains:

- Frontend
- Backend APIs
- Database initialization script
- Application dependencies

The infrastructure repository consumes the application repository during the Packer image-build process.

---

## 3. Infrastructure Deployment Order

Terraform stacks must be deployed in dependency order:

```text
┌─────────────────┐
│     Network     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    Database     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│     Compute     │
└─────────────────┘
```

### Step 1 — Network

Deploy:

```text
terraform/network/
```

This creates the VPC, subnets, routing, NAT Gateways, and security groups.

### Step 2 — Database

Deploy:

```text
terraform/database/
```

This consumes network remote-state outputs and creates the RDS database, DB subnet group, and Secrets Manager secret.

### Step 3 — Compute

Deploy:

```text
terraform/compute/
```

This consumes network and database remote-state outputs and creates the ALBs, Launch Templates, Auto Scaling Groups, and EC2 runtime configuration.

---

## 4. AMI Deployment Workflow

The EC2 instances are launched from Packer-built AMIs.

```text
Application Repository
          │
          ▼
       Packer
          │
     ┌────┴────┐
     ▼         ▼
Frontend AMI  Backend AMI
     │         │
     └────┬────┘
          ▼
    AMI ID files
          │
          ▼
       Terraform
          │
          ▼
   Launch Templates
          │
          ▼
    Auto Scaling Groups
          │
          ▼
         EC2
```

The current implementation stores the generated AMI IDs in:

```text
terraform/compute/ami_ids/frontend_ami.txt
terraform/compute/ami_ids/backend_ami.txt
```

Terraform reads these values when creating the Launch Templates.

---

## 5. Frontend Deployment

The frontend image is built from:

```text
packer/frontend/
```

The build script obtains the following Terraform outputs:

- VPC ID
- Public subnet ID
- Backend ALB DNS name

The backend ALB DNS name is passed to Packer and incorporated into the Nginx configuration.

The resulting AMI is then referenced by the frontend Launch Template.

The frontend Auto Scaling Group runs instances in the web private subnets behind the public frontend ALB.

---

## 6. Backend Deployment

The backend image is built from:

```text
packer/backend/
```

The image contains:

- Apache
- PHP
- Required PHP extensions
- Composer dependencies
- AWS SDK for PHP
- Backend API code
- MariaDB/MySQL command-line client

The resulting AMI is referenced by the backend Launch Template.

The backend Auto Scaling Group runs instances in the application private subnets behind the internal backend ALB.

---

## 7. Runtime Configuration

The backend database configuration is supplied at runtime rather than baked into the AMI.

Terraform passes:

```text
DB_SECRET_ARN
AWS_REGION
```

to the backend instance through Launch Template user data.

The PHP application then uses the EC2 IAM role to retrieve the database secret from Secrets Manager.

```text
Backend EC2
    │
    │ DB_SECRET_ARN
    ▼
Secrets Manager
    │
    │ credentials
    ▼
PHP API
    │
    ▼
RDS MySQL
```

---

## 8. Application Request Flow

Once deployment is complete, application traffic follows:

```text
Internet
   │
   ▼
Public Frontend ALB
   │
   ▼
Frontend EC2 / Nginx
   │
   │ /api/
   ▼
Internal Backend ALB
   │
   ▼
Backend EC2 / Apache / PHP
   │
   ▼
Secrets Manager
   │
   ▼
RDS MySQL
```

The database is not directly accessible from the internet.

---

## 9. Deployment Commands

The current deployment can be performed manually from the infrastructure repository.

### Network

```bash
cd terraform/network
terraform init
terraform plan
terraform apply
```

### Database

```bash
cd terraform/database
terraform init
terraform plan
terraform apply
```

### Compute

```bash
cd terraform/compute
terraform init
terraform plan
terraform apply
```

The exact variable values are environment-specific and should be supplied through the repository's configured Terraform variable mechanism.

---

## 10. Building the AMIs

### Frontend AMI

From:

```text
packer/frontend/
```

run:

```bash
AWS_DEFAULT_REGION=us-east-1 ./build_ami.sh
```

The script initializes the Packer plugin, retrieves required Terraform outputs, creates temporary build security infrastructure, identifies the latest Amazon Linux 2023 base AMI, builds the frontend image, and writes the AMI ID to:

```text
terraform/compute/ami_ids/frontend_ami.txt
```

### Backend AMI

From:

```text
packer/backend/
```

run:

```bash
AWS_DEFAULT_REGION=us-east-1 ./build_ami.sh
```

The script performs the corresponding backend image build and writes the AMI ID to:

```text
terraform/compute/ami_ids/backend_ami.txt
```

---

## 11. Updating an Application Deployment

For an application/image update, the deployment flow is:

```text
1. Update application code
          ↓
2. Build new frontend/backend AMI
          ↓
3. Update AMI ID references
          ↓
4. Run Terraform plan
          ↓
5. Apply Terraform changes
          ↓
6. Auto Scaling Groups use the new Launch Template version
          ↓
7. Instances are refreshed/replaced as required
```

This follows an immutable-image deployment model rather than manually modifying running EC2 instances.

---

## 12. Deployment Dependencies

The main dependencies are:

```text
Network
  ├── VPC
  ├── Subnets
  ├── Routing
  └── Security Groups
          │
          ▼
Database
  ├── RDS
  └── Secrets Manager
          │
          ▼
Compute
  ├── Frontend ALB / ASG
  └── Backend ALB / ASG
```

Packer has a dependency on the network and, for the frontend image, the backend ALB endpoint.

---

## 13. State Management

Terraform state is stored remotely in the S3 state bucket:

```text
3tier-aws-terraform-jenkins-devops-pipeline
```

with separate state objects for:

```text
network/terraform.tfstate
database/terraform.tfstate
compute/terraform.tfstate
```

The state bucket is retained independently from the application infrastructure lifecycle.

---

## 14. Destruction Order

When removing the deployed application infrastructure, destroy the Terraform stacks in reverse dependency order:

```text
Compute
   ↓
Database
   ↓
Network
```

The Terraform state bucket should remain available unless there is an explicit requirement to remove it.

Packer-created AMIs have a separate lifecycle and should be deregistered/cleaned up independently when no longer required.

---

## 15. Jenkins Integration — Next Phase

Jenkins will become the orchestration layer for the deployment workflow.

The planned relationship is:

```text
Application Repository
          │
          ▼
        Jenkins
          │
     ┌────┴─────┐
     ▼          ▼
   Packer     Terraform
     │          │
     ▼          ▼
    AMIs      AWS Infrastructure
     │          │
     └────┬─────┘
          ▼
     EC2 / ASGs
```

Jenkins will eventually automate stages such as:

1. Checkout source repositories.
2. Validate Terraform.
3. Build frontend and backend AMIs.
4. Capture AMI IDs.
5. Run Terraform plan.
6. Apply infrastructure changes.
7. Deploy the new application image.
8. Perform deployment validation.

Jenkins automation is a future phase and is not represented as an existing capability of the current baseline.

---

## 16. Current Deployment Principles

The deployment design follows these principles:

- Infrastructure is managed as code with Terraform.
- Server images are built with Packer.
- Application and infrastructure repositories remain separate.
- EC2 instances are launched from immutable AMIs.
- Application tiers run behind load balancers.
- Runtime database credentials are retrieved from Secrets Manager.
- Terraform state is stored remotely in S3.
- Network, database, and compute have independent Terraform state.

---

## 17. Baseline Reference

The documented deployment architecture corresponds to the working project baseline tagged:

```text
baseline-v1.0
```

This document describes the current deployment model and planned Jenkins integration without including troubleshooting history or migration steps.