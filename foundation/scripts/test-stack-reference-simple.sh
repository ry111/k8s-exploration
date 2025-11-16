#!/bin/bash
# Simple test to verify stack reference configuration
# Run from anywhere in the repo

set -e

echo "🔍 Testing Stack Reference Configuration"
echo "========================================="
echo ""

cd "$(dirname "$0")/../gitops/pulumi_deploy"

echo "📍 Current directory: $(pwd)"
echo ""

# Test 1: Check config value
echo "Test 1: Check kubernetes:kubeconfig config"
echo "-------------------------------------------"
pulumi stack select dev &>/dev/null

echo "Config value:"
pulumi config get kubernetes:kubeconfig || echo "  (empty or not set)"
echo ""

# Test 2: Try to read from infrastructure stack
echo "Test 2: Can we read from infrastructure stack?"
echo "-----------------------------------------------"
if pulumi stack output kubeconfig --stack ry111/service-infrastructure/day &>/dev/null; then
    echo "✅ Can read kubeconfig from ry111/service-infrastructure/day"
else
    echo "❌ Cannot read from infrastructure stack"
    echo "   Make sure infrastructure stack is deployed:"
    echo "   cd foundation/provisioning/pulumi && pulumi up --stack day"
fi
echo ""

# Test 3: Check if config file has fn::stackReference
echo "Test 3: Config file content"
echo "----------------------------"
if grep -A 2 "fn::stackReference" Pulumi.dev.yaml | grep -q "ry111/service-infrastructure/day"; then
    echo "✅ Pulumi.dev.yaml has fn::stackReference configured"
    echo "   $(grep -A 2 'fn::stackReference' Pulumi.dev.yaml | grep 'name:' | sed 's/^/   /')"
else
    echo "❌ Pulumi.dev.yaml missing fn::stackReference"
fi
echo ""

echo "📝 Summary"
echo "----------"
echo "To verify fn::stackReference works at runtime:"
echo "  cd foundation/gitops/pulumi_deploy"
echo "  pulumi preview --stack dev"
echo ""
echo "If preview works without 'stack reference' errors, it's configured correctly!"
