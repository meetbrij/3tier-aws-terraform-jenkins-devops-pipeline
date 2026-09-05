# 3-Tier AWS Architecture

## 1. Overview

This project implements a secure, highly available 3-tier web application architecture on AWS using Terraform and Packer.

The application is separated into three logical tiers:

- **Presentation tier** — Nginx-based frontend served from EC2 instances.
- **Application tier** — PHP backend APIs served from Apache/PHP EC2 instances.
- **Database tier** — Amazon RDS for MySQL.

The infrastructure is designed around private application workloads, load balancing, Auto Scaling, isolated database subnets, and controlled security-group-to-security-group communication.

This document describes the **frozen baseline architecture represented by `baseline-v1.0`**.

---

## 2. Architecture

```text
                              Internet
                                  |
                                  v
                    +---------------------------+
                    |   Public Frontend ALB     |
                    |        HTTP :80           |
                    +-------------+-------------+
                                  |
                                  v
              +-------------------------------------------+
              |       Web Private Subnets                |
              |                                           |
              |   +----------------+  +----------------+  |
              |   | Frontend EC2   |  | Frontend EC2   |  |
              |   | Nginx           |  | Nginx          |  |
              |   +----------------+  +----------------+  |
              |            Frontend Auto Scaling Group    |
              +----------------------+--------------------+
                                     |
                                     | HTTP :80
                                     v
                    +---------------------------+
                    | Internal Backend ALB      |
                    |        HTTP :80           |
                    +-------------+-------------+
                                  |
                                  v
              +-------------------------------------------+
              |       App Private Subnets                 |
              |                                           |
              |   +----------------+  +----------------+  |
              |   | Backend EC2    |  | Backend EC2    |  |
              |   | Apache + PHP   |  | Apache + PHP   |  |
              |   +----------------+  +----------------+  |
              |            Backend Auto Scaling Group     |
              +----------------------+--------------------+
                                     |
                                     | MySQL :3306
                                     v
              +-------------------------------------------+
              |          Database Subnets                 |
              |                                           |
              |              Amazon RDS                    |
              |               MySQL                       |
              +-------------------------------------------+
```

---

## 3. AWS Architecture Components

### Network layer

The network stack creates:

- One VPC
- Public web subnets across Availability Zones
- Private web subnets across Availability Zones
- Private application subnets across Availability Zones
- Isolated database subnets across Availability Zones
- Internet Gateway
- NAT Gateways
- Elastic IPs for NAT Gateways
- Route tables and subnet associations
- Security groups for each major application boundary

The database route tables intentionally do not contain a default internet route. Database subnets therefore remain isolated from direct internet access.

### Load balancing layer

Two Application Load Balancers are used:

1. **Public Frontend ALB**
   - Internet-facing
   - HTTP on port 80
   - Deployed in public subnets
   - Routes traffic to the frontend target group

2. **Internal Backend ALB**
   - Internal-only
   - HTTP on port 80
   - Deployed in application private subnets
   - Receives traffic only from the frontend tier
   - Routes traffic to the backend target group

### Compute layer

The compute stack contains two Auto Scaling Groups:

- **Frontend ASG** — EC2 instances running Nginx and the frontend application.
- **Backend ASG** — EC2 instances running Apache, PHP, the AWS SDK for PHP, and the backend API.

Both workloads run without public IP addresses and use IAM instance profiles for AWS access.

### Database layer

Amazon RDS for MySQL provides the persistent database layer.

The RDS instance:

- Runs in the database subnet group.
- Is not publicly accessible.
- Accepts MySQL traffic only from the backend security group.
- Uses seven days of backup retention in the baseline.

The application database is `appdb`.

---

## 4. Request Flow

A normal user request follows this path:

```text
User
  |
  | HTTP :80
  v
Public Frontend ALB
  |
  | HTTP :80
  v
Frontend EC2 / Nginx
  |
  | /api/* requests
  | HTTP :80
  v
Internal Backend ALB
  |
  | HTTP :80
  v
Backend EC2 / Apache + PHP
  |
  | MySQL :3306
  v
Amazon RDS MySQL
```

The frontend tier is therefore the only application tier directly exposed through the public load balancer. The backend tier is reachable through the internal load balancer, and the database is reachable only from backend instances.

---

