#!/bin/bash

# Script to deploy Dawn and Day services to Trantor cluster
# This demonstrates the decoupled architecture where multiple services share a cluster
# Usage: ./deploy-to-trantor.sh [region] [aws-account-id]

set -e

REGION=${1:-us-east-1}
AWS_ACCOUNT_ID=${2}

if [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "Getting AWS Account ID..."
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
fi

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "Deploying services to Trantor cluster"
echo "Services: Dawn + Day (decoupled architecture)"
echo "Region: $REGION"
echo ""

# Set kubectl context
echo "Setting kubectl context..."
aws eks update-kubeconfig --name trantor --region $REGION

# Create temporary deployment files with ECR image URLs
echo "Preparing deployment manifests..."
TEMP_DIR=$(mktemp -d)

# Copy manifests to temp directory
cp -r ../../k8s/dawn $TEMP_DIR/
cp -r ../../k8s/day $TEMP_DIR/

# Update image URLs in temp files (macOS and Linux compatible)
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  sed -i '' "s|image: dawn:latest|image: ${ECR_REGISTRY}/dawn:latest|g" $TEMP_DIR/dawn/deployment.yaml
  sed -i '' "s|image: day:latest|image: ${ECR_REGISTRY}/day:latest|g" $TEMP_DIR/day/deployment.yaml
else
  # Linux
  sed -i "s|image: dawn:latest|image: ${ECR_REGISTRY}/dawn:latest|g" $TEMP_DIR/dawn/deployment.yaml
  sed -i "s|image: day:latest|image: ${ECR_REGISTRY}/day:latest|g" $TEMP_DIR/day/deployment.yaml
fi

echo ""
echo "========================================="
echo "Deploying Dawn service..."
echo "========================================="

kubectl apply -f $TEMP_DIR/dawn/

echo ""
echo "Waiting for Dawn deployment..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/dawn -n dawn-ns 2>/dev/null || echo "⚠️  Deployment may still be in progress"

echo ""
echo "========================================="
echo "Deploying Day service..."
echo "========================================="

kubectl apply -f $TEMP_DIR/day/

echo ""
echo "Waiting for Day deployment..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/day -n day-ns 2>/dev/null || echo "⚠️  Deployment may still be in progress"

# Cleanup temp directory
rm -rf $TEMP_DIR

echo ""
echo "========================================="
echo "Deployment Status - Trantor Cluster"
echo "========================================="

echo ""
echo "Dawn Service (dawn-ns):"
kubectl get all -n dawn-ns

echo ""
echo "Day Service (day-ns):"
kubectl get all -n day-ns

echo ""
echo "========================================="
echo "✅ All services deployed to Trantor!"
echo "========================================="
echo ""
echo "Get service URLs:"
echo "  Dawn: kubectl get ingress -n dawn-ns"
echo "  Day:  kubectl get ingress -n day-ns"
echo ""
echo "Test services:"
echo "  Dawn: curl http://\$(kubectl get ingress dawn-ingress -n dawn-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/health"
echo "  Day:  curl http://\$(kubectl get ingress day-ingress -n day-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/health"
