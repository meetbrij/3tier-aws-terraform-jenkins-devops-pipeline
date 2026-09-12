#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# 3-Tier AWS Project Cleanup
#
# Removes AWS resources created by the 3-tier Terraform +
# Jenkins + Packer project.
#
# PROTECTED:
#   - Jenkins EC2
#   - Jenkins IAM role/profile
#   - Terraform S3 state bucket
#   - GitHub repositories
#
# Run from the repository root.
# ============================================================

AWS_REGION="us-east-1"
PROJECT_NAME="three-tier-app"
ENVIRONMENT="dev"
STATE_BUCKET="3tier-aws-terraform-jenkins-devops-pipeline"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

NETWORK_DIR="${REPO_ROOT}/terraform/network"
DATABASE_DIR="${REPO_ROOT}/terraform/database"
COMPUTE_DIR="${REPO_ROOT}/terraform/compute"

echo
echo "============================================================"
echo "3-TIER AWS PROJECT CLEANUP"
echo "============================================================"
echo "Region:       ${AWS_REGION}"
echo "Project:      ${PROJECT_NAME}"
echo "Environment:  ${ENVIRONMENT}"
echo "State bucket: ${STATE_BUCKET}"
echo
echo "PROTECTED:"
echo "  - Jenkins"
echo "  - Jenkins IAM"
echo "  - Terraform S3 state bucket"
echo "  - GitHub"
echo "============================================================"
echo

read -r -p "Type DELETE to continue: " CONFIRM

