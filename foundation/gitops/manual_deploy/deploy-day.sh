#!/bin/bash

# Script to deploy Day service to a specified EKS cluster
# Usage: ./deploy-day.sh <cluster-name> [region] [aws-account-id]
# Example: ./deploy-day.sh trantor us-east-1

set -e

CLUSTER_NAME=${1}
REGION=${2:-us-east-1}
AWS_ACCOUNT_ID=${3}

if [ -z "$CLUSTER_NAME" ]; then
  echo "Error: Cluster name is required"
  echo "Usage: $0 <cluster-name> [region] [aws-account-id]"
  echo "Example: $0 trantor us-east-1"
  exit 1
fi

if [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "Getting AWS Account ID..."
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
fi

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "========================================="
echo "Deploying Day Service"
echo "========================================="
echo "Target cluster: $CLUSTER_NAME"
echo "ECR Registry: $ECR_REGISTRY"
echo "Region: $REGION"
echo ""

# Set kubectl context to the specified cluster
echo "Setting kubectl context to cluster: $CLUSTER_NAME"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
echo ""

# Create temporary deployment files with ECR image URLs
echo "Preparing deployment manifests..."
TEMP_DIR=$(mktemp -d)

# Copy manifests to temp directory
cp -r ../../k8s/day $TEMP_DIR/

# Update image URLs in temp files (macOS and Linux compatible)
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  sed -i '' "s|image: day:latest|image: ${ECR_REGISTRY}/day:latest|g" $TEMP_DIR/day/deployment.yaml
else
  # Linux
  sed -i "s|image: day:latest|image: ${ECR_REGISTRY}/day:latest|g" $TEMP_DIR/day/deployment.yaml
fi

echo "Applying Day manifests..."
kubectl apply -f $TEMP_DIR/day/

echo ""
echo "Waiting for Day deployment to be ready..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/day -n day-ns 2>/dev/null || echo "⚠️  Deployment may still be in progress"

# Cleanup temp directory
rm -rf $TEMP_DIR

echo ""
echo "========================================="
echo "Day Service Status"
echo "========================================="
echo ""
kubectl get all -n day-ns

echo ""
echo "========================================="
echo "✅ Day service deployed successfully!"
echo "========================================="
echo ""
echo "Get service URL:"
echo "  kubectl get ingress -n day-ns"
echo ""
echo "Test service:"
echo "  curl http://\$(kubectl get ingress day-ingress -n day-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/health"
echo ""
