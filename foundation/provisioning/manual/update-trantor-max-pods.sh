#!/bin/bash

# Script to update Trantor EKS cluster node group with increased max-pods-per-node
# This creates a new node group with max-pods-per-node=30 and migrates workloads
# Usage: ./update-trantor-max-pods.sh [region]

set -e

REGION=${1:-us-east-1}
CLUSTER_NAME="trantor"
OLD_NODEGROUP="trantor-spot-nodes"
NEW_NODEGROUP="trantor-spot-nodes-v2"
MAX_PODS=30

echo "========================================="
echo "Updating Trantor cluster max_pods setting"
echo "========================================="
echo ""
echo "Current Configuration:"
echo "  - Cluster: $CLUSTER_NAME"
echo "  - Old node group: $OLD_NODEGROUP (max_pods: 11)"
echo "  - New node group: $NEW_NODEGROUP (max_pods: $MAX_PODS)"
echo "  - Node type: t3.small (spot instances)"
echo "  - Nodes: 2 desired (1 min, 4 max)"
echo ""
echo "This process will:"
echo "  1. Create new node group with max_pods=$MAX_PODS"
echo "  2. Wait for new nodes to be ready"
echo "  3. Drain and cordon old nodes"
echo "  4. Delete old node group"
echo ""
echo "⚠️  Warning: This will cause pod rescheduling"
echo ""

read -p "Continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 1
fi

echo ""
echo "========================================="
echo "Step 1: Creating new node group..."
echo "========================================="
echo ""

eksctl create nodegroup \
  --cluster=$CLUSTER_NAME \
  --region=$REGION \
  --name=$NEW_NODEGROUP \
  --node-type=t3.small \
  --nodes=2 \
  --nodes-min=1 \
  --nodes-max=4 \
  --managed \
  --spot \
  --max-pods-per-node=$MAX_PODS

echo ""
echo "✅ New node group created successfully!"
echo ""
echo "Waiting for nodes to be ready..."
kubectl wait --for=condition=Ready nodes --selector=eks.amazonaws.com/nodegroup=$NEW_NODEGROUP --timeout=300s

echo ""
echo "========================================="
echo "Step 2: Verifying new nodes..."
echo "========================================="
echo ""
kubectl get nodes -l eks.amazonaws.com/nodegroup=$NEW_NODEGROUP -o wide

echo ""
echo "Checking max_pods on new nodes:"
kubectl get nodes -l eks.amazonaws.com/nodegroup=$NEW_NODEGROUP -o json | \
  jq -r '.items[] | "\(.metadata.name): \(.status.allocatable.pods) pods"'

echo ""
echo "========================================="
echo "Step 3: Draining old node group..."
echo "========================================="
echo ""

# Get old nodes
OLD_NODES=$(kubectl get nodes -l eks.amazonaws.com/nodegroup=$OLD_NODEGROUP -o name)

if [ -z "$OLD_NODES" ]; then
  echo "No old nodes found. Skipping drain step."
else
  echo "Draining nodes in old node group..."
  for node in $OLD_NODES; do
    echo "Draining $node..."
    kubectl drain $node --ignore-daemonsets --delete-emptydir-data --force
  done
  echo "✅ Old nodes drained successfully!"
fi

echo ""
echo "========================================="
echo "Step 4: Deleting old node group..."
echo "========================================="
echo ""

read -p "Delete old node group '$OLD_NODEGROUP'? (yes/no): " CONFIRM_DELETE
if [ "$CONFIRM_DELETE" != "yes" ]; then
  echo "Skipping deletion. You can delete it manually later with:"
  echo "  eksctl delete nodegroup --cluster=$CLUSTER_NAME --name=$OLD_NODEGROUP --region=$REGION"
  exit 0
fi

eksctl delete nodegroup \
  --cluster=$CLUSTER_NAME \
  --region=$REGION \
  --name=$OLD_NODEGROUP

echo ""
echo "========================================="
echo "✅ Update completed successfully!"
echo "========================================="
echo ""
echo "Current cluster status:"
kubectl get nodes -o wide

echo ""
echo "Verify max_pods on all nodes:"
kubectl get nodes -o json | \
  jq -r '.items[] | "\(.metadata.name): \(.status.allocatable.pods) pods"'

echo ""
echo "All pods status:"
kubectl get pods --all-namespaces -o wide
