# Jenkins CI/CD Pipeline

Jenkins is used as the automation and orchestration layer for deploying the 3-tier AWS infrastructure.

The pipeline integrates GitHub, Terraform, Packer, and AWS to automate infrastructure provisioning and immutable application image creation.

---

## 1. Jenkins Architecture

The Jenkins server runs on a dedicated EC2 instance and orchestrates the deployment workflow.

```text
                         GitHub
                           │
                           │ SSH
                           ▼
                    ┌─────────────┐
                    │   Jenkins   │
                    │    EC2      │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
              ▼            ▼            ▼
          Terraform      Packer      AWS CLI
              │            │            │
              └────────────┼────────────┘
                           ▼
                      AWS Resources
```

Jenkins does not directly replace Terraform or Packer.
Instead:
- Jenkins orchestrates the workflow
- Terraform provisions AWS infrastructure
- Packer creates immutable application AMIs
- AWS CLI is used for AWS discovery and supporting automation
- GitHub stores the infrastructure source code

## 2. Jenkins Responsibilities
The Jenkins pipeline is responsible for:
- Checking out infrastructure code from GitHub
- Validating required tools
- Authenticating to AWS using an IAM role
- Provisioning the network infrastructure
- Provisioning the database infrastructure
- Building the backend AMI using Packer
- Creating the initial compute infrastructure
- Discovering the backend Application Load Balancer
- Building the frontend AMI using Packer
- Deploying the final compute infrastructure using Terraform
- Managing Terraform remote state through Amazon S3
- Performing deployment verification

## 3. Pipeline Flow
The overall pipeline follows this sequence:

```text
GitHub
   │
   ▼
Checkout
   │
   ▼
Validate Tools
   │
   ▼
Terraform → Network
   │
   ▼
Terraform → Database
   │
   ▼
Discover AWS Configuration
   │
   ▼
Discover Source AMI
   │
   ▼
Packer → Backend AMI
   │
   ▼
Terraform → Bootstrap Compute
   │
   ▼
Discover Backend ALB
   │
   ▼
Packer → Frontend AMI
   │
   ▼
Terraform → Final Compute Deployment
   │
   ▼
Deployment Verification
```

## 4. Jenkins Pipeline Stages
4.1 Checkout
Jenkins checks out the infrastructure repository from GitHub.
The pipeline uses the feature/productionize-infrastructure branch and the Jenkinsfile is located at:
jenkins/Jenkinsfile
The repository is accessed using SSH authentication through a Jenkins credential.

## 4.2 Validate Tools
The pipeline validates that the required tools are available on the Jenkins server.

The main tools are:
- Git
- Terraform
- Packer
- AWS CLI
This ensures that the build environment has the required tooling before infrastructure changes are attempted.

## 4.3 Terraform Network
Terraform provisions the AWS networking layer.
This includes:
- VPC
- Internet Gateway
- Public subnets
- Private web subnets
- Private application subnets
- Database subnets
- NAT Gateways
- Route tables
- Security groups
- Application Load Balancer security groups
- Packer builder security group
The network Terraform state is stored remotely in Amazon S3.

```text
terraform/network/
        │
        ▼
network/terraform.tfstate
        │
        ▼
Amazon S3
```

## 4.4 Terraform Database
Terraform provisions the database layer.
The database infrastructure includes:
- Amazon RDS MySQL
- Database subnet group
- RDS security group
- AWS Secrets Manager secret
The database Terraform configuration consumes outputs from the network Terraform state.

```text
Network State
     │
     ▼
Database Terraform
     │
     ├── RDS
     └── Secrets Manager
```

The database state is maintained separately:
database/terraform.tfstate

## 4.5 Discover AWS Configuration
The pipeline retrieves infrastructure information required by subsequent stages.
Examples include:
- VPC ID
- Public subnet ID
- Packer builder security group
- Network resource identifiers
This allows Jenkins to pass dynamically discovered AWS values to Packer instead of hardcoding resource IDs.

## 4.6 Discover Source AMI
The pipeline retrieves the current Amazon Linux 2023 AMI using AWS Systems Manager Parameter Store.
The source AMI is used as the base image for the Packer builds.

```text
AWS Systems Manager
        │
        ▼
Amazon Linux 2023 AMI
        │
        ▼
Packer
```

## 5. Packer Integration
Packer is integrated into the Jenkins pipeline to create immutable application AMIs.
The project creates separate AMIs for the:
- Backend
- Frontend
Backend AMI

The backend Packer build:
1. Launches a temporary EC2 builder instance
2. Uses Amazon Linux as the base image
3. Installs Apache, PHP and required dependencies
4. Retrieves the application code from GitHub
5. Installs application dependencies
6. Configures the backend application
7. Creates an AMI
8. Returns the AMI ID to Jenkins

