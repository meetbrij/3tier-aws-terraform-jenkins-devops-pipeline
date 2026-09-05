# Secure Highly Available 3-Tier Architecture on AWS

[![AWS](https://img.shields.io/badge/AWS-Cloud-232F3E?logo=amazonaws&logoColor=white)](https://aws.amazon.com/)
[![Terraform](https://img.shields.io/badge/Terraform-IaC-844FBA?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Packer](https://img.shields.io/badge/Packer-Image%20Build-02A8EF?logo=packer&logoColor=white)](https://www.packer.io/)
[![GitHub](https://img.shields.io/badge/GitHub-Source%20Control-181717?logo=github&logoColor=white)](https://github.com/)
[![AWS Secrets Manager](https://img.shields.io/badge/AWS-Secrets%20Manager-232F3E?logo=amazonaws&logoColor=white)](https://aws.amazon.com/secrets-manager/)
[![AWS Systems Manager](https://img.shields.io/badge/AWS-Systems%20Manager-232F3E?logo=amazonaws&logoColor=white)](https://aws.amazon.com/systems-manager/) 
[![Jenkins](https://img.shields.io/badge/Jenkins-DevSecOps%20CI%2FCD-D24939?logo=jenkins&logoColor=white)](https://www.jenkins.io/)

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
                    │ EC2 + Nginx      │
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

## Project Use Cases & Architecture Choice

This architecture is best suited for applications that require a traditional VM-based deployment model while still benefiting from AWS high availability, horizontal scaling, infrastructure as code, and automated image-based deployments.

### Suitable Project Use Cases

Not every production application needs a highly complex or massively scalable architecture.
In industries such as banking, healthcare, and insurance, many applications are internal enterprise systems used by a relatively limited and predictable number of employees. An application serving 1,000–5,000 internal users may not require Kubernetes, dozens of microservices, or sophisticated distributed architecture.
However, limited scale does not mean reduced infrastructure requirements. For these applications, security, high availability, controlled access, resilience, and infrastructure automation can still be non-negotiable requirements.

This architecture is a good fit for:

- Internal enterprise applications with a limited and predictable user base
- Banking, healthcare, insurance, and other regulated workloads
- Traditional 3-tier applications where the application architecture itself is relatively straightforward
- Legacy or monolithic applications that are not yet containerized
- Java, .NET, PHP, Python, and similar applications running on virtual machines
- Applications that require strong security and network isolation despite moderate traffic
- Applications requiring high availability and automated instance replacement
- On-premises applications being migrated to AWS without immediately adopting Kubernetes
- Small to medium production workloads where Kubernetes would introduce unnecessary operational complexity

### Why EC2 + Packer + Auto Scaling?

The project deliberately uses **EC2, Packer, Auto Scaling Groups, and ALBs** rather than Docker and Kubernetes.

| Technology | Why it is used |
|---|---|
| **EC2** | Provides a familiar VM-based runtime for traditional enterprise applications |
| **Packer** | Creates immutable, repeatable AMIs with the application and required runtime pre-configured |
| **Auto Scaling Groups** | Provides horizontal scaling, instance replacement, and Multi-AZ resilience |
| **Application Load Balancer** | Distributes application traffic across healthy instances |
| **Terraform** | Makes the infrastructure repeatable, version-controlled, and automated |

This approach provides many of the benefits expected from a production AWS environment without introducing the operational complexity of a container orchestration platform.

### Key Principle

The scale of the application may be modest, but the infrastructure supporting it can still require enterprise-grade security, high availability, resilience, and automation.

---

## Key Components

| Component | Purpose |
|---|---|
| Amazon VPC | Provides the isolated network boundary for the application. |
| Public, private and database subnets | Separate internet-facing infrastructure, application workloads, and database workloads. |
| Internet Gateway | Provides internet connectivity for public subnets. |
| NAT Gateways | Provide controlled outbound internet access for private workloads. |
| Frontend Application Load Balancer | Provides the public entry point and distributes traffic across frontend instances. |
| Backend Application Load Balancer | Provides an internal application endpoint and distributes API traffic across backend instances. |
| Frontend Auto Scaling Group | Maintains multiple frontend instances and supports horizontal scaling. |
| Backend Auto Scaling Group | Maintains multiple backend instances and supports horizontal scaling. |
| Amazon RDS for MySQL | Provides the managed relational database layer. |
| AWS Secrets Manager | Stores database credentials separately from application code and machine images. |
| IAM roles and instance profiles | Provide workload-level AWS permissions without embedding long-lived credentials in EC2 instances. |
| AWS Systems Manager | Provides management access to EC2 without requiring runtime SSH keys. |
| Amazon S3 | Stores Terraform remote state independently for the infrastructure stacks. |
| Terraform | Defines and manages AWS infrastructure as code, making the environment repeatable and version controlled. |
| Packer | Builds immutable frontend and backend AMIs so EC2 instances start with a known application/runtime configuration. |

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

| Area | Technology | Why it is used |
|---|---|---|
| Cloud | AWS | Provides the managed networking, compute, load balancing, database, identity, secrets, and operational services required by the architecture. |
| Infrastructure as Code | Terraform | Defines the complete infrastructure declaratively, provides repeatability, version control, dependency management, and a predictable plan/apply lifecycle. |
| Image Builder | Packer | Creates immutable, repeatable EC2 AMIs containing the required OS packages, runtime, dependencies, configuration, and application code. |
| Compute | Amazon EC2, Auto Scaling Groups | Provides flexible compute capacity while ASGs maintain multiple instances and support horizontal scaling and replacement. |
| Load Balancing | Application Load Balancer | Provides stable application endpoints and distributes traffic across healthy EC2 instances. A separate internal ALB keeps backend APIs private. |
| Networking | Amazon VPC, Internet Gateway, NAT Gateway | Provides network isolation, subnet segmentation, internet ingress for the public tier, and controlled outbound access for private workloads. |
| Database | Amazon RDS for MySQL | Provides a managed relational database with AWS handling the underlying database infrastructure and availability capabilities. |
| Secrets | AWS Secrets Manager | Keeps database credentials out of application code and AMIs and allows the backend to retrieve them at runtime. |
| Identity | AWS IAM | Provides fine-grained permissions for EC2 workloads so applications can access AWS services without storing access keys. |
| Instance Management | AWS Systems Manager | Enables operational access to EC2 instances without exposing SSH access or requiring persistent SSH key pairs. |
| State Management | Amazon S3 | Centralizes Terraform state remotely and separates state for the network, database, and compute stacks. |
| Dependency Management | Composer | Installs and manages the PHP dependencies required by the backend, including the AWS SDK for PHP. |
| Source Control | GitHub | Stores version-controlled infrastructure and application source code and provides the foundation for the future CI/CD workflow. |
| CI/CD | Jenkins — next phase | Will orchestrate validation, Packer image builds, Terraform planning/apply, and deployment in the next phase. |

*Frontend and backend technologies are intentionally not emphasized here because the application will later be modernized to React and Node.js.*

---

## Key Architecture Decisions and Concerns

Several deliberate decisions were made while building the current baseline.

### 1. Separate Terraform stacks

Network, database, and compute are maintained as independent Terraform stacks with separate state files.

```text
Network → Database → Compute
```

This makes infrastructure boundaries clear, reduces the scope of individual Terraform operations, and makes dependencies explicit through remote state.

### 2. Private application and database tiers

Frontend and backend EC2 instances do not need to be directly reachable from the internet. The frontend ALB is public, while the backend ALB is internal and RDS remains in dedicated database subnets.

### 3. Security-group-based tier isolation

Traffic is restricted to the required paths and ports:

```text
Internet → Frontend ALB        TCP/80
Frontend ALB → Frontend EC2   TCP/80
Frontend EC2 → Backend ALB    TCP/80
Backend ALB → Backend EC2     TCP/80
Backend EC2 → RDS             TCP/3306
```

### 4. Secrets are consumed at runtime

Database credentials are stored in Secrets Manager rather than being embedded in the application repository or Packer image. The backend EC2 role is granted access to the required secret.

### 5. IAM roles instead of static AWS credentials

EC2 workloads use IAM instance profiles. The application therefore does not require AWS access keys to call Secrets Manager.

### 6. Packer for immutable machine images

Rather than configuring running EC2 instances manually, the required operating-system packages, runtime dependencies, application code, and configuration are built into AMIs.

This gives the Auto Scaling Groups a consistent instance starting point.

### 7. Application and infrastructure repositories remain separate

Application code is maintained independently from AWS infrastructure. Packer connects the two during the image-build process.

This separation allows the application to evolve without restructuring the infrastructure repository.

### 8. S3 remote state

Terraform state is stored remotely in S3 with separate state objects for each stack. The state bucket is treated as a persistent infrastructure dependency rather than something destroyed with the application environment.

### 9. Runtime instances are managed through Systems Manager

The compute layer does not depend on SSH key pairs for normal runtime administration. Systems Manager provides the management path through the EC2 IAM role.

### 10. Current implementation favors learning clarity over complete production hardening

The current project intentionally focuses on establishing the architecture and DevOps patterns first. Some controls will be strengthened as the project evolves, particularly around CI/CD security, IAM least privilege, Packer build networking, secret lifecycle, image lifecycle, and deployment governance.

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

The detailed deployment workflow is documented in [`docs/deployment.md`](docs/deployment.md).

---

## Initial Setup

Before deploying the project for the first time, install and configure the required tools.

The complete setup procedure is documented separately in [`docs/initial-setup.md`](docs/initial-setup.md).

At a high level, the environment requires:

- Git
- AWS CLI
- Terraform
- Packer
- `jq`
- An AWS account with appropriate permissions
- Access to the application repository

---

## Production Readiness

The current architecture incorporates several production-oriented patterns, but it should be considered a **production-style portfolio implementation rather than a fully production-ready platform**.

### Implemented

- Multi-AZ network design
- Public/private/database subnet separation
- Private application and database workloads
- Public and internal load balancers
- Auto Scaling Groups
- RDS managed database
- Security-group-based tier isolation
- Secrets Manager integration
- IAM roles for EC2 workloads
- Systems Manager-based instance management
- Terraform remote state in S3
- Immutable Packer-built AMIs
- Separate infrastructure and application repositories

### Areas for further hardening

- Replace broad build-time permissions with tightly scoped CI/CD IAM roles
- Restrict temporary Packer SSH access to the build environment rather than the internet
- Improve Terraform state protection and access controls for production use
- Adopt a stronger secret lifecycle strategy and avoid exposing sensitive values through Terraform state where possible
- Establish AMI retention and cleanup policies
- Add HTTPS/TLS certificates and secure public ingress
- Add AWS WAF and appropriate edge protection
- Add centralized logging and monitoring
- Add CloudWatch alarms and operational dashboards
- Add backup, restore, and disaster-recovery procedures
- Add CI/CD approval and deployment governance through Jenkins
- Add automated security and dependency scanning in the DevSecOps pipeline
- Add deployment validation and rollback mechanisms

These improvements form part of the future DevSecOps evolution of the project.

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
│   ├── deployment.md
│   └── initial-setup.md
│
├── .gitignore
└── README.md
```

The application is maintained separately in:

```text
3tier-app-code
```

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

---

## Security Model

The architecture uses multiple security boundaries.

### Network isolation

- Frontend instances run in private web subnets.
- Backend instances run in private application subnets.
- RDS runs in dedicated private database subnets.
- The database tier has no direct internet route.

### Secrets

Database credentials are not baked into the backend AMI.

The backend receives the Secrets Manager ARN through runtime configuration and uses its EC2 IAM role to retrieve the credentials when connecting to RDS.

---

## Application

The current application is a simple three-tier message application used to demonstrate the infrastructure.

### Current application

- Static HTML/CSS/JavaScript frontend served by Nginx
- PHP APIs running on Apache
- AWS SDK for PHP
- RDS MySQL database
- Secrets Manager-based database credential retrieval

The application repository is:

```text
3tier-app-code
```

### Planned application evolution

The application will later be modernized to:

```text
React frontend
       ↓
Node.js backend
       ↓
MySQL / RDS
```

The infrastructure architecture can remain largely unchanged while the application evolves.

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
| [`initial-setup.md`](docs/initial-setup.md) | Local tools and first-time environment setup |

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
