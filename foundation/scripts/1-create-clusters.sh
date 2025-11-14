#!/bin/bash

# Script to create all three EKS clusters
# Usage: ./1-create-clusters.sh [region]

set -e

REGION=${1:-us-west-2}

echo "Creating EKS clusters in region: $REGION"
echo "This will take approximately 15-20 minutes per cluster..."
echo ""

# Array of cluster names
CLUSTERS=("dawn" "day" "dusk")

for CLUSTER in "${CLUSTERS[@]}"; do
  echo "========================================="
  echo "Creating ${CLUSTER}-cluster..."
  echo "========================================="

  eksctl create cluster \
    --name ${CLUSTER}-cluster \
    --region $REGION \
    --nodegroup-name ${CLUSTER}-nodes \
    --node-type t3.small \
    --nodes 2 \
    --nodes-min 1 \
    --nodes-max 3 \
    --managed \
    --with-oidc

  echo ""
  echo "✅ ${CLUSTER}-cluster created successfully!"
  echo ""
done

echo "========================================="
echo "All clusters created!"
echo "========================================="
echo ""
echo "Verify clusters:"
for CLUSTER in "${CLUSTERS[@]}"; do
  echo "  eksctl get cluster --name ${CLUSTER}-cluster --region $REGION"
done
