# IAM and Secrets Architecture

## 1. Overview

IAM and AWS Secrets Manager provide the identity and credential-management layer for the three-tier application.

The current design follows a simple principle:

```text
EC2 Instance Role
       │
       ▼
AWS permissions
       │
       ▼
Application accesses only the AWS service it requires
```

Database credentials are stored in AWS Secrets Manager and retrieved by the backend application at runtime.

---

## 2. IAM Architecture

The compute stack creates separate IAM roles for the frontend and backend EC2 instances.

```text
                EC2
                 │
        ┌────────┴────────┐
        │                 │
        ▼                 ▼
 Frontend EC2        Backend EC2
        │                 │
        ▼                 ▼
Frontend IAM Role    Backend IAM Role
        │                 │
        ▼                 ├── Systems Manager
 Amazon SSM Managed   └── Secrets Manager
 Instance Core
```

The roles are attached to the EC2 instances through IAM instance profiles.

---

## 3. Frontend IAM Role

The frontend role is:

```text
${project_name}-frontend-ec2-role
```

The role trusts the EC2 service so that EC2 instances can assume the role.

The role currently has the AWS managed policy:

```text
AmazonSSMManagedInstanceCore
```

This allows the frontend instances to be managed through AWS Systems Manager.

The frontend role does not have permission to retrieve the database secret.

---

## 4. Backend IAM Role

The backend role is:

```text
${project_name}-backend-ec2-role
```

Like the frontend role, it can be assumed by EC2 and has:

```text
AmazonSSMManagedInstanceCore
```

The backend role also has a project-specific inline policy that grants:

```text
secretsmanager:GetSecretValue
```

The resource is restricted to the database secret ARN obtained from the database Terraform state.

This creates the following boundary:

```text
Backend EC2 Role
      │
      └── GetSecretValue
              │
              ▼
       Specific DB Secret
```

The backend application therefore does not need AWS access keys stored on the server.

---

## 5. IAM Instance Profiles

EC2 uses IAM instance profiles to make the IAM roles available to running instances.

The project creates:

```text
Frontend EC2 Role
      ↓
Frontend Instance Profile
      ↓
Frontend EC2
```

and:

```text
Backend EC2 Role
      ↓
Backend Instance Profile
      ↓
Backend EC2
```

Terraform associates the corresponding instance profile with each Launch Template.

---

## 6. Secrets Manager

Database credentials are stored in AWS Secrets Manager.

The secret name follows the project/environment convention:

```text
${project_name}/${environment}/database
```

The secret value contains the database connection information required by the backend application:

```text
engine
host
port
dbname
username
password
```

The database host and port point to the private RDS MySQL instance.

---

## 7. Secret Creation

The database Terraform stack creates the secret and its version.

The current implementation generates the database password with Terraform's `random_password` resource and stores the resulting connection information in the secret.

Conceptually:

```text
Terraform Database Stack
          │
          ├── Generate password
          │
          ├── Create RDS
          │
          └── Create Secrets Manager secret
                    │
                    ▼
              DB credentials
```

The secret is then exposed from the database stack as:

```text
db_secret_arn
```

---

## 8. Secret Consumption by Backend

The compute stack reads the database secret ARN from the database remote state.

Terraform passes the ARN into the backend Launch Template user data.

The runtime flow is:

```text
Database Terraform
       │
       │ db_secret_arn
       ▼
Compute Terraform
       │
       │ DB_SECRET_ARN
       ▼
Backend EC2
       │
       ▼
PHP application
       │
       │ GetSecretValue
       ▼
Secrets Manager
       │
       │ credentials
       ▼
PDO / MySQL
       │
       ▼
RDS MySQL
```

The application reads `DB_SECRET_ARN` from its environment rather than embedding the secret ARN or password in application source code.

---

## 9. Application Access Pattern

The database connection code uses the AWS SDK for PHP to retrieve the secret.

The application flow is:

```text
getDatabaseConnection()
        │
        ▼
Read DB_SECRET_ARN
        │
        ▼
Create Secrets Manager client
        │
        ▼
GetSecretValue
        │
        ▼
Parse secret
        │
        ▼
Create PDO connection
        │
        ▼
RDS MySQL
```

No static AWS access key is required by the PHP application because AWS authentication is provided through the backend EC2 IAM role.

---

## 10. Least-Privilege Boundary

The current IAM design applies a basic least-privilege boundary at the application level.

### Frontend

```text
Frontend EC2
    │
    └── Systems Manager access
```

### Backend

```text
Backend EC2
    │
    ├── Systems Manager access
    │
    └── GetSecretValue → specific database secret
```

The backend role is not granted broad Secrets Manager access across all secrets.

---

## 11. Secrets Are Not Stored in the AMI

The backend AMI contains the application and its dependencies, but not the database password.

The AMI contains the application code and AWS SDK dependencies needed to retrieve the secret at runtime.

```text
Backend AMI
   │
   ├── PHP application
   ├── Composer dependencies
   └── AWS SDK for PHP

   No database password
```

At runtime, the application obtains the credentials from Secrets Manager using the EC2 role.

---

## 12. Terraform State Consideration

The current database implementation generates the password with Terraform and uses it when creating the RDS instance and Secrets Manager secret.

As a result, sensitive credential material can exist in Terraform state even though the application itself retrieves the password from Secrets Manager at runtime.

This is an important limitation of the current implementation.

A future production hardening step is to use an RDS-managed master password/secret approach and minimize secret material handled directly by Terraform state.

---

## 13. Current Security Model

The current security model can be summarized as:

```text
Internet
   │
   ▼
Frontend ALB
   │
   ▼
Frontend EC2
   │
   │ IAM role
   ▼
Backend ALB
   │
   ▼
Backend EC2
   │
   │ IAM role
   ├──────────► Secrets Manager
   │
   ▼
RDS MySQL
```

Network-level access is controlled separately through security groups. IAM controls AWS API access, while Secrets Manager stores database credentials.

---

## 14. Future IAM and Secrets Hardening

Future improvements may include:

- Use RDS-managed master credentials with Secrets Manager.
- Reduce sensitive values exposed to Terraform state.
- Add customer-managed KMS encryption where appropriate.
- Further restrict IAM permissions by action and resource.
- Add IAM policy validation and security scanning to CI/CD.
- Add rotation of database credentials.
- Introduce separate IAM roles and secrets for different environments.
- Replace temporary build-time SSH access with a more controlled image-building mechanism.

These are future improvements and are not represented as existing capabilities in the current baseline.

---

## 15. Baseline Reference

The documented IAM and secrets architecture corresponds to the working project baseline tagged:

```text
baseline-v1.0
```

This document describes the current IAM and Secrets Manager design and does not include troubleshooting history or migration steps.