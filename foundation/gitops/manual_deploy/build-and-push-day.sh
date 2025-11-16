#!/bin/bash

# Script to build Day Docker images and push to ECR
# Usage: ./build-and-push-day.sh [region] [aws-account-id]

set -e

REGION=${1:-us-east-1}
AWS_ACCOUNT_ID=${2}

if [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "Getting AWS Account ID..."
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
fi

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "Building and pushing Day Docker images"
echo "Region: $REGION"
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo "ECR Registry: $ECR_REGISTRY"
echo ""

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# Create ECR repository
echo "Creating ECR repository for day..."
aws ecr create-repository --repository-name day --region $REGION 2>/dev/null || echo "✓ Repository day already exists"

# Build Docker images
echo ""
echo "Building Day Docker images..."
cd ../../services/day

docker build -t day:latest .
echo "✓ Built day:latest"

# Tag images for ECR
docker tag day:latest ${ECR_REGISTRY}/day:latest

echo ""
echo "Pushing images to ECR..."
docker push ${ECR_REGISTRY}/day:latest
echo "✓ Pushed day:latest"

cd ../../gitops/manual_deploy

echo ""
echo "========================================="
echo "✅ Day images built and pushed!"
echo "========================================="
echo ""
echo "Image URL:"
echo "  ${ECR_REGISTRY}/day:latest"
echo ""
echo "Next step:"
echo "  ./deploy-to-trantor.sh $REGION"