## 5. High Availability Design

High availability is achieved by distributing the major application components across multiple Availability Zones.

### Frontend

The frontend Auto Scaling Group spans the private web subnets and maintains multiple instances behind the public ALB.

### Backend

The backend Auto Scaling Group spans the private application subnets and maintains multiple instances behind the internal ALB.

### Load balancers

Both ALBs use target groups with HTTP health checks. Unhealthy targets can therefore be removed from traffic while healthy targets continue serving requests.

### Database

The RDS subnet group spans multiple database subnets/Availability Zones, providing the required network placement for the managed database service.

---

## 6. Security Boundaries

The architecture uses security groups to enforce tier-to-tier communication.

```text
Internet
   |
   | TCP/80
   v
Frontend ALB SG
   |
   | TCP/80
   v
Frontend EC2 SG
   |
   | TCP/80
   v
Backend ALB SG
   |
   | TCP/80
   v
Backend EC2 SG
   |
   | TCP/3306
   v
RDS SG
```

The security groups allow traffic only from the preceding application boundary for the required application port.

Database access is therefore not exposed to the internet or directly to the frontend tier.

---

## 7. Infrastructure as Code

Terraform is separated into three independent stacks:

```text
terraform/
├── network/
├── database/
└── compute/
```

The dependency flow is:

```text
Network
   |
   +------> Database
   |
   +------> Compute
              ^
              |
           Database
```

Terraform remote state stored in Amazon S3 allows the database and compute stacks to consume outputs from the network and database stacks.

The stacks use separate state keys:

- `network/terraform.tfstate`
- `database/terraform.tfstate`
- `compute/terraform.tfstate`

---

## 8. Machine Images with Packer

Packer is used to create immutable EC2 machine images for the application tiers.

```text
Packer
  |
  +--> Frontend AMI
  |       |
  |       +--> Nginx + frontend application
  |
  +--> Backend AMI
          |
          +--> Apache + PHP + AWS SDK + backend application
```

Terraform then uses the generated AMI IDs in the EC2 launch templates used by the Auto Scaling Groups.

This separates **image creation** from **infrastructure provisioning**.

---

## 9. Secrets and IAM

The backend application retrieves database credentials from AWS Secrets Manager at runtime.

The backend EC2 instances use an IAM instance profile with:

- `AmazonSSMManagedInstanceCore` for Systems Manager access.
- Permission to call `secretsmanager:GetSecretValue` for the application's database secret.

No database password is embedded in the application source code.

The frontend instances use an IAM instance profile primarily for Systems Manager access.

---

## 10. State Management

Terraform state is stored remotely in an Amazon S3 bucket.

The baseline uses separate state files for the three Terraform stacks, allowing each stack to have an independent lifecycle while sharing required outputs through Terraform remote state.

The S3 state bucket is not part of the normal application infrastructure destruction lifecycle and is intended to remain available for future Terraform operations.

---

## 11. Application Stack

The baseline application consists of:

| Tier | Technology | Purpose |
|---|---|---|
| Frontend | HTML, CSS, JavaScript, Nginx | User interface |
| Backend | PHP, Apache | REST-style API endpoints |
| Database | Amazon RDS MySQL | Persistent data |
| AWS integration | AWS SDK for PHP | Runtime access to Secrets Manager |

The application currently provides a simple message-based demonstration of the 3-tier architecture.

---

## 12. Baseline Technology Stack

| Area | Technology |
|---|---|
| Cloud | AWS |
| Infrastructure as Code | Terraform |
| Image building | Packer |
| Compute | Amazon EC2 |
| Scaling | EC2 Auto Scaling Groups |
| Load balancing | Application Load Balancer |
| Database | Amazon RDS for MySQL |
| Secrets | AWS Secrets Manager |
| Instance management | AWS Systems Manager |
| State storage | Amazon S3 |
| Web server | Nginx |
| Application server | Apache + PHP |
| Networking | Amazon VPC |

---

## 13. Baseline Reference

**Baseline version:** `baseline-v1.0`

This version represents the known-good infrastructure and application architecture before introducing the Jenkins CI/CD and DevSecOps automation layers.

Future changes should build on this baseline without modifying the documented architecture retrospectively. New capabilities such as Jenkins, security scanning, and application modernization should be documented as subsequent project phases.
