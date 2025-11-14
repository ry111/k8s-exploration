#!/bin/bash

# Script to install AWS Load Balancer Controller on all clusters
# Must be run after clusters are created
# Usage: ./2-install-alb-controller.sh [region] [aws-account-id]

set -e

REGION=${1:-us-west-2}
AWS_ACCOUNT_ID=${2}

if [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "Getting AWS Account ID..."
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
fi

echo "Region: $REGION"
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo ""

CLUSTERS=("dawn" "day" "dusk")

# Download IAM policy (only once)
echo "Downloading IAM policy for AWS Load Balancer Controller..."
curl -o /tmp/iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

# Create IAM policy (only once, shared across clusters)
echo "Creating IAM policy..."
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file:///tmp/iam-policy.json \
  2>/dev/null || echo "IAM policy already exists, continuing..."

echo ""

for CLUSTER in "${CLUSTERS[@]}"; do
  echo "========================================="
  echo "Installing ALB Controller on ${CLUSTER}-cluster..."
  echo "========================================="

  # Set kubectl context
  aws eks update-kubeconfig --name ${CLUSTER}-cluster --region $REGION

  # Create IAM service account
  echo "Creating IAM service account..."
  eksctl create iamserviceaccount \
    --cluster=${CLUSTER}-cluster \
    --region=$REGION \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
    --approve \
    --override-existing-serviceaccounts

  # Add eks-charts helm repo (only once)
  helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
  helm repo update

  # Install AWS Load Balancer Controller
  echo "Installing AWS Load Balancer Controller via Helm..."
  helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=${CLUSTER}-cluster \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set region=$REGION \
    --set vpcId=$(aws eks describe-cluster --name ${CLUSTER}-cluster --region $REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text)

  echo "Waiting for controller to be ready..."
  kubectl wait --namespace kube-system \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=aws-load-balancer-controller \
    --timeout=90s

  echo "✅ ALB Controller installed on ${CLUSTER}-cluster!"
  echo ""
done

echo "========================================="
echo "All ALB Controllers installed!"
echo "========================================="
