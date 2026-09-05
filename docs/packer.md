# Packer Architecture

## 1. Overview

Packer is used to build immutable Amazon Machine Images (AMIs) for the frontend and backend EC2 instances.

The project keeps image creation separate from infrastructure provisioning:

```text
Packer → AMI → Terraform Launch Template → Auto Scaling Group → EC2
```

Two independent Packer configurations are maintained:

```text
packer/
├── frontend/
└── backend/
```

---

## 2. Why Packer Is Used

The EC2 instances are not configured from scratch during every application deployment. Instead, the required software and application components are installed into an AMI ahead of deployment.

This provides a consistent server image for every instance launched by the Auto Scaling Groups.

The approach also separates two responsibilities:

- **Packer** — creates the machine image.
- **Terraform** — provisions the infrastructure that runs the image.

---

## 3. Image Architecture

```text
                         Packer
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
      Frontend AMI               Backend AMI
              │                         │
              ▼                         ▼
   Frontend Launch Template   Backend Launch Template
              │                         │
              ▼                         ▼
      Frontend ASG               Backend ASG
              │                         │
              ▼                         ▼
      Frontend EC2               Backend EC2
```

---

## 4. Frontend AMI

Location:

```text
packer/frontend/
```

The frontend image prepares an Amazon Linux server with Nginx and the frontend application.

The image is configured with the backend Application Load Balancer DNS name so that Nginx can proxy `/api/` requests to the internal backend tier.

### Frontend image responsibilities

- Start from an Amazon Linux base AMI.
- Install and configure Nginx.
- Copy the frontend application into the web root.
- Configure Nginx as the web server.
- Configure `/api/` proxying to the backend ALB.
- Validate the Nginx configuration.
- Enable Nginx at system startup.
- Create the resulting frontend AMI.

The resulting image is consumed by the Terraform compute stack through:

```text
terraform/compute/ami_ids/frontend_ami.txt
```

---

## 5. Backend AMI

Location:

```text
packer/backend/
```

The backend image prepares an Amazon Linux server with Apache, PHP, the AWS SDK for PHP, and the backend application.

### Backend image responsibilities

- Start from an Amazon Linux base AMI.
- Install Apache HTTP Server.
- Install PHP and required PHP extensions.
- Install Composer.
- Clone the application repository.
- Install PHP dependencies with Composer.
- Copy the backend API into the Apache web root.
- Copy the Composer dependencies into the image.
- Configure file ownership and permissions.
- Enable Apache at system startup.
- Include the MariaDB/MySQL command-line client for database administration and testing.
- Remove build-time Git tooling after the application has been copied.
- Create the resulting backend AMI.

The resulting image is consumed by the Terraform compute stack through:

```text
terraform/compute/ami_ids/backend_ami.txt
```

The MariaDB/MySQL client is only a client utility on the backend instances. The database server itself is Amazon RDS for MySQL.

---

## 6. Packer Build Process

The build process follows this general sequence:

```text
1. Select base Amazon Linux AMI
             ↓
2. Launch temporary EC2 build instance
             ↓
3. Connect to temporary instance
             ↓
4. Install required packages
             ↓
5. Copy/build application components
             ↓
6. Configure services
             ↓
7. Validate configuration
             ↓
8. Create AMI snapshot
             ↓
9. Terminate temporary build instance
             ↓
10. Record AMI ID
```

The temporary build infrastructure is used only during image creation.

---

## 7. Frontend Build-Time Configuration

The frontend image requires the backend ALB DNS name because Nginx needs to know where `/api/` requests should be forwarded.

The build process obtains the backend ALB DNS name from the Terraform compute stack and passes it to Packer as a variable.

Conceptually:

```text
Terraform Compute
       │
       └── Backend ALB DNS name
                    │
                    ▼
              Packer variable
                    │
                    ▼
              Nginx config
                    │
                    ▼
          Frontend AMI
```

The resulting Nginx configuration forwards API requests to the internal backend ALB.

---

## 8. Backend Runtime Configuration

The backend image does not contain the database password.

Instead, Terraform provides the database secret ARN to the backend EC2 instances through launch-template user data.

At runtime:

