#!/bin/bash

# Script to deploy Dawn services to EKS cluster
# Usage: ./deploy-dawn.sh [region] [aws-account-id]

set -e

REGION=${1:-us-east-1}
AWS_ACCOUNT_ID=${2}

if [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "Getting AWS Account ID..."
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
fi

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "Deploying Dawn services to dawn-cluster"
echo "Region: $REGION"
echo ""

# Set kubectl context
echo "Setting kubectl context..."
aws eks update-kubeconfig --name dawn-cluster --region $REGION

# Create temporary deployment files with ECR image URLs
echo "Preparing deployment manifests..."
TEMP_DIR=$(mktemp -d)

# Copy all manifests to temp directory
cp -r ../k8s/dawn $TEMP_DIR/
cp -r ../k8s/dawn-rc $TEMP_DIR/

# Update image URLs in temp files (macOS and Linux compatible)
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  sed -i '' "s|image: dawn:latest|image: ${ECR_REGISTRY}/dawn:latest|g" $TEMP_DIR/dawn/deployment.yaml
  sed -i '' "s|image: dawn:rc|image: ${ECR_REGISTRY}/dawn:rc|g" $TEMP_DIR/dawn-rc/deployment.yaml
else
  # Linux
  sed -i "s|image: dawn:latest|image: ${ECR_REGISTRY}/dawn:latest|g" $TEMP_DIR/dawn/deployment.yaml
  sed -i "s|image: dawn:rc|image: ${ECR_REGISTRY}/dawn:rc|g" $TEMP_DIR/dawn-rc/deployment.yaml
fi

echo ""
echo "========================================="
echo "Deploying Dawn Production..."
echo "========================================="

kubectl apply -f $TEMP_DIR/dawn/

echo ""
echo "Waiting for production deployment..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/dawn -n dawn-ns 2>/dev/null || echo "⚠️  Deployment may still be in progress"

echo ""
echo "========================================="
echo "Deploying Dawn RC..."
echo "========================================="

kubectl apply -f $TEMP_DIR/dawn-rc/

echo ""
echo "Waiting for RC deployment..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/dawn-rc -n dawn-rc-ns 2>/dev/null || echo "⚠️  Deployment may still be in progress"

# Cleanup temp directory
rm -rf $TEMP_DIR

echo ""
echo "========================================="
echo "Deployment Status"
echo "========================================="

echo ""
echo "Production Namespace (dawn-ns):"
kubectl get all -n dawn-ns

echo ""
echo "RC Namespace (dawn-rc-ns):"
kubectl get all -n dawn-rc-ns

echo ""
echo "========================================="
echo "Ingress Resources"
echo "========================================="

echo ""
echo "Production Ingress:"
kubectl get ingress -n dawn-ns

echo ""
echo "RC Ingress:"
kubectl get ingress -n dawn-rc-ns

echo ""
echo "========================================="
echo "✅ Dawn services deployed!"
echo "========================================="
echo ""
echo "Get ALB URLs (may take 2-3 minutes to provision):"
echo "  Production: kubectl get ingress dawn-ingress -n dawn-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
echo "  RC:         kubectl get ingress dawn-rc-ingress -n dawn-rc-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
echo ""
echo "Test endpoints once ALB is ready:"
echo "  curl http://\$(kubectl get ingress dawn-ingress -n dawn-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/health"
