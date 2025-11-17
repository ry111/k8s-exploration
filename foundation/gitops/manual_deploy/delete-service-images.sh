#!/bin/bash

# Script to delete ECR repository for a specific service
# This is APPLICATION cleanup - removes container images
# Usage: ./delete-service-images.sh <service-name> [region]
# Example: ./delete-service-images.sh dawn us-east-1

set -e

SERVICE_NAME=${1}
REGION=${2:-us-east-1}

if [ -z "$SERVICE_NAME" ]; then
  echo "Error: Service name is required"
  echo "Usage: $0 <service-name> [region]"
  echo "Example: $0 dawn us-east-1"
  exit 1
fi

echo "⚠️  WARNING: This will delete the ECR repository and all images!"
echo ""
echo "Service: $SERVICE_NAME"
echo "Region: $REGION"
echo ""
echo "This will delete:"
echo "  - ECR repository: $SERVICE_NAME"
echo "  - All container images and tags in this repository"
echo ""
echo "This will NOT delete:"
echo "  - Kubernetes deployments (use kubectl delete)"
echo "  - EKS clusters (use delete-cluster.sh)"
echo ""

read -p "Are you sure? Type 'DELETE' to continue: " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
  echo "Aborted."
  exit 1
fi

echo ""
echo "========================================="
echo "Deleting ECR repository: $SERVICE_NAME"
echo "========================================="
echo ""

# Check if repository exists
if aws ecr describe-repositories --repository-names "$SERVICE_NAME" --region "$REGION" >/dev/null 2>&1; then
  aws ecr delete-repository --repository-name "$SERVICE_NAME" --region "$REGION" --force
  echo "✅ ECR repository '$SERVICE_NAME' deleted successfully"
else
  echo "ℹ️  ECR repository '$SERVICE_NAME' does not exist (already deleted or never created)"
fi

echo ""
echo "========================================="
echo "✅ Service images cleanup complete!"
echo "========================================="
echo ""
echo "Verify deletion:"
echo "  aws ecr describe-repositories --region $REGION"
echo ""
