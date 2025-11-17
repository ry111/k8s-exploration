#!/bin/bash

# Watch Dawn cluster status in real-time
# Usage: ./watch-dawn.sh [region]

REGION=${1:-us-east-1}

# Update kubeconfig
aws eks update-kubeconfig --name trantor --region $REGION &>/dev/null

echo "Watching Dawn cluster... (Press Ctrl+C to exit)"
echo ""

watch -n 2 "
echo '=== NODES ==='
kubectl get nodes 2>/dev/null || echo 'Error getting nodes'

echo ''
echo '=== PRODUCTION PODS (dawn-ns) ==='
kubectl get pods -n dawn-ns 2>/dev/null || echo 'Error getting pods'

echo ''
echo '=== RC PODS (dawn-rc-ns) ==='
kubectl get pods -n dawn-rc-ns 2>/dev/null || echo 'Error getting pods'

echo ''
echo '=== INGRESS ==='
kubectl get ingress -n dawn-ns 2>/dev/null || echo 'Error getting ingress'

echo ''
echo '=== HPA ==='
kubectl get hpa -n dawn-ns 2>/dev/null || echo 'Error getting HPA'
"
