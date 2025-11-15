#!/bin/bash

# Script to deploy services to EKS clusters
# Usage: ./5-deploy-to-clusters.sh [region]

set -e

REGION=${1:-us-east-1}

echo "Deploying services to EKS clusters..."
echo "Region: $REGION"
echo ""

SERVICES=("dawn" "day" "dusk")

for SERVICE in "${SERVICES[@]}"; do
  echo "========================================="
  echo "Deploying to ${SERVICE}-cluster..."
  echo "========================================="

  # Set kubectl context
  aws eks update-kubeconfig --name ${SERVICE}-cluster --region $REGION

  # Deploy production
  echo "Deploying ${SERVICE} production..."
  kubectl apply -f ../k8s/${SERVICE}/

  # Deploy RC
  echo "Deploying ${SERVICE} RC..."
  kubectl apply -f ../k8s/${SERVICE}-rc/

  echo ""
  echo "Waiting for deployments to be ready..."
  kubectl wait --for=condition=available --timeout=300s \
    deployment/${SERVICE} -n ${SERVICE}-ns || true
  kubectl wait --for=condition=available --timeout=300s \
    deployment/${SERVICE}-rc -n ${SERVICE}-rc-ns || true

  echo ""
  echo "Deployment status:"
  kubectl get all -n ${SERVICE}-ns
  echo ""
  kubectl get all -n ${SERVICE}-rc-ns

  echo ""
  echo "Ingress status:"
  kubectl get ingress -n ${SERVICE}-ns
  kubectl get ingress -n ${SERVICE}-rc-ns

  echo ""
  echo "✅ Deployed to ${SERVICE}-cluster!"
  echo ""
done

echo "========================================="
echo "All services deployed!"
echo "========================================="
echo ""
echo "Get ALB URLs:"
for SERVICE in "${SERVICES[@]}"; do
  echo "  kubectl get ingress -n ${SERVICE}-ns --context ${SERVICE}-cluster"
done
