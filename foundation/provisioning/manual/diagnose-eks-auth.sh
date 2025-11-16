#!/bin/bash
#
# Diagnose EKS Authentication Issues
#
# This script helps diagnose why GitHub Actions can't authenticate to EKS
#
# Usage:
#   ./diagnose-eks-auth.sh <CLUSTER_NAME> <IAM_ARN>
#

set -e

CLUSTER_NAME=${1:-trantor}
IAM_ARN=${2}
REGION=${AWS_REGION:-us-east-1}

echo "==========================================================="
echo "EKS Authentication Diagnostics"
echo "==========================================================="
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
if [ -n "$IAM_ARN" ]; then
    echo "IAM ARN to check: $IAM_ARN"
fi
echo ""

# 1. Check current IAM identity
echo "1. Current IAM Identity:"
echo "-----------------------------------------------------------"
aws sts get-caller-identity
echo ""

# 2. Check cluster exists and is accessible
echo "2. Cluster Status:"
echo "-----------------------------------------------------------"
aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.{Name:name,Status:status,Endpoint:endpoint,Version:version}' --output table
echo ""

# 3. Update kubeconfig
echo "3. Updating kubeconfig:"
echo "-----------------------------------------------------------"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
echo ""

# 4. Check aws-auth ConfigMap
echo "4. Current aws-auth ConfigMap:"
echo "-----------------------------------------------------------"
echo "Checking for IAM principals with cluster access..."
kubectl get configmap aws-auth -n kube-system -o yaml || echo "⚠️  Could not retrieve aws-auth ConfigMap (this might be the issue!)"
echo ""

# 5. Check access entries (new method)
echo "5. EKS Access Entries:"
echo "-----------------------------------------------------------"
echo "Listing all access entries..."
aws eks list-access-entries --cluster-name "$CLUSTER_NAME" --region "$REGION" || echo "Access entries not available (cluster may not support them)"
echo ""

if [ -n "$IAM_ARN" ]; then
    echo "Checking if $IAM_ARN has an access entry..."
    aws eks describe-access-entry --cluster-name "$CLUSTER_NAME" --principal-arn "$IAM_ARN" --region "$REGION" || echo "No access entry found for this IAM principal"
    echo ""
fi

# 6. Test kubectl access
echo "6. Testing kubectl Access:"
echo "-----------------------------------------------------------"
echo "Testing 'kubectl cluster-info'..."
if kubectl cluster-info; then
    echo "✅ kubectl access working!"
else
    echo "❌ kubectl access FAILED"
fi
echo ""

echo "Testing 'kubectl auth can-i get pods --all-namespaces'..."
if kubectl auth can-i get pods --all-namespaces; then
    echo "✅ Has permission to list pods"
else
    echo "❌ Does NOT have permission to list pods"
fi
echo ""

# 7. Test EKS token generation
echo "7. Testing EKS Token Generation:"
echo "-----------------------------------------------------------"
echo "Running: aws eks get-token --cluster-name $CLUSTER_NAME"
if aws eks get-token --cluster-name "$CLUSTER_NAME" --region "$REGION" >/dev/null; then
    echo "✅ EKS token generation successful"
else
    echo "❌ EKS token generation FAILED"
fi
echo ""

# 8. Summary
echo "==========================================================="
echo "Summary"
echo "==========================================================="
echo ""
if [ -n "$IAM_ARN" ]; then
    echo "To grant access to $IAM_ARN, use ONE of these methods:"
    echo ""
    echo "Method 1 (Recommended - Access Entries):"
    echo "  ./grant-github-actions-access-v2.sh '$IAM_ARN' '$CLUSTER_NAME'"
    echo ""
    echo "Method 2 (Legacy - aws-auth ConfigMap):"
    echo "  ./grant-github-actions-access.sh '$IAM_ARN' '$CLUSTER_NAME'"
    echo ""
else
    echo "Run this script with the IAM ARN to get specific fix commands:"
    echo "  ./diagnose-eks-auth.sh $CLUSTER_NAME arn:aws:iam::ACCOUNT:user/USERNAME"
    echo ""
fi
