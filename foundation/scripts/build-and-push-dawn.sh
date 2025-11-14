#!/bin/bash

# Script to build Dawn Docker images and push to ECR
# Usage: ./build-and-push-dawn.sh [region] [aws-account-id]

set -e

REGION=${1:-us-west-2}
AWS_ACCOUNT_ID=${2}

if [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "Getting AWS Account ID..."
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
fi

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "Building and pushing Dawn Docker images"
echo "Region: $REGION"
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo "ECR Registry: $ECR_REGISTRY"
echo ""

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# Create ECR repository
echo "Creating ECR repository for dawn..."
aws ecr create-repository --repository-name dawn --region $REGION 2>/dev/null || echo "✓ Repository dawn already exists"

# Build Docker images
echo ""
echo "Building Dawn Docker images..."
cd ../services/dawn

docker build -t dawn:latest .
echo "✓ Built dawn:latest"

# Tag images for ECR
docker tag dawn:latest ${ECR_REGISTRY}/dawn:latest
docker tag dawn:latest ${ECR_REGISTRY}/dawn:rc

echo ""
echo "Pushing images to ECR..."
docker push ${ECR_REGISTRY}/dawn:latest
echo "✓ Pushed dawn:latest"

docker push ${ECR_REGISTRY}/dawn:rc
echo "✓ Pushed dawn:rc"

cd ../../scripts

echo ""
echo "========================================="
echo "✅ Dawn images built and pushed!"
echo "========================================="
echo ""
echo "Image URLs:"
echo "  Production: ${ECR_REGISTRY}/dawn:latest"
echo "  RC:         ${ECR_REGISTRY}/dawn:rc"
echo ""
echo "Next step:"
echo "  ./deploy-dawn.sh $REGION"
