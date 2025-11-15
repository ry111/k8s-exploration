#!/bin/bash

# Quick health check for Dawn cluster and application
# Usage: ./health-check-dawn.sh [region]

set -e

REGION=${1:-us-east-1}
CLUSTER_NAME="dawn-cluster"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================"
echo "Dawn Cluster Health Check"
echo "Region: $REGION"
echo "======================================"
echo ""

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
    fi
}

# 1. Check cluster exists
echo "1. Checking cluster connectivity..."
if aws eks describe-cluster --name $CLUSTER_NAME --region $REGION &>/dev/null; then
    print_status 0 "Cluster $CLUSTER_NAME exists"
    aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION &>/dev/null
else
    print_status 1 "Cluster $CLUSTER_NAME not found"
    exit 1
fi
echo ""

# 2. Check nodes
echo "2. Checking nodes..."
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c Ready || echo 0)

if [ "$NODE_COUNT" -gt 0 ] && [ "$NODE_COUNT" -eq "$READY_NODES" ]; then
    print_status 0 "$READY_NODES/$NODE_COUNT nodes ready"
    kubectl get nodes --no-headers | while read line; do
        echo "  - $line"
    done
else
    print_status 1 "Only $READY_NODES/$NODE_COUNT nodes ready"
fi
echo ""

# 3. Check ALB controller
echo "3. Checking AWS Load Balancer Controller..."
ALB_READY=$(kubectl get deployment -n kube-system aws-load-balancer-controller --no-headers 2>/dev/null | awk '{print $2}')
if [ "$ALB_READY" = "2/2" ]; then
    print_status 0 "ALB Controller running ($ALB_READY)"
else
    print_status 1 "ALB Controller not ready ($ALB_READY)"
fi
echo ""

# 4. Check Dawn production pods
echo "4. Checking Dawn production pods..."
DAWN_PODS=$(kubectl get pods -n dawn-ns --no-headers 2>/dev/null | wc -l)
DAWN_RUNNING=$(kubectl get pods -n dawn-ns --no-headers 2>/dev/null | grep -c Running || echo 0)

if [ "$DAWN_PODS" -gt 0 ] && [ "$DAWN_PODS" -eq "$DAWN_RUNNING" ]; then
    print_status 0 "$DAWN_RUNNING/$DAWN_PODS pods running"
    kubectl get pods -n dawn-ns --no-headers | while read line; do
        echo "  - $line"
    done
else
    print_status 1 "Only $DAWN_RUNNING/$DAWN_PODS pods running"
    kubectl get pods -n dawn-ns
fi
echo ""

# 5. Check Dawn RC pods
echo "5. Checking Dawn RC pods..."
RC_PODS=$(kubectl get pods -n dawn-rc-ns --no-headers 2>/dev/null | wc -l)
RC_RUNNING=$(kubectl get pods -n dawn-rc-ns --no-headers 2>/dev/null | grep -c Running || echo 0)

if [ "$RC_PODS" -gt 0 ] && [ "$RC_PODS" -eq "$RC_RUNNING" ]; then
    print_status 0 "$RC_RUNNING/$RC_PODS RC pods running"
else
    print_status 1 "Only $RC_RUNNING/$RC_PODS RC pods running"
fi
echo ""

