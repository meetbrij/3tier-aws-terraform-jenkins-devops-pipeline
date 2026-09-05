# AWS Resource Inventory

## 1. Overview

This document provides the AWS resource inventory for the **3-tier AWS architecture baseline (`baseline-v1.0`)**.

The infrastructure is deployed in **AWS `us-east-1`** and is managed through three Terraform stacks:

```text
terraform/
├── network/
├── database/
└── compute/
```

The inventory below describes the resources represented by the baseline configuration. Resource IDs and endpoints are intentionally not treated as permanent documentation values because Terraform may recreate resources during future deployments.

---

## 2. Resource Summary

| Layer | AWS Service | Resource | Purpose |
|---|---|---|---|
| Network | Amazon VPC | VPC | Provides isolated network boundary |
| Network | Internet Gateway | IGW | Internet connectivity for public subnets |
| Network | Elastic IP | NAT EIP(s) | Public IPs assigned to NAT Gateways |
| Network | NAT Gateway | NAT Gateway(s) | Outbound internet access for private application tiers |
| Network | Subnets | Public web subnets | Host the public frontend ALB |
| Network | Subnets | Private web subnets | Host frontend EC2 instances |
| Network | Subnets | Private app subnets | Host backend ALB and backend EC2 instances |
| Network | Subnets | Database subnets | Isolate RDS |
| Network | Route Tables | Public/private/database RTs | Control subnet routing |
| Network | Security Groups | 5 security groups | Enforce tier-to-tier traffic boundaries |
| Compute | Application Load Balancer | Frontend ALB | Public entry point |
| Compute | Application Load Balancer | Backend ALB | Internal application routing |
| Compute | Target Groups | Frontend target group | Routes traffic to frontend instances |
| Compute | Target Groups | Backend target group | Routes traffic to backend instances |
| Compute | Launch Templates | Frontend launch template | Defines frontend EC2 configuration |
| Compute | Launch Templates | Backend launch template | Defines backend EC2 configuration |
| Compute | Auto Scaling | Frontend ASG | Runs and scales frontend instances |
| Compute | Auto Scaling | Backend ASG | Runs and scales backend instances |
| Compute | IAM | Frontend EC2 role/profile | Instance identity and SSM access |
| Compute | IAM | Backend EC2 role/profile | Instance identity, SSM and Secrets Manager access |
| Database | Amazon RDS | MySQL instance | Persistent application database |
| Database | RDS | DB subnet group | Places RDS in database subnets |
| Database | Secrets Manager | Database secret | Stores runtime database credentials |
| Operations | Amazon S3 | Terraform state bucket | Remote Terraform state |

---

## 3. Network Resources

### 3.1 Amazon VPC

The network stack creates a single VPC with a default CIDR of `10.0.0.0/16`. DNS hostnames and DNS support are enabled.

The VPC is the primary network isolation boundary for the application.

### 3.2 Subnets

The VPC is divided into four subnet categories:

```text
VPC
│
├── Public Web Subnets
│     └── Frontend ALB
│
├── Private Web Subnets
│     └── Frontend EC2 / ASG
│
├── Private App Subnets
│     ├── Backend ALB
│     └── Backend EC2 / ASG
│
└── Database Subnets
      └── RDS MySQL
```

The subnet definitions are supplied as lists of CIDR blocks and Availability Zones through Terraform variables.

### 3.3 Internet Gateway

An Internet Gateway is attached to the VPC and is used by the public route table for internet-bound traffic.

### 3.4 NAT Gateways

NAT Gateways are deployed in the public web subnets. Each NAT Gateway receives an Elastic IP and provides outbound internet access for private web and application subnets.

The private web and application route tables use the corresponding NAT Gateway as their default route.

### 3.5 Database Routing

Database route tables do not define a default `0.0.0.0/0` route. The database subnets therefore do not have a direct internet or NAT route.

---

## 4. Security Groups

The baseline contains five primary security groups.

| Security Group | Allows | Source |
|---|---|---|
| Frontend ALB SG | TCP/80 | Internet |
| Frontend EC2 SG | TCP/80 | Frontend ALB SG |
| Backend ALB SG | TCP/80 | Frontend EC2 SG |
| Backend EC2 SG | TCP/80 | Backend ALB SG |
| RDS SG | TCP/3306 | Backend EC2 SG |

This creates the following controlled communication chain:

```text
Internet
   ↓ TCP/80
Frontend ALB
   ↓ TCP/80
Frontend EC2
   ↓ TCP/80
Backend ALB
   ↓ TCP/80
Backend EC2
   ↓ TCP/3306
RDS MySQL
```

