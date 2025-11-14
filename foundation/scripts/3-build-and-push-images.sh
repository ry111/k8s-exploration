#!/bin/bash

# Script to build Docker images and push to ECR
# Usage: ./3-build-and-push-images.sh [region] [aws-account-id]

set -e

REGION=${1:-us-west-2}
AWS_ACCOUNT_ID=${2}

if [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "Getting AWS Account ID..."
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
fi

echo "Region: $REGION"
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo "ECR Registry: ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
echo ""

SERVICES=("dawn" "day" "dusk")

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

for SERVICE in "${SERVICES[@]}"; do
  echo "========================================="
  echo "Processing ${SERVICE} service..."
  echo "========================================="

  # Create ECR repositories
  echo "Creating ECR repository for ${SERVICE}..."
  aws ecr create-repository --repository-name ${SERVICE} --region $REGION 2>/dev/null || echo "Repository ${SERVICE} already exists"

  # Build Docker images
  echo "Building ${SERVICE} Docker image..."
  cd ../services/${SERVICE}
  docker build -t ${SERVICE}:latest .
  docker build -t ${SERVICE}:rc .

  # Tag images for ECR
  docker tag ${SERVICE}:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${SERVICE}:latest
  docker tag ${SERVICE}:rc ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${SERVICE}:rc

  # Push to ECR
  echo "Pushing ${SERVICE} images to ECR..."
  docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${SERVICE}:latest
  docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${SERVICE}:rc

  cd ../../scripts

  echo "✅ ${SERVICE} images pushed to ECR!"
  echo ""
done

echo "========================================="
echo "All images built and pushed!"
echo "========================================="
echo ""
echo "Image URLs:"
for SERVICE in "${SERVICES[@]}"; do
  echo "  ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${SERVICE}:latest"
  echo "  ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${SERVICE}:rc"
done
