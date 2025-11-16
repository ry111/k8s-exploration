#!/bin/bash

# Script to update deployment manifests with ECR image URLs
# Usage: ./4-update-deployment-images.sh [region] [aws-account-id]

set -e

REGION=${1:-us-east-1}
AWS_ACCOUNT_ID=${2}

if [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "Getting AWS Account ID..."
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
fi

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "Updating deployment manifests with ECR image URLs..."
echo "ECR Registry: $ECR_REGISTRY"
echo ""

SERVICES=("dawn" "day" "dusk")

for SERVICE in "${SERVICES[@]}"; do
  echo "Updating ${SERVICE} deployments..."

  # Update production deployment
  sed -i.bak "s|image: ${SERVICE}:latest|image: ${ECR_REGISTRY}/${SERVICE}:latest|g" ../k8s/${SERVICE}/deployment.yaml

  # Update RC deployment
  sed -i.bak "s|image: ${SERVICE}:rc|image: ${ECR_REGISTRY}/${SERVICE}:rc|g" ../k8s/${SERVICE}-rc/deployment.yaml

  # Remove backup files
  rm -f ../k8s/${SERVICE}/deployment.yaml.bak
  rm -f ../k8s/${SERVICE}-rc/deployment.yaml.bak

  echo "  ✅ ${SERVICE} production: ${ECR_REGISTRY}/${SERVICE}:latest"
  echo "  ✅ ${SERVICE} RC: ${ECR_REGISTRY}/${SERVICE}:rc"
done

echo ""
echo "========================================="
echo "All deployment manifests updated!"
echo "========================================="
echo ""
echo "Note: These changes are temporary. Run git diff to see them."
echo "You may want to parameterize these instead of committing ECR URLs."