```text
Amazon Linux
     │
     ▼
Packer Builder
     │
     ├── Apache
     ├── PHP
     ├── Application
     └── Dependencies
     │
     ▼
Backend AMI
Frontend AMI
```

The frontend Packer build:
1. Launches a temporary EC2 builder instance
2. Uses Amazon Linux as the base image
3. Installs Nginx
4. Retrieves the frontend application
5. Configures Nginx
6. Configures the backend ALB endpoint
7. Creates the frontend AMI
8. Returns the AMI ID to Jenkins

```text
Amazon Linux
     │
     ▼
Packer Builder
     │
     ├── Nginx
     ├── Frontend
     └── Backend ALB configuration
     │
     ▼
Frontend AMI
```

## 6. Bootstrap Compute Deployment
There is a dependency between the frontend AMI and the backend ALB.
The frontend configuration requires the backend ALB DNS name.
However, the backend ALB is created by the Terraform compute layer.
The pipeline therefore uses a bootstrap approach:

```text
                    Terraform
                       │
                       ▼
               Bootstrap Compute
                       │
                       ▼
                Backend ALB
                       │
                       ▼
             Backend ALB DNS Name
                       │
                       ▼
                    Packer
                       │
                       ▼
               Frontend AMI
                       │
                       ▼
              Final Terraform
                 Deployment
```

A temporary source AMI is used during the bootstrap deployment so that the required AWS infrastructure can be created first.
Once the backend ALB exists, Jenkins can pass its DNS name to the frontend Packer build.

## 7. Final Compute Deployment
After both application AMIs have been created, Jenkins updates the Terraform compute configuration with the AMI IDs.
Terraform then manages:
- Frontend Application Load Balancer
- Backend Internal Application Load Balancer
- Frontend Auto Scaling Group
- Backend Auto Scaling Group
- Launch Templates
- Target Groups
- Listeners
- EC2 instances
The resulting architecture is:

```text
Internet
   │
   ▼
Frontend ALB
   │
   ▼
Frontend ASG
   │
   ▼
Backend ALB
   │
   ▼
Backend ASG
   │
   ▼
RDS MySQL
```

## 8. Terraform Remote State
The project uses Amazon S3 for Terraform remote state.
Separate state files are maintained for each infrastructure layer:

```text
S3 Bucket
│
├── network/terraform.tfstate
├── database/terraform.tfstate
└── compute/terraform.tfstate
```

This provides separation between the major infrastructure components.
Terraform remote state is also used to pass outputs between layers.
For example:

```text
Network
   │
   ├── VPC ID
   ├── Subnet IDs
   └── Security Group IDs
          │
          ▼
      Database
          │
          ├── RDS endpoint
          └── Secret ARN
                 │
                 ▼
              Compute
```

## 9. Jenkins AWS Authentication
The Jenkins EC2 instance uses an IAM role to access AWS.
No long-lived AWS access keys are required on the Jenkins server.

```text
Jenkins EC2
     │
     ▼
IAM Role
     │
     ▼
AWS APIs
```

The IAM role provides Jenkins with the permissions required to perform the infrastructure deployment workflow.
This includes access to services such as:
- EC2
- VPC
- Elastic Load Balancing
- Auto Scaling
- RDS
- S3
- Secrets Manager
- Systems Manager

## 10. GitHub Integration
The Jenkins pipeline retrieves infrastructure code from GitHub using SSH authentication.

```text
GitHub Repository
       │
       │ SSH
       ▼
Jenkins
       │
       ▼
jenkins/Jenkinsfile
```

The Jenkins credential stores the SSH private key required to access the repository.
The AWS credentials are handled separately through the Jenkins EC2 IAM role.

## 11. Repository Structure
The relevant Jenkins and automation components are organized as follows:

```text
.
├── jenkins/
│   └── Jenkinsfile
│
├── packer/
│   ├── backend/
│   │   └── backend.pkr.hcl
│   │
│   └── frontend/
│       └── frontend.pkr.hcl
│
├── terraform/
│   ├── network/
│   ├── database/
│   └── compute/
│
└── docs/
    ├── architecture.md
    ├── terraform.md
    ├── packer.md
    └── jenkins.md
```

## 12. Design Decisions
Jenkins as the Orchestrator
Jenkins coordinates the workflow while Terraform and Packer remain responsible for their respective domains.
This separation keeps the pipeline modular:

```text
Jenkins
   │
   ├── Terraform → Infrastructure
   │
   └── Packer → Machine Images
```

IAM Role Instead of Static AWS Credentials
The Jenkins EC2 instance uses an IAM role to obtain AWS permissions rather than storing permanent AWS access keys.
Immutable AMIs
Application servers are built as AMIs using Packer.
This avoids relying on manual configuration after EC2 instances are launched and provides a repeatable server build process.
Separate Terraform States
Network, database, and compute infrastructure use separate Terraform states.
This provides clearer infrastructure boundaries and allows each layer to consume outputs from the previous layer.