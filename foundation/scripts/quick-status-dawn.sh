#!/bin/bash

# Quick status check - minimal output for fast verification
# Usage: ./quick-status-dawn.sh [region]

REGION=${1:-us-east-1}

# Update kubeconfig silently
aws eks update-kubeconfig --name trantor --region $REGION &>/dev/null

# One-liner checks
echo "Nodes:     $(kubectl get nodes --no-headers 2>/dev/null | grep -c Ready)/$(kubectl get nodes --no-headers 2>/dev/null | wc -l) Ready"
echo "Pods:      $(kubectl get pods -n dawn-ns --no-headers 2>/dev/null | grep -c Running)/$(kubectl get pods -n dawn-ns --no-headers 2>/dev/null | wc -l) Running (prod)"
echo "RC Pods:   $(kubectl get pods -n dawn-rc-ns --no-headers 2>/dev/null | grep -c Running)/$(kubectl get pods -n dawn-rc-ns --no-headers 2>/dev/null | wc -l) Running"

# Get ALB URL
ALB_URL=$(kubectl get ingress dawn-ingress -n dawn-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

if [ -n "$ALB_URL" ]; then
    echo "ALB:       $ALB_URL"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: dawn.example.com" http://$ALB_URL/health --max-time 3 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        echo "Health:    ✓ OK ($HTTP_CODE)"
    else
        echo "Health:    ✗ FAIL ($HTTP_CODE)"
    fi
else
    echo "ALB:       (not ready)"
    echo "Health:    (skipped)"
fi

# Quick test command
echo ""
echo "Test command:"
echo "curl -H \"Host: dawn.example.com\" http://$ALB_URL/health"
