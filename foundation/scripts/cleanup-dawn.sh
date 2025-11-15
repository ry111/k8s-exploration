#!/bin/bash

# Script to delete Dawn EKS cluster and all resources
# WARNING: This will destroy everything!
# Usage: ./cleanup-dawn.sh [region]

set -e

REGION=${1:-us-east-1}

echo "⚠️  WARNING: This will delete the Dawn cluster and all resources!"
echo "Region: $REGION"
echo ""
echo "This will delete:"
echo "  - dawn-cluster EKS cluster"
echo "  - All node groups and EC2 instances"
echo "  - Dawn ECR repository and images"
echo "  - Application Load Balancers"
echo "  - Associated IAM roles and policies"
echo ""

read -p "Are you sure? Type 'DELETE' to continue: " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
  echo "Aborted."
  exit 1
fi

echo ""
echo "========================================="
echo "Deleting dawn-cluster..."
echo "========================================="

eksctl delete cluster --name dawn-cluster --region $REGION --wait

echo ""
echo "========================================="
echo "Deleting ECR repository..."
echo "========================================="

aws ecr delete-repository --repository-name dawn --region $REGION --force 2>/dev/null || echo "✓ ECR repository already deleted"

echo ""
echo "========================================="
echo "✅ All Dawn resources deleted!"
echo "========================================="
echo ""
echo "Verify deletion:"
echo "  eksctl get cluster --region $REGION"
