#!/bin/bash

# Troubleshooting script for when things go wrong
# Usage: ./troubleshoot-dawn.sh [region]

REGION=${1:-us-east-1}

echo "======================================"
echo "Dawn Troubleshooting Report"
echo "======================================"
echo ""

# Update kubeconfig
aws eks update-kubeconfig --name dawn-cluster --region $REGION &>/dev/null

# 1. Check for pod issues
echo "1. Checking for pod problems..."
echo ""

PROBLEM_PODS=$(kubectl get pods -n dawn-ns --no-headers 2>/dev/null | grep -v Running || echo "")

if [ -n "$PROBLEM_PODS" ]; then
    echo "Found problematic pods:"
    echo "$PROBLEM_PODS"
    echo ""

    # Get details on first problem pod
    FIRST_POD=$(echo "$PROBLEM_PODS" | head -1 | awk '{print $1}')
    echo "Details for pod: $FIRST_POD"
    echo ""
    kubectl describe pod $FIRST_POD -n dawn-ns | grep -A 20 "Events:"
    echo ""

    echo "Recent logs from pod:"
    kubectl logs $FIRST_POD -n dawn-ns --tail=20 2>/dev/null || echo "Could not retrieve logs"
else
    echo "✓ All pods running normally"
fi

echo ""
echo "======================================"

# 2. Check for pending ingress
echo "2. Checking ingress status..."
echo ""

ALB_URL=$(kubectl get ingress dawn-ingress -n dawn-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

if [ -z "$ALB_URL" ]; then
    echo "⚠ Ingress has no ALB address (still provisioning or error)"
    echo ""
    kubectl describe ingress dawn-ingress -n dawn-ns | grep -A 20 "Events:"
else
    echo "✓ Ingress has ALB: $ALB_URL"
fi

echo ""
echo "======================================"

# 3. Check ALB controller logs
echo "3. Checking ALB controller logs (last 20 lines)..."
echo ""

kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=20 2>/dev/null || echo "Could not retrieve ALB controller logs"

echo ""
echo "======================================"

# 4. Check service endpoints
echo "4. Checking service endpoints..."
echo ""

ENDPOINTS=$(kubectl get endpoints dawn-service -n dawn-ns -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)

if [ -z "$ENDPOINTS" ]; then
    echo "⚠ No endpoints for dawn-service"
    echo ""
    echo "Service details:"
    kubectl describe service dawn-service -n dawn-ns
else
    echo "✓ Service endpoints: $ENDPOINTS"
fi

echo ""
echo "======================================"

# 5. Check node resources
echo "5. Checking node resources..."
echo ""

kubectl top nodes 2>/dev/null || echo "Metrics server not available (kubectl top not working)"

echo ""
echo "======================================"

# 6. Common issues and solutions
echo "6. Common Issues & Solutions:"
echo ""
echo "Issue: Pods in ImagePullBackOff"
echo "  → Check if images exist in ECR:"
echo "    aws ecr list-images --repository-name dawn --region $REGION"
echo ""
echo "Issue: Pods in CrashLoopBackOff"
echo "  → Check pod logs:"
echo "    kubectl logs -n dawn-ns <pod-name>"
echo ""
echo "Issue: Ingress has no ADDRESS"
echo "  → Check ALB controller is running:"
echo "    kubectl get pods -n kube-system | grep aws-load-balancer"
echo "  → Check ALB controller logs:"
echo "    kubectl logs -n kube-system deployment/aws-load-balancer-controller"
echo ""
echo "Issue: curl returns empty"
echo "  → Use Host header:"
echo "    curl -H \"Host: dawn.example.com\" http://ALB_URL/health"
echo ""
echo "Issue: HPA not scaling"
echo "  → Check metrics server:"
echo "    kubectl top pods -n dawn-ns"
echo ""

echo "======================================"
echo "Report complete"
echo "======================================"
