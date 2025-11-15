#!/bin/bash

# Detailed application testing
# Usage: ./test-dawn-app.sh [region]

set -e

REGION=${1:-us-east-1}

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Update kubeconfig
aws eks update-kubeconfig --name dawn-cluster --region $REGION &>/dev/null

echo "======================================"
echo "Dawn Application Test Suite"
echo "======================================"
echo ""

# Get ALB URL
ALB_URL=$(kubectl get ingress dawn-ingress -n dawn-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -z "$ALB_URL" ]; then
    echo -e "${RED}Error: No ALB URL found. Is the ingress ready?${NC}"
    exit 1
fi

echo "Testing ALB: $ALB_URL"
echo ""

# Test function
test_endpoint() {
    local endpoint=$1
    local expected_code=$2
    local host=${3:-dawn.example.com}

    echo -n "Testing $endpoint ... "

    HTTP_CODE=$(curl -s -o /tmp/response.json -w "%{http_code}" -H "Host: $host" http://$ALB_URL$endpoint --max-time 10)

    if [ "$HTTP_CODE" = "$expected_code" ]; then
        echo -e "${GREEN}✓ $HTTP_CODE${NC}"
        if [ -f /tmp/response.json ]; then
            cat /tmp/response.json | python3 -m json.tool 2>/dev/null | head -10
        fi
        return 0
    else
        echo -e "${RED}✗ $HTTP_CODE (expected $expected_code)${NC}"
        return 1
    fi
}

# Test Production
echo -e "${BLUE}=== Production Tests (dawn.example.com) ===${NC}"
echo ""

test_endpoint "/" 200
echo ""

test_endpoint "/health" 200
echo ""

test_endpoint "/info" 200
echo ""

# Test RC
echo -e "${BLUE}=== RC Tests (dawn-rc.example.com) ===${NC}"
echo ""

RC_ALB_URL=$(kubectl get ingress dawn-rc-ingress -n dawn-rc-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -n "$RC_ALB_URL" ]; then
    test_endpoint "/" 200 "dawn-rc.example.com"
    echo ""

    test_endpoint "/health" 200 "dawn-rc.example.com"
    echo ""
else
    echo "RC ALB not ready, skipping RC tests"
fi

# Load balancing test
echo -e "${BLUE}=== Load Balancing Test ===${NC}"
echo "Calling /info 10 times to verify traffic distribution:"
echo ""

for i in {1..10}; do
    HOSTNAME=$(curl -s -H "Host: dawn.example.com" http://$ALB_URL/info | grep -o '"hostname":"[^"]*"' | cut -d'"' -f4)
    echo "$i. Pod: $HOSTNAME"
done

echo ""
echo "If you see different pod names, load balancing is working!"

# Performance test
echo ""
echo -e "${BLUE}=== Performance Test ===${NC}"
echo "Testing response time (10 requests):"
echo ""

TOTAL_TIME=0
for i in {1..10}; do
    START=$(date +%s%N)
    curl -s -H "Host: dawn.example.com" http://$ALB_URL/health -o /dev/null
    END=$(date +%s%N)
    ELAPSED=$((($END - $START) / 1000000))
    echo "$i. ${ELAPSED}ms"
    TOTAL_TIME=$(($TOTAL_TIME + $ELAPSED))
done

AVG_TIME=$(($TOTAL_TIME / 10))
echo ""
echo "Average response time: ${AVG_TIME}ms"

if [ $AVG_TIME -lt 100 ]; then
    echo -e "${GREEN}✓ Excellent (<100ms)${NC}"
elif [ $AVG_TIME -lt 500 ]; then
    echo -e "${GREEN}✓ Good (<500ms)${NC}"
else
    echo -e "${RED}⚠ Slow (>500ms)${NC}"
fi

echo ""
echo "======================================"
echo "All tests completed!"
echo "======================================"
