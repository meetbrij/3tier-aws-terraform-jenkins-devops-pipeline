# Terraform Architecture

## 1. Overview

Terraform is used to provision and manage the AWS infrastructure for the three-tier application.

The infrastructure is intentionally divided into three independent Terraform stacks:

```text
terraform/
├── network/
├── database/
└── compute/
```

This separation keeps networking, data services, and compute/application infrastructure independently manageable while allowing the stacks to share required outputs through Terraform remote state.

---

## 2. Terraform Stack Architecture

```text
                    ┌──────────────────────┐
                    │   Terraform Network  │
                    │       Stack          │
                    └──────────┬───────────┘
                               │
                    network/terraform.tfstate
                               │
              ┌────────────────┴────────────────┐
              │                                 │
              ▼                                 ▼
   ┌──────────────────────┐          ┌──────────────────────┐
   │ Terraform Database   │          │ Terraform Compute    │
   │       Stack          │          │       Stack          │
   └──────────┬───────────┘          └──────────┬───────────┘
              │                                  │
   database/terraform.tfstate          compute/terraform.tfstate
              │                                  │
              └──────────────────┬───────────────┘
                                 ▼
                       AWS 3-Tier Infrastructure
```

### Dependency order

```text
Network
   ↓
Database
   ↓
Compute
```

The network stack is the foundation. The database stack consumes network outputs, while the compute stack consumes outputs from both the network and database stacks.

---

## 3. Network Stack

Location:

```text
terraform/network/
```

The network stack provisions the foundational VPC infrastructure, including:

- VPC
- Internet Gateway
- Public subnets
- Web private subnets
- Application private subnets
- Database subnets
- Elastic IPs
- NAT Gateways
- Public, private, and database route tables
- Route table associations
- Frontend ALB security group
- Frontend instance security group
- Backend ALB security group
- Backend instance security group
- RDS security group

The stack exposes outputs such as:

- VPC ID
- Public subnet IDs
- Web private subnet IDs
- Application private subnet IDs
- Database subnet IDs
- Route table IDs
- Security group IDs

These outputs become inputs to the downstream Terraform stacks.

---

## 4. Database Stack

Location:

```text
terraform/database/
```

The database stack consumes network information using Terraform remote state and provisions the database layer.

Resources include:

- RDS subnet group
- RDS MySQL instance
- Database credentials generated with `random_password`
- AWS Secrets Manager secret
- Secret version containing database connection information

The database stack currently uses:

- MySQL
- `db.t3.micro`
- 20 GB allocated storage
- `gp2` storage
- Database name: `appdb`
- Database port: `3306`
- Backup retention: 7 days

The stack exposes outputs including:

- RDS endpoint
- RDS address
- RDS username
- RDS security group ID
- Database secret ARN

The compute stack consumes the database secret ARN to configure backend instances.

---

## 5. Compute Stack

Location:

```text
terraform/compute/
```

The compute stack provisions the application tier and load-balancing components.

Resources include:

### Frontend

- Public Application Load Balancer
- Frontend target group
- HTTP listener on port 80
- Frontend Launch Template
- Frontend Auto Scaling Group
- Frontend EC2 IAM role and instance profile

Frontend instances run in the web private subnets and do not receive public IP addresses.

### Backend

- Internal Application Load Balancer
- Backend target group
- HTTP listener on port 80
- Backend Launch Template
- Backend Auto Scaling Group
- Backend EC2 IAM role and instance profile

Backend instances run in the application private subnets and do not receive public IP addresses.

The backend Launch Template receives the database secret ARN from the database remote state and configures it as an environment variable through user data.

---

## 6. Terraform Remote State

Terraform state is stored remotely in an S3 bucket:

```text
3tier-aws-terraform-jenkins-devops-pipeline
```

State files are separated by stack:

```text
network/terraform.tfstate
 database/terraform.tfstate
compute/terraform.tfstate
```

The separation allows each Terraform stack to maintain its own lifecycle and state while still sharing selected outputs.

The S3 state bucket is configured with:

- Versioning enabled
- Server-side encryption
- Bucket Key enabled
- S3 Block Public Access enabled
- Terraform state locking using the configured lockfile mechanism

The state bucket itself is intentionally retained independently from application infrastructure lifecycle operations.

---

## 7. Remote State Dependencies

