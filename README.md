# Secure Highly Available 3-Tier Architecture on AWS

Infrastructure-as-code project that provisions a secure, highly available three-tier application platform on AWS using **Terraform** and **Packer**.

The project is designed as a practical cloud/DevOps portfolio implementation, with clear separation between infrastructure, machine images, application code, and runtime configuration.

> **Current status:** AWS infrastructure, custom AMIs, application deployment model, IAM/Secrets Manager integration, and deployment documentation are implemented. Jenkins CI/CD automation is the next phase.

---

## Architecture

```text
                           Internet
                              │
                              ▼
                    ┌──────────────────┐
                    │ Public Frontend  │
                    │       ALB        │
                    └────────┬─────────┘
                             │
                    Web Private Subnets
                             │
                    ┌────────▼─────────┐
                    │ Frontend ASG     │
                    │ EC2 + Nginx     │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │ Internal Backend │
                    │       ALB        │
                    └────────┬─────────┘
                             │
                    App Private Subnets
                             │
                    ┌────────▼─────────┐
                    │ Backend ASG      │
                    │ EC2 + PHP/Apache │
                    └────────┬─────────┘
                             │
                    Secrets Manager
                             │
                             ▼
                    ┌──────────────────┐
                    │   RDS MySQL      │
                    │ Database Subnets │
                    └──────────────────┘
```

The application is distributed across multiple Availability Zones with separate network boundaries for the web, application, and database tiers.

---

## What This Project Demonstrates

- AWS VPC design with public, private, and database subnet layers
- Multi-AZ network architecture
- Internet Gateway and NAT Gateway routing
- Application Load Balancers for frontend and backend tiers
- Auto Scaling Groups for compute scalability and availability
- Amazon RDS MySQL in private database subnets
- Security-group-based tier isolation
- Terraform remote state stored in Amazon S3
- Independent Terraform stacks for network, database, and compute
- Immutable EC2 machine images built with Packer
- Runtime database credential retrieval from AWS Secrets Manager
- IAM roles and instance profiles for EC2 workloads
- AWS Systems Manager access without SSH keys on runtime instances
- Separation of infrastructure and application repositories

---

## Technology Stack

| Area | Technology |
|---|---|
| Cloud | AWS |
| Infrastructure as Code | Terraform |
| Image Builder | Packer |
| Compute | Amazon EC2, Auto Scaling Groups |
| Load Balancing | Application Load Balancer |
| Networking | Amazon VPC, Internet Gateway, NAT Gateway |
| Database | Amazon RDS for MySQL |
| Secrets | AWS Secrets Manager |
| Identity | AWS IAM |
| Instance Management | AWS Systems Manager |
| Frontend | HTML, CSS, JavaScript, Nginx |
| Backend | PHP, Apache |
| Dependency Management | Composer |
| State Management | Amazon S3 |
| Source Control | GitHub |
| CI/CD | Jenkins — next phase |

---

## Repository Structure

```text
.
├── packer/
│   ├── frontend/              # Frontend AMI build
│   └── backend/               # Backend AMI build
│
├── terraform/
│   ├── network/               # VPC, subnets, routing, security groups
│   ├── database/              # RDS, DB subnet group, Secrets Manager
│   └── compute/               # ALBs, ASGs, Launch Templates, IAM
│
├── docs/
│   ├── architecture.md
│   ├── aws-resources.md
│   ├── networking-security.md
│   ├── terraform.md
│   ├── packer.md
│   ├── application.md
│   ├── iam-secrets.md
│   └── deployment.md
│
├── .gitignore
└── README.md
```

The application is maintained separately in:

```text
3tier-app-code
```

This keeps application source code independent from the AWS infrastructure repository.

---

## Terraform Architecture

Terraform is divided into three independently managed stacks:

```text
terraform/network
       │
       ▼
terraform/database
       │
       ▼
terraform/compute
```

Each stack has its own remote state in S3:

```text
network/terraform.tfstate
database/terraform.tfstate
compute/terraform.tfstate
```

The database stack consumes network outputs, while the compute stack consumes outputs from both network and database.

This separation keeps infrastructure concerns modular and makes dependencies explicit.

---

## Packer and Immutable Infrastructure

Packer creates custom Amazon Machine Images for the frontend and backend tiers.

```text
Application Repository
        │
        ▼
      Packer
      /   \
     ▼     ▼
Frontend  Backend
  AMI      AMI
    │        │
    └───┬────┘
        ▼
     Terraform
        ▼
 Launch Templates
        ▼
     ASGs / EC2
```