The security-group configuration is defined in the network stack.

---

## 5. Load Balancing Resources

### Frontend ALB

The frontend Application Load Balancer is:

- Internet-facing
- Deployed in public subnets
- Listening on HTTP port 80
- Associated with the frontend ALB security group
- Connected to the frontend target group

### Backend ALB

The backend Application Load Balancer is:

- Internal
- Deployed in application private subnets
- Listening on HTTP port 80
- Associated with the backend ALB security group
- Connected to the backend target group

### Target Groups

Both ALBs use HTTP target groups on port 80 with health checks enabled. The baseline health checks use `/` and expect HTTP status `200`.

---

## 6. Compute Resources

### Frontend Auto Scaling Group

The frontend ASG runs EC2 instances in the private web subnets.

Instances are launched using a dedicated launch template containing:

- Frontend AMI
- EC2 instance type
- Frontend security group
- Frontend IAM instance profile
- No public IP address
- Frontend initialization/user-data configuration

The ASG registers instances with the frontend target group.

### Backend Auto Scaling Group

The backend ASG runs EC2 instances in the private application subnets.

Instances are launched using a dedicated launch template containing:

- Backend AMI
- EC2 instance type
- Backend security group
- Backend IAM instance profile
- No public IP address
- Database secret ARN and AWS region supplied through user data

The ASG registers instances with the backend target group.

---

## 7. Database Resources

### Amazon RDS for MySQL

The database tier uses Amazon RDS for MySQL.

Baseline configuration includes:

- Engine: MySQL
- Database name: `appdb`
- Master username: `admin`
- Port: `3306`
- Instance class: `db.t3.micro`
- Allocated storage: `20 GB`
- Storage type: `gp2`
- Backup retention: 7 days
- Public accessibility: disabled by the deployed baseline design

The database is associated with the RDS security group and a DB subnet group containing the database subnets.

### DB Subnet Group

The RDS subnet group uses the database subnet IDs exported by the network Terraform stack.

---

## 8. Secrets Manager

The database credentials are stored in AWS Secrets Manager.

The secret contains the database connection information required by the backend application, including:

- Engine
- Host
- Port
- Database name
- Username
- Password

The backend EC2 IAM role is granted `secretsmanager:GetSecretValue` against the database secret.

The backend application retrieves this information at runtime rather than storing database credentials in application source code.

---

## 9. IAM Resources

The compute stack creates separate IAM roles and instance profiles for the frontend and backend EC2 tiers.

### Frontend

The frontend role has:

- EC2 trust relationship
- `AmazonSSMManagedInstanceCore`

### Backend

The backend role has:

- EC2 trust relationship
- `AmazonSSMManagedInstanceCore`
- Restricted `secretsmanager:GetSecretValue` access to the database secret

The separate roles provide a distinct IAM identity for each application tier.

---

## 10. Amazon S3 Terraform State

Terraform state is stored remotely in an Amazon S3 bucket.

The baseline uses separate state keys:

```text
network/terraform.tfstate
database/terraform.tfstate
compute/terraform.tfstate
```

The S3 state bucket is a shared infrastructure dependency and should remain available when individual application stacks are destroyed and recreated.

---

## 11. Resource Dependency View

```text
                         S3
                   Terraform State
                         |
                         v
                      Network
                         |
              +----------+----------+
              |                     |
              v                     v
           Database              Compute
              |                     |
              |          +----------+----------+
              |          |                     |
              v          v                     v
          RDS + Secret  Frontend            Backend
                         ALB/ASG             ALB/ASG
```

More specifically:

```text
Network
├── VPC
├── Subnets
├── Routes
├── NAT Gateways
├── Internet Gateway
└── Security Groups
       │
       ├───────────────> Database
       │                    ├── DB Subnet Group
       │                    ├── RDS MySQL
       │                    └── Secrets Manager Secret
       │
       └───────────────> Compute
                            ├── Frontend ALB
                            ├── Frontend ASG
                            ├── Backend ALB
                            ├── Backend ASG
                            └── IAM Roles / Instance Profiles
```

---

## 12. Baseline Reference

**Baseline:** `baseline-v1.0`

**AWS Region:** `us-east-1`

This document is an inventory of the resources defined by the baseline Terraform configuration. Exact AWS resource IDs, IP addresses, DNS names, and generated identifiers may change when resources are recreated and should therefore be obtained from Terraform outputs or the AWS console rather than treated as permanent architecture identifiers.
