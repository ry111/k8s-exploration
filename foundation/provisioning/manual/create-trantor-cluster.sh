#!/bin/bash

# Script to create Trantor EKS cluster with SPOT instances
# This cluster hosts multiple services: Dawn and Day
# Usage: ./create-trantor-cluster.sh [region]

set -e

REGION=${1:-us-east-1}

echo "Creating Trantor EKS cluster with SPOT instances..."
echo "Region: $REGION"
echo ""
echo "Configuration:"
echo "  - Cluster name: trantor"
echo "  - Services: Dawn + Day (decoupled from cluster name)"
echo "  - Node type: t3.small (spot instances)"
echo "  - Nodes: 2 desired (1 min, 4 max)"
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
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 4 \
  --managed \
  --spot \
  --with-oidc \
  --ssh-access=false \
  --tags "Environment=development,Cluster=trantor,Services=dawn-day,CostCenter=learning"

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
echo "  2. Deploy services:"
echo "     cd ../../gitops/manual_deploy"
echo "     ./build-and-push-dawn.sh $REGION"
echo "     ./build-and-push-day.sh $REGION"
echo "     ./deploy-to-trantor.sh $REGION"
