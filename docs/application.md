# Application Architecture

## 1. Overview

The project is a simple three-tier web application used to demonstrate a production-style AWS infrastructure and DevOps workflow.

The application is maintained in a separate repository from the infrastructure code:

```text
3tier-app-code
```

The current application stack is:

- **Frontend:** HTML, CSS and JavaScript served by Nginx
- **Backend:** PHP REST-style APIs served by Apache HTTP Server
- **Database:** MySQL on Amazon RDS
- **Secrets:** AWS Secrets Manager
- **AWS SDK:** AWS SDK for PHP for runtime access to Secrets Manager

---

## 2. Application Architecture

```text
                    Internet
                       │
                       ▼
              Frontend Application
                  Load Balancer
                       │
                       ▼
              Frontend EC2 / Nginx
                       │
                 /api/ requests
                       │
                       ▼
               Internal Backend
                  Load Balancer
                       │
                       ▼
              Backend EC2 / Apache
                       │
                       ▼
                  PHP APIs
                       │
                       ├──────────────► Secrets Manager
                       │                      │
                       │                      ▼
                       │               DB credentials
                       │
                       ▼
                  RDS MySQL
```

The frontend and backend EC2 instances run in private subnets. The public frontend ALB is the internet-facing entry point.

---

## 3. Frontend

Location in the application repository:

```text
frontend/
```

The frontend is a lightweight static web application consisting of HTML, CSS and JavaScript.

Nginx serves the static content and also acts as the reverse proxy for backend API requests.

The Nginx configuration routes:

```text
/api/* → Internal Backend ALB
```

Other requests are served by the frontend application.

This allows the browser to communicate through the same public frontend endpoint while keeping the backend tier private.

---

## 4. Backend

Location in the application repository:

```text
backend/api/
```

The backend consists of PHP APIs running on Apache HTTP Server.

Current API responsibilities include:

- Reading messages from the database
- Saving new messages to the database
- Establishing database connections

The backend is deployed to multiple EC2 instances behind an internal Application Load Balancer.

---

## 5. Backend API Flow

The application request path is:

```text
Browser
   │
   ▼
Frontend ALB
   │
   ▼
Nginx
   │
   │ /api/
   ▼
Backend ALB
   │
   ▼
Apache / PHP
   │
   ▼
Database connection
   │
   ▼
RDS MySQL
```

The internal backend ALB provides a stable endpoint for the frontend tier while allowing the backend EC2 instances to scale independently.

---

## 6. Database

The database layer uses Amazon RDS for MySQL.

Current database configuration includes:

- Database engine: MySQL
- Database name: `appdb`
- Database port: `3306`
- Master username: `admin`
- RDS instance class: `db.t3.micro`
- Allocated storage: 20 GB

The database is deployed in dedicated database subnets and is not publicly accessible.

The application connects to RDS through the backend tier.

---

## 7. Database Schema

The current application uses a simple `messages` table for demonstrating database connectivity.

The database initialization script is maintained in:

```text
database/database_setup.sql
```

The current application demonstrates two core operations:

```text
GET  → retrieve messages
POST → save a message
```

The database layer is intentionally simple because the primary purpose of this project is to demonstrate the AWS architecture and DevOps workflow.

---

## 8. Database Credentials and Secrets Manager

Database connection information is stored in AWS Secrets Manager rather than directly in the application source code.

The backend receives the secret ARN as a runtime environment variable:

```text
DB_SECRET_ARN
```

The PHP application uses the AWS SDK for PHP to retrieve the secret at runtime.

The secret contains the database connection information required by the application, including:

- Engine
- Host
- Port
- Database name
- Username
- Password

The database password is therefore not embedded in the application source code or AMI.

---

## 9. Backend Database Connection

The database connection logic is located in:

```text
backend/api/db_connection.php
```

The application:

1. Reads `DB_SECRET_ARN` from the environment.
2. Creates an AWS Secrets Manager client.
3. Retrieves the secret using the EC2 instance role.
4. Parses the secret JSON.
5. Builds a MySQL PDO connection.
6. Uses exception-based error handling.

The connection uses PDO with:

- Exception error mode
- Associative default fetch mode
- Native prepared statements

This keeps the database connection implementation centralized for the backend APIs.

---

## 10. PHP Dependencies

The backend uses Composer for dependency management.

The application repository contains:

```text
composer.json
composer.lock
```

The AWS SDK for PHP is included as an application dependency.

During the backend Packer build:

```text
composer install --no-dev --optimize-autoloader
```

is executed and the resulting `vendor` directory is included in the backend AMI.

The runtime image therefore contains the application dependencies required by the PHP APIs.

---

## 11. Application Repository Structure

The current application repository follows this structure:

```text
3tier-app-code/
├── backend/
│   └── api/
│       ├── db_connection.php
│       ├── get_messages.php
│       └── save_message.php
│
├── database/
│   └── database_setup.sql
│
├── frontend/
│   ├── index.html
│   └── styles.css
│
├── infrastructure/
│   ├── backend_server.md
│   ├── frontend_server.md
│   └── nginx_config
│
├── composer.json
├── composer.lock
└── README.md
```

The infrastructure repository remains separate:

```text
3tier-aws-terraform-jenkins-devops-pipeline
```

---

## 12. Application-to-Infrastructure Relationship

The two repositories have clearly separated responsibilities.

### Application repository

Contains:

- Application source code
- Frontend assets
- Backend APIs
- Database initialization script
- PHP dependencies
- Application-specific configuration

### Infrastructure repository

Contains:

- Terraform infrastructure
- Packer image definitions
- Jenkins automation
- Infrastructure documentation

The relationship is:

```text
Application Repository
          │
          ▼
        Packer
          │
          ▼
         AMIs
          │
          ▼
       Terraform
          │
          ▼
         EC2
```

---

## 13. Runtime Configuration

The application separates build-time configuration from runtime configuration.

### Frontend

The backend ALB DNS name is injected during the frontend AMI build and becomes part of the Nginx configuration.

### Backend

The database secret ARN is injected by Terraform into the backend EC2 Launch Template user data.

```text
Terraform
   │
   └── DB_SECRET_ARN
           │
           ▼
      Backend EC2
           │
           ▼
      PHP application
           │
           ▼
   Secrets Manager
```

The actual database password remains in Secrets Manager rather than in the AMI.

---

## 14. Current Application Deployment Model

The current deployment model is image-based.

```text
Application source
       ↓
Packer image build
       ↓
New AMI
       ↓
Terraform Launch Template
       ↓
Auto Scaling Group
       ↓
EC2 instances
```

The frontend and backend tiers are deployed independently through their respective AMIs and Auto Scaling Groups.

---

## 15. Current Application Capabilities

The current application provides a small message-management demonstration.

Users can:

- Open the frontend UI through the public ALB.
- View messages stored in MySQL.
- Add a new message.
- Have the request travel through the frontend and backend tiers before reaching RDS.

This provides a simple end-to-end demonstration of the three-tier architecture.

---

## 16. Future Application Evolution

The current application is intentionally simple. A future phase of the portfolio project is planned to evolve it into a more realistic Contact Book application.

The planned technology direction is:

```text
Current                    Future
------------------------------------------------
HTML/CSS/JS          →     React.js
PHP                  →     Node.js APIs
messages table       →     contacts table
```

The underlying AWS three-tier architecture can remain largely unchanged while the application technology evolves.

This future application evolution is not part of the current baseline.

---

## 17. Baseline Reference

The documented application architecture corresponds to the working project baseline tagged:

```text
baseline-v1.0
```

This document describes the current application design and does not include troubleshooting history or migration steps.