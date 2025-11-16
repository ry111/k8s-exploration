#!/bin/bash

# Script to delete all EKS clusters and associated resources
# WARNING: This will destroy everything!
# Usage: ./cleanup.sh [region]

set -e

REGION=${1:-us-east-1}

echo "⚠️  WARNING: This will delete all clusters and resources!"
echo "Region: $REGION"
echo ""
read -p "Are you sure? Type 'yes' to continue: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 1
fi

CLUSTERS=("dawn" "day" "dusk")

for CLUSTER in "${CLUSTERS[@]}"; do
  echo "========================================="
  echo "Deleting ${CLUSTER}-cluster..."
  echo "========================================="

  eksctl delete cluster --name ${CLUSTER}-cluster --region $REGION --wait

  echo "✅ ${CLUSTER}-cluster deleted!"
  echo ""
done

echo "========================================="
echo "Cleaning up ECR repositories..."
echo "========================================="

SERVICES=("dawn" "day" "dusk")
for SERVICE in "${SERVICES[@]}"; do
  echo "Deleting ECR repository: ${SERVICE}"
  aws ecr delete-repository --repository-name ${SERVICE} --region $REGION --force 2>/dev/null || echo "Repository ${SERVICE} not found"
done

echo ""
echo "========================================="
echo "All resources deleted!"
echo "========================================="