if [[ "${CONFIRM}" != "DELETE" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo
echo "Checking AWS identity..."
aws sts get-caller-identity

echo
echo "============================================================"
echo "STEP 1 - Get Jenkins public IP"
echo "============================================================"

JENKINS_PUBLIC_IP="$(curl -s https://checkip.amazonaws.com)"

echo "Jenkins public IP: ${JENKINS_PUBLIC_IP}"

# ============================================================
# STEP 2 - Destroy Compute
# ============================================================

echo
echo "============================================================"
echo "STEP 2 - Destroy Terraform Compute"
echo "============================================================"

cd "${COMPUTE_DIR}"

terraform init -input=false

echo "Terraform Compute resources:"
terraform state list || true

if terraform state list 2>/dev/null | grep -q .; then

    terraform destroy -auto-approve \
        -var="aws_region=${AWS_REGION}" \
        -var="project_name=${PROJECT_NAME}" \
        -var="environment=${ENVIRONMENT}" \
        -var="terraform_state_bucket=${STATE_BUCKET}"

else
    echo "Compute Terraform state is already empty."
fi

# ============================================================
# STEP 3 - Destroy Database
# ============================================================

echo
echo "============================================================"
echo "STEP 3 - Destroy Terraform Database"
echo "============================================================"

cd "${DATABASE_DIR}"

terraform init -input=false

echo "Terraform Database resources:"
terraform state list || true

if terraform state list 2>/dev/null | grep -q .; then

    terraform destroy -auto-approve \
        -var="aws_region=${AWS_REGION}" \
        -var="project_name=${PROJECT_NAME}" \
        -var="environment=${ENVIRONMENT}" \
        -var="terraform_state_bucket=${STATE_BUCKET}"

else
    echo "Database Terraform state is already empty."
fi

# ============================================================
# STEP 4 - Destroy Network
# ============================================================

echo
echo "============================================================"
echo "STEP 4 - Destroy Terraform Network"
echo "============================================================"

cd "${NETWORK_DIR}"

terraform init -input=false

echo "Terraform Network resources:"
terraform state list || true

if terraform state list 2>/dev/null | grep -q .; then

    terraform destroy -auto-approve \
        -var="aws_region=${AWS_REGION}" \
        -var="project_name=${PROJECT_NAME}" \
        -var="environment=${ENVIRONMENT}" \
        -var="web_public_subnets='[\"10.0.1.0/24\",\"10.0.2.0/24\",\"10.0.3.0/24\"]'" \
        -var="web_private_subnets='[\"10.0.11.0/24\",\"10.0.12.0/24\",\"10.0.13.0/24\"]'" \
        -var="app_private_subnets='[\"10.0.21.0/24\",\"10.0.22.0/24\",\"10.0.23.0/24\"]'" \
        -var="database_subnets='[\"10.0.31.0/24\",\"10.0.32.0/24\",\"10.0.33.0/24\"]'" \
        -var="availability_zones='[\"us-east-1a\",\"us-east-1b\",\"us-east-1c\"]'" \
        -var="packer_ssh_cidr=${JENKINS_PUBLIC_IP}/32"

else
    echo "Network Terraform state is already empty."
fi

# ============================================================
# STEP 5 - Remove Packer AMIs
# ============================================================

echo
echo "============================================================"
echo "STEP 5 - Remove Packer AMIs"
echo "============================================================"

echo "Searching for project AMIs..."

AMI_IDS=$(aws ec2 describe-images \
    --region "${AWS_REGION}" \
    --owners self \
    --query 'Images[?starts_with(Name, `three-tier-backend-`) || starts_with(Name, `three-tier-frontend-`)].ImageId' \
    --output text)

if [[ -z "${AMI_IDS}" ]]; then

    echo "No project AMIs found."

else

    for AMI_ID in ${AMI_IDS}; do

        echo
        echo "Processing ${AMI_ID}"

        SNAPSHOT_IDS=$(aws ec2 describe-images \
            --region "${AWS_REGION}" \
            --image-ids "${AMI_ID}" \
            --query 'Images[0].BlockDeviceMappings[].Ebs.SnapshotId' \
            --output text)

        echo "Deregistering AMI ${AMI_ID}"

        aws ec2 deregister-image \
            --region "${AWS_REGION}" \
            --image-id "${AMI_ID}"

        for SNAPSHOT_ID in ${SNAPSHOT_IDS}; do

            if [[ "${SNAPSHOT_ID}" != "None" && -n "${SNAPSHOT_ID}" ]]; then

                echo "Deleting snapshot ${SNAPSHOT_ID}"

                aws ec2 delete-snapshot \
                    --region "${AWS_REGION}" \
                    --snapshot-id "${SNAPSHOT_ID}"

            fi

        done

    done

fi

# ============================================================
# STEP 6 - Verify Terraform states
# ============================================================

echo
echo "============================================================"
echo "STEP 6 - Verify Terraform States"
echo "============================================================"

for DIR in "${COMPUTE_DIR}" "${DATABASE_DIR}" "${NETWORK_DIR}"; do

    echo
    echo "Checking ${DIR}"

    cd "${DIR}"

    if terraform state list 2>/dev/null | grep -q .; then
        echo "WARNING: Terraform state still contains resources:"
        terraform state list
    else
        echo "Terraform state is EMPTY."
    fi

done

# ============================================================
# STEP 7 - Verify project AWS resources
# ============================================================

echo
echo "============================================================"
echo "STEP 7 - AWS Verification"
echo "============================================================"

echo
echo "--- Project VPCs ---"

aws ec2 describe-vpcs \
    --region "${AWS_REGION}" \
    --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
    --query 'Vpcs[].VpcId' \
    --output table

echo
echo "--- Project Load Balancers ---"

aws elbv2 describe-load-balancers \
    --region "${AWS_REGION}" \
    --query "LoadBalancers[?contains(LoadBalancerName, '${PROJECT_NAME}')].[LoadBalancerName,LoadBalancerArn]" \
    --output table

echo
echo "--- Project Auto Scaling Groups ---"

aws autoscaling describe-auto-scaling-groups \
    --region "${AWS_REGION}" \
    --query "AutoScalingGroups[?contains(AutoScalingGroupName, '${PROJECT_NAME}')].AutoScalingGroupName" \
    --output table

echo
echo "--- Project AMIs ---"

aws ec2 describe-images \
    --region "${AWS_REGION}" \
    --owners self \
    --query 'Images[?starts_with(Name, `three-tier-backend-`) || starts_with(Name, `three-tier-frontend-`)].[ImageId,Name]' \
    --output table

echo
echo "============================================================"
echo "CLEANUP COMPLETE"
echo "============================================================"

echo
echo "Protected resources were NOT touched:"
echo "  Jenkins"
echo "  Jenkins IAM"
echo "  Terraform S3 state bucket"
echo "  GitHub"
echo