### Database → Network

The database stack reads the network state:

```hcl
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = var.terraform_state_bucket
    key    = "network/terraform.tfstate"
    region = var.aws_region
  }
}
```

This provides values such as the database subnet IDs and RDS security group ID.

### Compute → Network

The compute stack reads:

```text
network/terraform.tfstate
```

This provides:

- VPC ID
- Public subnet IDs
- Web private subnet IDs
- Application private subnet IDs
- Security group IDs

### Compute → Database

The compute stack also reads:

```text
 database/terraform.tfstate
```

This provides the database secret ARN used by the backend instances.

---

## 8. AMI Integration

Terraform does not build the EC2 images directly. AMIs are created separately using Packer.

The compute stack reads the AMI IDs from local files:

```text
terraform/compute/ami_ids/frontend_ami.txt
terraform/compute/ami_ids/backend_ami.txt
```

Terraform loads these values through the `local_file` data source and uses them in the corresponding Launch Templates.

```text
Packer
  │
  ├── Frontend AMI
  └── Backend AMI
          │
          ▼
terraform/compute/ami_ids/
          │
          ▼
Terraform Launch Templates
          │
          ▼
Auto Scaling Groups
```

This creates a clear separation between image creation and infrastructure provisioning.

---

## 9. Terraform Resource Flow

The overall Terraform provisioning flow is:

```text
Terraform Network
       │
       ├── VPC
       ├── Subnets
       ├── Routing
       ├── NAT Gateways
       └── Security Groups
              │
              ▼
Terraform Database
       │
       ├── DB Subnet Group
       ├── RDS MySQL
       └── Secrets Manager
              │
              ▼
Terraform Compute
       │
       ├── Frontend ALB
       ├── Frontend ASG
       ├── Backend ALB
       └── Backend ASG
```

---

## 10. Configuration and Variables

The stacks use Terraform variables for environment-specific configuration rather than hard-coding the main deployment parameters.

Examples include:

- AWS region
- Environment name
- Project name
- VPC CIDR
- Subnet CIDRs
- Availability Zones
- EC2 instance types
- Auto Scaling desired/min/max capacity
- RDS instance class
- RDS engine/version
- Database name
- Database port
- Terraform state bucket

This keeps the Terraform modules reusable and makes the infrastructure easier to parameterize for additional environments later.

---

## 11. State and Lifecycle Model

Each stack has an independent Terraform lifecycle.

Recommended provisioning order:

```bash
terraform -chdir=terraform/network init
terraform -chdir=terraform/network plan
terraform -chdir=terraform/network apply

terraform -chdir=terraform/database init
terraform -chdir=terraform/database plan
terraform -chdir=terraform/database apply

terraform -chdir=terraform/compute init
terraform -chdir=terraform/compute plan
terraform -chdir=terraform/compute apply
```

The reverse order is used when destroying the application infrastructure:

```text
Compute
   ↓
Database
   ↓
Network
```

The Terraform state bucket is retained separately.

---

## 12. Current Design Principles

The Terraform implementation follows these principles:

1. **Separation of concerns** — network, database, and compute have independent states.
2. **Remote state sharing** — downstream stacks consume only the outputs they require.
3. **Immutable application images** — EC2 instances are launched from Packer-built AMIs.
4. **Private application tiers** — frontend and backend EC2 instances are deployed without public IP addresses.
5. **Infrastructure as code** — AWS resources are defined declaratively and version controlled.
6. **Repeatability** — the environment can be recreated from Terraform configuration and Packer AMIs.
7. **Independent lifecycle management** — each stack can be planned, applied, and destroyed separately.

---

## 13. Current Baseline vs Future Improvements

The current baseline intentionally keeps the Terraform implementation straightforward for the portfolio project.

Future improvements may include:

- Reusable Terraform modules
- Separate environment directories or workspaces
- CI validation with `terraform fmt`, `validate`, and `plan`
- Policy/security scanning
- Remote AMI ID management rather than local AMI ID files
- Stronger state-bucket controls
- Additional production hardening

These are future enhancements and are not represented as existing capabilities in the current baseline.

---

## 14. Baseline Reference

The documented Terraform architecture corresponds to the working project baseline tagged:

```text
baseline-v1.0
```

This document describes the current Terraform design and does not include troubleshooting history or migration steps.