# 6. Check service endpoints
echo "6. Checking service endpoints..."
DAWN_ENDPOINTS=$(kubectl get endpoints dawn-service -n dawn-ns -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
if [ "$DAWN_ENDPOINTS" -gt 0 ]; then
    print_status 0 "dawn-service has $DAWN_ENDPOINTS endpoints"
else
    print_status 1 "dawn-service has no endpoints"
fi

RC_ENDPOINTS=$(kubectl get endpoints dawn-rc-service -n dawn-rc-ns -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
if [ "$RC_ENDPOINTS" -gt 0 ]; then
    print_status 0 "dawn-rc-service has $RC_ENDPOINTS endpoints"
else
    print_status 1 "dawn-rc-service has no endpoints"
fi
echo ""

# 7. Check ingress
echo "7. Checking ingress resources..."
DAWN_ALB=$(kubectl get ingress dawn-ingress -n dawn-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ -n "$DAWN_ALB" ]; then
    print_status 0 "Production ingress has ALB"
    echo "  URL: http://$DAWN_ALB"
else
    print_status 1 "Production ingress has no ALB (still provisioning?)"
fi

RC_ALB=$(kubectl get ingress dawn-rc-ingress -n dawn-rc-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ -n "$RC_ALB" ]; then
    print_status 0 "RC ingress has ALB"
    echo "  URL: http://$RC_ALB"
else
    print_status 1 "RC ingress has no ALB"
fi
echo ""

# 8. Test application endpoints
echo "8. Testing application health..."
if [ -n "$DAWN_ALB" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: dawn.example.com" http://$DAWN_ALB/health --max-time 5)
    if [ "$HTTP_CODE" = "200" ]; then
        print_status 0 "Production /health endpoint responding ($HTTP_CODE)"
        RESPONSE=$(curl -s -H "Host: dawn.example.com" http://$DAWN_ALB/health)
        echo "  Response: $RESPONSE"
    else
        print_status 1 "Production /health endpoint failed ($HTTP_CODE)"
    fi
else
    echo -e "${YELLOW}⊘${NC} Skipping health check (no ALB URL)"
fi

if [ -n "$RC_ALB" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: dawn-rc.example.com" http://$RC_ALB/health --max-time 5)
    if [ "$HTTP_CODE" = "200" ]; then
        print_status 0 "RC /health endpoint responding ($HTTP_CODE)"
    else
        print_status 1 "RC /health endpoint failed ($HTTP_CODE)"
    fi
fi
echo ""

# 9. Check HPA status
echo "9. Checking HPA (autoscaling)..."
DAWN_HPA=$(kubectl get hpa dawn-hpa -n dawn-ns --no-headers 2>/dev/null)
if [ -n "$DAWN_HPA" ]; then
    print_status 0 "Production HPA configured"
    echo "  $DAWN_HPA"
else
    print_status 1 "Production HPA not found"
fi

RC_HPA=$(kubectl get hpa dawn-rc-hpa -n dawn-rc-ns --no-headers 2>/dev/null)
if [ -n "$RC_HPA" ]; then
    print_status 0 "RC HPA configured"
    echo "  $RC_HPA"
else
    print_status 1 "RC HPA not found"
fi
echo ""

# 10. Summary
echo "======================================"
echo "Health Check Summary"
echo "======================================"

TOTAL_CHECKS=10
PASSED=0

# Count passed checks (simplified - could be more sophisticated)
[ "$READY_NODES" -eq "$NODE_COUNT" ] && ((PASSED++))
[ "$ALB_READY" = "2/2" ] && ((PASSED++))
[ "$DAWN_RUNNING" -eq "$DAWN_PODS" ] && ((PASSED++))
[ "$RC_RUNNING" -eq "$RC_PODS" ] && ((PASSED++))
[ "$DAWN_ENDPOINTS" -gt 0 ] && ((PASSED++))
[ "$RC_ENDPOINTS" -gt 0 ] && ((PASSED++))
[ -n "$DAWN_ALB" ] && ((PASSED++))
[ -n "$RC_ALB" ] && ((PASSED++))
[ -n "$DAWN_HPA" ] && ((PASSED++))
[ -n "$RC_HPA" ] && ((PASSED++))

echo "Checks passed: $PASSED/$TOTAL_CHECKS"

if [ $PASSED -eq $TOTAL_CHECKS ]; then
    echo -e "${GREEN}All systems operational!${NC}"
    exit 0
elif [ $PASSED -gt $((TOTAL_CHECKS / 2)) ]; then
    echo -e "${YELLOW}Some issues detected${NC}"
    exit 1
else
    echo -e "${RED}Critical issues detected${NC}"
    exit 2
fi
