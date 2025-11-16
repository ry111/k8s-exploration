#!/bin/bash

# Script to delete Trantor EKS cluster and all resources
# WARNING: This will destroy everything!
# Usage: ./cleanup-trantor.sh [region]

set -e

REGION=${1:-us-east-1}

echo "⚠️  WARNING: This will delete the Trantor cluster and all resources!"
echo "Region: $REGION"
echo ""
echo "This will delete:"
echo "  - Trantor EKS cluster"
echo "  - All node groups and EC2 instances"
echo "  - Dawn and Day ECR repositories and images"
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
echo "Deleting Trantor cluster..."
echo "========================================="

eksctl delete cluster --name trantor --region $REGION --wait

echo ""
echo "========================================="
echo "Deleting ECR repositories..."
echo "========================================="

aws ecr delete-repository --repository-name dawn --region $REGION --force 2>/dev/null || echo "✓ Dawn ECR repository already deleted"
aws ecr delete-repository --repository-name day --region $REGION --force 2>/dev/null || echo "✓ Day ECR repository already deleted"

echo ""
echo "========================================="
echo "✅ All Trantor resources deleted!"
echo "========================================="
echo ""
echo "Verify deletion:"
echo "  eksctl get cluster --region $REGION"
