# Networking and Security

## 1. Overview

This document describes the networking model and security boundaries of the **3-tier AWS architecture baseline (`baseline-v1.0`)**.

The design separates the application into public, private application, and isolated database network zones. Communication between tiers is controlled using route tables and security groups.

**AWS Region:** `us-east-1`

---

## 2. Network Architecture

```text
                                  Internet
                                      |
                                      v
                              Internet Gateway
                                      |
                         +------------+------------+
                         |     Public Subnets      |
                         |                         |
                         |   Frontend ALB          |
                         |   NAT Gateway(s)        |
                         +------------+------------+
                                      |
                    +-----------------+-----------------+
                    |                                   |
                    v                                   v
          Private Web Subnets                 Private App Subnets
          +------------------+                +------------------+
          | Frontend EC2     |                | Backend ALB      |
          | Frontend ASG     |                | Backend EC2      |
          +------------------+                | Backend ASG      |
                    |                         +------------------+
                    |                                  |
                    +----------------------------------+
                                      |
                                      v
                             Database Subnets
                         +-----------------------+
                         | Amazon RDS MySQL      |
                         | No default internet   |
                         | route                 |
                         +-----------------------+
```

---

## 3. VPC

The baseline creates a dedicated Amazon VPC with the following characteristics:

- CIDR: `10.0.0.0/16`
- DNS hostnames enabled
- DNS support enabled
- Dedicated application network boundary

The VPC is divided into separate subnet groups for the web, application, and database tiers.

---

## 4. Subnet Design

The architecture uses four logical subnet categories.

### 4.1 Public Web Subnets

Public subnets have a route to the Internet Gateway.

They are used for:

- Internet-facing frontend Application Load Balancer
- NAT Gateways

The application EC2 instances are **not** placed directly in these public subnets.

### 4.2 Private Web Subnets

Private web subnets contain the frontend EC2 instances.

Characteristics:

- No direct route to the Internet Gateway
- Default outbound route through NAT Gateway
- EC2 instances do not receive public IP addresses
- Frontend instances receive inbound traffic only from the frontend ALB

### 4.3 Private Application Subnets

Private application subnets contain:

- Internal backend Application Load Balancer
- Backend EC2 instances

Characteristics:

- No direct inbound internet access
- Outbound internet access through NAT Gateway where required
- Backend instances do not receive public IP addresses
- Backend instances receive application traffic only through the internal backend ALB

### 4.4 Database Subnets

Database subnets contain the RDS database layer.

Characteristics:

- No default internet route
- No NAT route
- Not directly accessible from the internet
- Database traffic is restricted to the backend tier

This is the most isolated network zone in the architecture.

---

## 5. Route Table Design

The baseline uses separate routing behavior for public, private application, and database networks.

### Public Route Table

```text
Destination        Target
-----------        ------
0.0.0.0/0         Internet Gateway
```

This provides internet connectivity for resources that require a public subnet.

### Private Web Route Tables

```text
Destination        Target
-----------        ------
0.0.0.0/0         NAT Gateway
```

This allows frontend EC2 instances to initiate outbound internet connections without being directly reachable from the internet.

### Private App Route Tables

```text
Destination        Target
-----------        ------
0.0.0.0/0         NAT Gateway
```

This provides controlled outbound connectivity for backend EC2 instances.

### Database Route Tables

```text
No 0.0.0.0/0 route
```

The database subnet route tables intentionally do not provide an internet or NAT path.

---

## 6. NAT Gateway Design

NAT Gateways are deployed in the public subnets.

The purpose of the NAT layer is to allow instances in private subnets to initiate outbound connections while preventing unsolicited inbound internet connections to those instances.

```text
Private EC2
    |
    | outbound request
    v
NAT Gateway
    |
    v
Internet Gateway
    |
    v
Internet
```

The private web and application tiers use NAT Gateway routes for their default outbound traffic.

---

## 7. Security Group Architecture

Security groups form the primary application-level network boundary between tiers.

The baseline uses five security groups:

```text
SG-Frontend-ALB
SG-Frontend-EC2
SG-Backend-ALB
SG-Backend-EC2
SG-RDS
```

The intended trust chain is:

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

This is preferable to allowing broad CIDR-based access between application tiers because each tier trusts the specific preceding security boundary.

---

## 8. Security Group Rules

