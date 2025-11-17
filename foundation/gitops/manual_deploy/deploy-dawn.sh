#!/bin/bash

# Script to deploy Dawn service to the current kubectl context
# Works with any cluster - uses whatever is configured in kubectl
# Usage: ./deploy-dawn.sh [region] [aws-account-id]

set -e

REGION=${1:-us-east-1}
AWS_ACCOUNT_ID=${2}

if [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "Getting AWS Account ID..."
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
fi

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# Get current kubectl context
CURRENT_CONTEXT=$(kubectl config current-context)
CURRENT_CLUSTER=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='$CURRENT_CONTEXT')].context.cluster}")

echo "========================================="
echo "Deploying Dawn Service"
echo "========================================="
echo "Target cluster: $CURRENT_CLUSTER"
echo "ECR Registry: $ECR_REGISTRY"
echo "Region: $REGION"
echo ""

# Create temporary deployment files with ECR image URLs
echo "Preparing deployment manifests..."
TEMP_DIR=$(mktemp -d)

# Copy manifests to temp directory
cp -r ../../k8s/dawn $TEMP_DIR/

# Update image URLs in temp files (macOS and Linux compatible)
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  sed -i '' "s|image: dawn:latest|image: ${ECR_REGISTRY}/dawn:latest|g" $TEMP_DIR/dawn/deployment.yaml
else
  # Linux
  sed -i "s|image: dawn:latest|image: ${ECR_REGISTRY}/dawn:latest|g" $TEMP_DIR/dawn/deployment.yaml
fi

echo "Applying Dawn manifests..."
kubectl apply -f $TEMP_DIR/dawn/

echo ""
echo "Waiting for Dawn deployment to be ready..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/dawn -n dawn-ns 2>/dev/null || echo "⚠️  Deployment may still be in progress"

# Cleanup temp directory
rm -rf $TEMP_DIR

echo ""
echo "========================================="
echo "Dawn Service Status"
echo "========================================="
echo ""
kubectl get all -n dawn-ns

echo ""
echo "========================================="
echo "✅ Dawn service deployed successfully!"
echo "========================================="
echo ""
echo "Get service URL:"
echo "  kubectl get ingress -n dawn-ns"
echo ""
echo "Test service:"
echo "  curl http://\$(kubectl get ingress dawn-ingress -n dawn-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/health"
echo ""
