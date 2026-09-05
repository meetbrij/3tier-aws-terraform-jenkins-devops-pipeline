#!/usr/bin/env bash
# Destroys the demo environment but deliberately preserves the Terraform S3 state bucket.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
STATE_BUCKET="3tier-aws-terraform-jenkins-devops-pipeline"
PROJECT_NAME="three-tier-app"
ENVIRONMENT="dev"

on_error() {
  local exit_code=$?
  echo >&2
  echo "Cleanup stopped at line $1 (exit code: ${exit_code})." >&2
  echo "Resolve the reported issue, then rerun this script; completed Terraform destroys are safe to rerun." >&2
  exit "${exit_code}"
}
trap 'on_error $LINENO' ERR

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

add_ami_if_present() {
  local ami_id="$1"

  [[ -n "${ami_id}" && "${ami_id}" != "None" ]] || return 0

  if aws ec2 describe-images --region "${AWS_REGION}" --image-ids "${ami_id}" \
    --query 'Images[0].ImageId' --output text >/dev/null 2>&1; then
    for existing_ami in "${AMI_IDS[@]:-}"; do
      [[ "${existing_ami}" == "${ami_id}" ]] && return 0
    done
    AMI_IDS+=("${ami_id}")
  else
    echo "Skipping AMI not available in ${AWS_REGION}: ${ami_id}"
  fi
}

destroy_stack() {
  local stack="$1"
  local stack_dir="${SCRIPT_DIR}/terraform/${stack}"

  [[ -d "${stack_dir}" ]] || {
    echo "Terraform stack directory not found: ${stack_dir}" >&2
    exit 1
  }

  echo
  echo "==> Destroying Terraform ${stack} stack"
  terraform -chdir="${stack_dir}" init -input=false
  terraform -chdir="${stack_dir}" destroy -input=false -auto-approve
}

force_delete_database_secret() {
  # Terraform's default Secrets Manager deletion window can otherwise leave this
  # demo secret pending deletion for 30 days after the database stack is destroyed.
  local secret_name="${PROJECT_NAME}/${ENVIRONMENT}/database"

  if aws secretsmanager describe-secret --region "${AWS_REGION}" \
    --secret-id "${secret_name}" >/dev/null 2>&1; then
    echo "==> Permanently deleting database secret: ${secret_name}"
    aws secretsmanager delete-secret --region "${AWS_REGION}" \
      --secret-id "${secret_name}" --force-delete-without-recovery >/dev/null
  fi
}

collect_packer_amis() {
  local component manifest ami_id discovered_amis

  echo
  echo "==> Finding Packer-created frontend and backend AMIs in ${AWS_REGION}"

  # Packer sets Component and Name tags. Name is included as a fallback for older builds.
  for component in frontend backend; do
    discovered_amis="$(aws ec2 describe-images --region "${AWS_REGION}" --owners self \
      --filters "Name=tag:Component,Values=${component}" \
      --query 'Images[].ImageId' --output text)"
    for ami_id in ${discovered_amis}; do
      add_ami_if_present "${ami_id}"
    done

    discovered_amis="$(aws ec2 describe-images --region "${AWS_REGION}" --owners self \
      --filters "Name=name,Values=three-tier-${component}-*" \
      --query 'Images[].ImageId' --output text)"
    for ami_id in ${discovered_amis}; do
      add_ami_if_present "${ami_id}"
    done

    manifest="${SCRIPT_DIR}/packer/${component}/manifest.json"
    if [[ -f "${manifest}" ]]; then
      while IFS= read -r ami_id; do
        add_ami_if_present "${ami_id}"
      done < <(grep -Eo 'ami-[a-z0-9]+' "${manifest}" | sort -u || true)
    fi
  done
}

delete_packer_amis_and_snapshots() {
  local ami_id snapshot_id snapshot_ids

  if [[ ${#AMI_IDS[@]} -eq 0 ]]; then
    echo "No matching Packer-created AMIs found; nothing to deregister."
    return 0
  fi

  echo "The following AMIs will be deregistered in ${AWS_REGION}:"
  printf '  - %s\n' "${AMI_IDS[@]}"

  for ami_id in "${AMI_IDS[@]}"; do
    snapshot_ids="$(aws ec2 describe-images --region "${AWS_REGION}" --image-ids "${ami_id}" \
      --query 'Images[0].BlockDeviceMappings[?Ebs.SnapshotId].Ebs.SnapshotId' --output text)"

    echo "==> Deregistering AMI: ${ami_id}"
    aws ec2 deregister-image --region "${AWS_REGION}" --image-id "${ami_id}"

    for snapshot_id in ${snapshot_ids}; do
      [[ -n "${snapshot_id}" && "${snapshot_id}" != "None" ]] || continue
      echo "==> Deleting EBS snapshot: ${snapshot_id}"
      aws ec2 delete-snapshot --region "${AWS_REGION}" --snapshot-id "${snapshot_id}"
    done
  done
}

main() {
  require_command terraform
  require_command aws

  cd "${SCRIPT_DIR}"
  aws sts get-caller-identity --region "${AWS_REGION}" >/dev/null
  collect_packer_amis

  echo "WARNING: This permanently destroys the ${ENVIRONMENT} demo environment in ${AWS_REGION}."
  echo "It runs Terraform destroy in this order: compute -> database -> network."
  echo "It then deregisters this project's Packer frontend/backend AMIs and deletes their EBS snapshots."
  echo "No RDS final snapshot will be created (the database is configured with skip_final_snapshot = true)."
  echo
  echo "It deliberately keeps:"
  echo "  - S3 Terraform state bucket: ${STATE_BUCKET}"
  echo "  - Terraform state objects, source code, and GitHub repositories"
  echo
  if [[ ${#AMI_IDS[@]} -eq 0 ]]; then
    echo "No matching Packer-created AMIs are currently registered in ${AWS_REGION}."
  else
    echo "Packer-created AMIs queued for deregistration after the Terraform stacks are destroyed:"
    printf '  - %s\n' "${AMI_IDS[@]}"
  fi
  echo
  read -r -p "Type DESTROY to continue: " confirmation
  if [[ "${confirmation}" != "DESTROY" ]]; then
    echo "Cleanup cancelled."
    exit 0
  fi

  destroy_stack compute
  destroy_stack database
  force_delete_database_secret
  destroy_stack network
  delete_packer_amis_and_snapshots

  echo
  echo "Cleanup completed. The Terraform state bucket ${STATE_BUCKET} was not modified."
}

AMI_IDS=()
main "$@"