| Security Group | Protocol | Port | Source | Purpose |
|---|---|---:|---|---|
| Frontend ALB SG | TCP | 80 | `0.0.0.0/0` | Accept web traffic |
| Frontend EC2 SG | TCP | 80 | Frontend ALB SG | Serve frontend traffic |
| Backend ALB SG | TCP | 80 | Frontend EC2 SG | Accept API traffic from frontend |
| Backend EC2 SG | TCP | 80 | Backend ALB SG | Serve backend API traffic |
| RDS SG | TCP | 3306 | Backend EC2 SG | Accept MySQL connections |

All five security groups also have outbound traffic allowed in the baseline.

---

## 9. Frontend Security Boundary

The frontend ALB is the only component in the application path that accepts traffic directly from the internet.

```text
Internet
   |
   | TCP/80
   v
Frontend ALB
   |
   | TCP/80
   v
Frontend EC2
```

Frontend EC2 instances:

- Are located in private subnets
- Do not have public IP addresses
- Accept HTTP only from the frontend ALB security group
- Are not directly exposed to the internet

This creates a public entry point without making the application servers public.

---

## 10. Backend Security Boundary

The backend tier is protected by a second load-balancing boundary.

```text
Frontend EC2
     |
     | TCP/80
     v
Internal Backend ALB
     |
     | TCP/80
     v
Backend EC2
```

The backend ALB is internal and therefore does not provide a public internet endpoint.

Backend EC2 instances accept traffic only from the backend ALB security group.

---

## 11. Database Security Boundary

The database is the final and most restricted application boundary.

```text
Backend EC2
     |
     | TCP/3306
     v
RDS MySQL
```

The RDS security group allows MySQL traffic only from the backend EC2 security group.

There is no direct path from:

- Internet → RDS
- Frontend EC2 → RDS
- Frontend ALB → RDS
- Backend ALB → RDS

The backend application tier is the only application tier authorized to establish database connections.

---

## 12. End-to-End Traffic Flow

### User request

```text
1. User
      |
      | HTTP :80
      v
2. Public Frontend ALB
      |
      | HTTP :80
      v
3. Frontend EC2 / Nginx
      |
      | API request HTTP :80
      v
4. Internal Backend ALB
      |
      | HTTP :80
      v
5. Backend EC2 / Apache + PHP
      |
      | MySQL :3306
      v
6. RDS MySQL
```

### Return path

The response travels back through the established connection path:

```text
RDS
  ↓
Backend EC2
  ↓
Backend ALB
  ↓
Frontend EC2
  ↓
Frontend ALB
  ↓
User
```

---

## 13. Outbound Traffic Flow

Private application instances may require outbound connectivity for operating-system updates and other permitted external services.

The baseline provides this through NAT Gateways:

```text
Private Web EC2
       |
       +-----> NAT Gateway -----> Internet Gateway -----> Internet

Private App EC2
       |
       +-----> NAT Gateway -----> Internet Gateway -----> Internet
```

The database tier does not use this path because its subnet route tables have no default NAT route.

---

## 14. Security Design Principles

The baseline follows these principles:

### No public application servers

Frontend and backend EC2 instances are placed in private subnets and do not receive public IP addresses.

### Layered network boundaries

Each application tier has a separate security group and controlled ingress path.

### Least-path connectivity

Only the required application ports are opened between tiers:

- HTTP `80` for frontend traffic
- HTTP `80` for backend traffic
- MySQL `3306` for database traffic

### Isolated database tier

The database subnet has no default internet route, and RDS is not publicly accessible.

### Internal backend service

The backend ALB is internal and is not directly reachable from the internet.

### IAM-based AWS access

EC2 instances use IAM instance profiles rather than embedded AWS credentials. The backend role additionally has permission to retrieve the database secret from Secrets Manager.

---

## 15. Current Baseline vs Future Hardening

This document describes the current `baseline-v1.0` implementation.

The following are intentionally outside the current baseline and can be introduced in later DevSecOps phases:

- HTTPS/TLS listeners and certificates
- AWS WAF
- Network ACL hardening
- VPC endpoints for selected AWS services
- Centralized logging and flow logs
- More restrictive egress rules
- Dedicated NAT architecture refinements
- Secrets rotation improvements
- Automated security scanning

These should be treated as future enhancements rather than undocumented assumptions about the current implementation.

---

## 16. Baseline Reference

**Baseline:** `baseline-v1.0`

**AWS Region:** `us-east-1`

The networking and security model documented here represents the frozen architecture that will serve as the foundation for the subsequent Jenkins and DevSecOps phases.
