#!/bin/bash

# Script to deploy Dawn service to a specified EKS cluster
# Usage: ./deploy-dawn.sh <cluster-name> [region] [aws-account-id]
# Example: ./deploy-dawn.sh trantor us-east-1

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
echo "Deploying Dawn Service"
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
cp -r ../../k8s/dawn $TEMP_DIR/

# Update image URLs in temp files (macOS and Linux compatible)
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  sed -i '' "s|image: dawn:latest|image: ${ECR_REGISTRY}/dawn:latest|g" $TEMP_DIR/dawn/prod/deployment.yaml
  sed -i '' "s|image: dawn:rc|image: ${ECR_REGISTRY}/dawn:rc|g" $TEMP_DIR/dawn/rc/deployment.yaml
else
  # Linux
  sed -i "s|image: dawn:latest|image: ${ECR_REGISTRY}/dawn:latest|g" $TEMP_DIR/dawn/prod/deployment.yaml
  sed -i "s|image: dawn:rc|image: ${ECR_REGISTRY}/dawn:rc|g" $TEMP_DIR/dawn/rc/deployment.yaml
fi

echo "Applying Dawn manifests (prod + rc)..."
kubectl apply -f $TEMP_DIR/dawn/prod/
kubectl apply -f $TEMP_DIR/dawn/rc/

echo ""
echo "Waiting for Dawn deployments to be ready..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/dawn -n dawn-ns 2>/dev/null || echo "⚠️  Production deployment may still be in progress"
kubectl wait --for=condition=available --timeout=300s \
  deployment/dawn-rc -n dawn-rc-ns 2>/dev/null || echo "⚠️  RC deployment may still be in progress"

# Cleanup temp directory
rm -rf $TEMP_DIR

echo ""
echo "========================================="
echo "Dawn Service Status"
echo "========================================="
echo ""
echo "Production (dawn-ns):"
kubectl get all -n dawn-ns
echo ""
echo "RC (dawn-rc-ns):"
kubectl get all -n dawn-rc-ns

echo ""
echo "========================================="
echo "✅ Dawn service deployed successfully!"
echo "========================================="
echo ""
echo "Get service URLs:"
echo "  kubectl get ingress -n dawn-ns        # Production"
echo "  kubectl get ingress -n dawn-rc-ns     # RC"
echo ""
echo "Test services:"
echo "  curl http://\$(kubectl get ingress dawn-ingress -n dawn-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/health"
echo "  curl http://\$(kubectl get ingress dawn-rc-ingress -n dawn-rc-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/health"
echo ""