The frontend AMI contains the Nginx configuration and frontend application.

The backend AMI contains Apache, PHP, Composer dependencies, the AWS SDK for PHP, backend APIs, and the database client.

EC2 instances are therefore launched from versioned machine images rather than configured manually after deployment.

---

## Security Model

The architecture uses multiple security boundaries.

### Network isolation

- Frontend instances run in private web subnets.
- Backend instances run in private application subnets.
- RDS runs in dedicated private database subnets.
- The database tier has no direct internet route.

### Security groups

Traffic is explicitly restricted between tiers:

```text
Internet
   │ TCP/80
   ▼
Frontend ALB
   │ TCP/80
   ▼
Frontend EC2
   │ TCP/80
   ▼
Backend ALB
   │ TCP/80
   ▼
Backend EC2
   │ TCP/3306
   ▼
RDS MySQL
```

### Secrets

Database credentials are not baked into the backend AMI.

The backend receives the Secrets Manager ARN through runtime configuration and uses its EC2 IAM role to retrieve the credentials when connecting to RDS.

---

## Application

The current application is a simple three-tier message application used to demonstrate the infrastructure.

### Frontend

- Static HTML/CSS/JavaScript
- Served by Nginx
- Proxies `/api/` requests to the internal backend ALB

### Backend

- PHP APIs running on Apache
- Uses the AWS SDK for PHP
- Retrieves database credentials from Secrets Manager
- Reads and writes application messages in MySQL

### Database

Amazon RDS MySQL contains the application database and `messages` table used by the current application.

The application repository is:

```text
3tier-app-code
```

---

## Deployment Flow

The current deployment model is:

```text
1. Deploy Network
       ↓
2. Deploy Database
       ↓
3. Build Frontend / Backend AMIs
       ↓
4. Store generated AMI IDs
       ↓
5. Deploy / update Compute
       ↓
6. Launch EC2 instances through ASGs
       ↓
7. Application becomes available through the frontend ALB
```

Detailed deployment instructions are available in [`docs/deployment.md`](docs/deployment.md).

---

## Prerequisites

The current manual workflow requires:

- AWS account and appropriate IAM permissions
- AWS CLI
- Terraform
- Packer
- Git
- `jq`
- Access to the application repository

AWS resources in the current baseline are deployed in `us-east-1`.

---

## Documentation

The project documentation is organized by architectural concern:

| Document | Purpose |
|---|---|
| [`architecture.md`](docs/architecture.md) | Overall architecture and design |
| [`aws-resources.md`](docs/aws-resources.md) | AWS resource inventory |
| [`networking-security.md`](docs/networking-security.md) | Network and security design |
| [`terraform.md`](docs/terraform.md) | Terraform architecture and state |
| [`packer.md`](docs/packer.md) | AMI build architecture |
| [`application.md`](docs/application.md) | Application architecture |
| [`iam-secrets.md`](docs/iam-secrets.md) | IAM and Secrets Manager design |
| [`deployment.md`](docs/deployment.md) | Deployment workflow and lifecycle |

---

## Project Lifecycle

### Current baseline

The working infrastructure is frozen at:

```text
baseline-v1.0
```

This represents the current documented architecture and deployment model.

### Next phase — Jenkins

Jenkins will become the orchestration layer for the DevOps/DevSecOps workflow.

The planned pipeline will connect the application and infrastructure repositories and automate activities such as:

```text
Checkout
   ↓
Validation
   ↓
Packer Build
   ↓
AMI Capture
   ↓
Terraform Plan
   ↓
Terraform Apply
   ↓
Deployment Validation
```

Jenkins automation is planned work and is not part of the current baseline.

---

## Future Application Evolution

The current application is intentionally simple so the infrastructure can be demonstrated clearly.

A future application iteration is planned to modernize the application to:

```text
React frontend
       ↓
Node.js backend
       ↓
MySQL / RDS
```

The infrastructure architecture can remain largely unchanged while the application evolves.

---

## Portfolio Focus

This project is primarily a **cloud infrastructure and DevOps architecture project**, rather than an application-development project.

It demonstrates how to design and implement a production-style AWS platform with:

- High availability
- Network segmentation
- Load balancing
- Auto scaling
- Infrastructure as code
- Immutable machine images
- IAM-based workload access
- Centralized secret management
- Remote Terraform state
- Clear separation of infrastructure and application responsibilities

The next stage extends this foundation into a Jenkins-based DevSecOps delivery pipeline.
