#!/bin/bash

# Script to install AWS Load Balancer Controller on Trantor cluster
# Usage: ./install-alb-controller-trantor.sh [region] [aws-account-id]

set -e

REGION=${1:-us-east-1}
AWS_ACCOUNT_ID=${2}

if [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "Getting AWS Account ID..."
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
fi

echo "Installing AWS Load Balancer Controller on trantor cluster"
echo "Region: $REGION"
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo ""

# Set kubectl context
echo "Setting kubectl context..."
aws eks update-kubeconfig --name trantor --region $REGION

# Download IAM policy
echo "Downloading IAM policy..."
curl -s -o /tmp/iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

# Create IAM policy
echo "Creating IAM policy..."
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file:///tmp/iam-policy.json \
  2>/dev/null || echo "✓ IAM policy already exists"

# Create IAM service account
echo "Creating IAM service account..."
eksctl create iamserviceaccount \
  --cluster=trantor \
  --region=$REGION \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve \
  --override-existing-serviceaccounts

# Add eks-charts helm repo
echo "Adding Helm repository..."
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update

# Get VPC ID
VPC_ID=$(aws eks describe-cluster --name trantor --region $REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text)
echo "VPC ID: $VPC_ID"

# Install AWS Load Balancer Controller
echo "Installing AWS Load Balancer Controller via Helm..."
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=trantor \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$REGION \
  --set vpcId=$VPC_ID

echo ""
echo "Waiting for controller to be ready..."
kubectl wait --namespace kube-system \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=aws-load-balancer-controller \
  --timeout=120s

echo ""
echo "========================================="
echo "✅ ALB Controller installed successfully!"
echo "========================================="

# Install metrics-server for HPA
echo ""
echo "Installing metrics-server for HPA support..."
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ 2>/dev/null || true
helm repo update

helm install metrics-server metrics-server/metrics-server \
  -n kube-system \
  --set 'args[0]=--kubelet-preferred-address-types=InternalIP'

echo ""
echo "Waiting for metrics-server to be ready..."
kubectl wait --namespace kube-system \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=metrics-server \
  --timeout=120s

echo ""
echo "========================================="
echo "✅ Metrics Server installed successfully!"
echo "========================================="
echo ""
echo "Verify installations:"
echo "  kubectl get deployment -n kube-system aws-load-balancer-controller"
echo "  kubectl get deployment -n kube-system metrics-server"
echo "  kubectl top nodes  # Test metrics-server"
echo ""
echo "Next steps:"
echo "  Deploy your services (see gitops/manual_deploy for deployment scripts)"
