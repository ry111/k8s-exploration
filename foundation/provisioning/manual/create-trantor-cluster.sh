#!/bin/bash

# Script to create Trantor EKS cluster with SPOT instances
# Usage: ./create-trantor-cluster.sh [region]

set -e

REGION=${1:-us-east-1}

echo "Creating Trantor EKS cluster with SPOT instances..."
echo "Region: $REGION"
echo ""
echo "Configuration:"
echo "  - Cluster name: trantor"
echo "  - Node type: t3.small (spot instances)"
echo "  - Nodes: 1 desired (1 min, 1 max)"
echo "  - Max pods per node: 30"
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
echo "Creating trantor cluster..."
echo "========================================="
echo "This will take approximately 15-20 minutes..."
echo ""

eksctl create cluster \
  --name trantor \
  --region $REGION \
  --version 1.28 \
  --nodegroup-name trantor-spot-nodes \
  --node-type t3.small \
  --nodes 1 \
  --nodes-min 1 \
  --nodes-max 1 \
  --managed \
  --spot \
  --with-oidc \
  --ssh-access=false \
  --max-pods-per-node 30 \
  --tags "Environment=development,Cluster=trantor,CostCenter=learning"

echo ""
echo "========================================="
echo "✅ Trantor cluster created successfully!"
echo "========================================="
echo ""
echo "Cluster details:"
eksctl get cluster --name trantor --region $REGION

echo ""
echo "Node details:"
kubectl get nodes

echo ""
echo "Next steps:"
echo "  1. Run: ./install-alb-controller-trantor.sh $REGION"
echo "  2. Deploy your services (see gitops/manual_deploy for deployment scripts)"
