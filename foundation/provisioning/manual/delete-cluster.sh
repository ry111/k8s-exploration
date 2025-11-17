#!/bin/bash

# Script to delete an EKS cluster and its infrastructure resources
# This is INFRASTRUCTURE cleanup - does NOT touch application resources (ECR, etc.)
# Usage: ./delete-cluster.sh <cluster-name> [region]
# Example: ./delete-cluster.sh trantor us-east-1

set -e

CLUSTER_NAME=${1}
REGION=${2:-us-east-1}

if [ -z "$CLUSTER_NAME" ]; then
  echo "Error: Cluster name is required"
  echo "Usage: $0 <cluster-name> [region]"
  echo "Example: $0 trantor us-east-1"
  exit 1
fi

echo "⚠️  WARNING: This will delete the EKS cluster and all infrastructure resources!"
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo ""
echo "This will delete:"
echo "  - EKS cluster: $CLUSTER_NAME"
echo "  - All node groups and EC2 instances"
echo "  - Application Load Balancers created by services"
echo "  - Associated IAM roles and policies"
echo "  - VPC and networking resources (if created by eksctl)"
echo ""
echo "This will NOT delete:"
echo "  - ECR repositories and images (use delete-service-images.sh)"
echo "  - S3 buckets"
echo "  - Other AWS resources outside the cluster"
echo ""

read -p "Are you sure? Type 'DELETE' to continue: " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
  echo "Aborted."
  exit 1
fi

echo ""
echo "========================================="
echo "Deleting EKS cluster: $CLUSTER_NAME"
echo "========================================="
echo ""

# Check if cluster exists
if ! eksctl get cluster --name "$CLUSTER_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "❌ Cluster '$CLUSTER_NAME' does not exist in region $REGION"
  exit 1
fi

echo "Deleting cluster (this may take 10-15 minutes)..."
eksctl delete cluster --name "$CLUSTER_NAME" --region "$REGION" --wait

echo ""
echo "========================================="
echo "✅ Cluster deleted successfully!"
echo "========================================="
echo ""
echo "Verify deletion:"
echo "  eksctl get cluster --region $REGION"
echo ""
echo "Note: Application resources (ECR images) were not deleted."
echo "To clean up ECR repositories, use: delete-service-images.sh <service-name>"
echo ""
