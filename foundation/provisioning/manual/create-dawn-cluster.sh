#!/bin/bash

# Script to create Dawn EKS cluster with SPOT instances
# Usage: ./create-dawn-cluster.sh [region]

set -e

REGION=${1:-us-east-1}

echo "Creating Dawn EKS cluster with SPOT instances..."
echo "Region: $REGION"
echo ""
echo "Configuration:"
echo "  - Cluster name: dawn-cluster"
echo "  - Node type: t3.small (spot instances)"
echo "  - Nodes: 2 desired (1 min, 3 max)"
echo "  - Cost savings: ~70% vs on-demand"
echo ""
echo "⚠️  Note: Spot instances can be terminated with 2-minute warning"
echo ""

read -p "Continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 1
fi

echo ""
echo "========================================="
echo "Creating dawn-cluster..."
echo "========================================="
echo "This will take approximately 15-20 minutes..."
echo ""

eksctl create cluster \
  --name dawn-cluster \
  --region $REGION \
  --version 1.28 \
  --nodegroup-name dawn-spot-nodes \
  --node-type t3.small \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3 \
  --managed \
  --spot \
  --with-oidc \
  --ssh-access=false \
  --tags "Environment=development,Service=dawn,CostCenter=learning"

echo ""
echo "========================================="
echo "✅ Dawn cluster created successfully!"
echo "========================================="
echo ""
echo "Cluster details:"
eksctl get cluster --name dawn-cluster --region $REGION

echo ""
echo "Node details:"
kubectl get nodes

echo ""
echo "Next steps:"
echo "  1. Run: ./install-alb-controller-dawn.sh $REGION"
echo "  2. Run: ./build-and-push-dawn.sh $REGION"
echo "  3. Run: ./deploy-dawn.sh $REGION"