```text
Backend EC2
    │
    │ DB_SECRET_ARN
    ▼
AWS Secrets Manager
    │
    │ database credentials
    ▼
PHP application
    │
    ▼
RDS MySQL
```

This keeps the database credentials outside the AMI.

The backend EC2 IAM role is granted `secretsmanager:GetSecretValue` access to the specific database secret.

---

## 9. Application Repository Integration

The backend Packer build retrieves application code from the separate application repository:

```text
3tier-app-code
```

This keeps application source code independent from the infrastructure repository.

The relationship is:

```text
Application Repository
        │
        │ source code
        ▼
      Packer
        │
        │ application image
        ▼
       AMI
        │
        ▼
     Terraform
        │
        ▼
       EC2
```

The infrastructure repository therefore orchestrates the infrastructure and image lifecycle without embedding the application source tree into the Terraform codebase.

---

## 10. Packer and Terraform Responsibilities

| Responsibility | Packer | Terraform |
|---|---|---|
| Build server image | Yes | No |
| Install OS packages | Yes | No |
| Install application dependencies | Yes | No |
| Configure Nginx/Apache | Yes | No |
| Create AMI | Yes | No |
| Create VPC | No | Yes |
| Create ALBs | No | Yes |
| Create security groups | No | Yes |
| Create Launch Templates | No | Yes |
| Create Auto Scaling Groups | No | Yes |
| Create RDS | No | Yes |
| Configure runtime secret ARN | No | Yes |

This separation keeps the machine-image lifecycle distinct from the infrastructure lifecycle.

---

## 11. AMI Handoff to Terraform

After an image build, the AMI ID is written to the corresponding file under:

```text
terraform/compute/ami_ids/
```

Terraform reads these files using the `local_file` data source.

The compute stack then uses the AMI IDs in its Launch Templates.

```text
Packer build
     │
     ▼
AMI ID
     │
     ▼
ami_ids/*.txt
     │
     ▼
Terraform local_file
     │
     ▼
Launch Template
     │
     ▼
Auto Scaling Group
```

The current implementation intentionally uses this simple handoff mechanism. A future CI/CD implementation can replace it with a more automated artifact or parameter-based AMI promotion mechanism.

---

## 12. Build Environment

Packer builds use AWS resources in the same AWS environment as the application infrastructure.

The build process uses:

- AWS region: `us-east-1`
- Amazon Linux base image
- Temporary EC2 build instance
- Temporary security group for image creation
- Temporary SSH access during the image build

The temporary build resources are removed after the image build completes.

---

## 13. Current Image Strategy

The project uses immutable image deployment:

```text
New application/server configuration
            ↓
       Build new AMI
            ↓
     Update AMI reference
            ↓
     Update Launch Template
            ↓
      Refresh ASG instances
```

Existing instances are therefore not manually configured as part of normal image rollout. New instances are launched from the selected AMI.

---

## 14. Security Considerations

The current image-building process is designed for the portfolio implementation and includes temporary build-time SSH access.

The AMIs themselves do not contain the runtime database password. Database credentials are retrieved from Secrets Manager at runtime.

Future hardening can include:

- Restricting temporary SSH access to the build environment.
- Using AWS Systems Manager instead of SSH where practical.
- Automated image vulnerability scanning.
- Image signing and provenance verification.
- Automated AMI cleanup and retention policies.
- Removing unnecessary packages from the final image.
- Integrating Packer validation and security checks into Jenkins.

These are future improvements and are not represented as existing capabilities in the current baseline.

---

## 15. Packer + Terraform Deployment Flow

The complete image-to-infrastructure flow is:

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
    AMI ID handoff
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

For the complete application request path, the deployed EC2 instances then participate in:

```text
Internet
   ↓
Frontend ALB
   ↓
Frontend EC2 / Nginx
   ↓
Backend ALB
   ↓
Backend EC2 / Apache / PHP
   ↓
AWS Secrets Manager
   ↓
RDS MySQL
```

---

## 16. Baseline Reference

The documented Packer architecture corresponds to the working project baseline tagged:

```text
baseline-v1.0
```

This document describes the current image-building design and does not include troubleshooting history or migration steps.