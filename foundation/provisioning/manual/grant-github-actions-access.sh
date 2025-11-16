#!/bin/bash
#
# Grant GitHub Actions IAM Principal Access to EKS Cluster
#
# This script uses the EKS Access Entry API (recommended for EKS 1.23+).
# This is the modern approach that replaces the legacy aws-auth ConfigMap method.
#
# Usage:
#   ./grant-github-actions-access.sh <IAM_ARN> <CLUSTER_NAME>
#
# Example:
#   ./grant-github-actions-access.sh arn:aws:iam::612974049499:user/github-actions trantor
#

set -e

if [ $# -ne 2 ]; then
    echo "Usage: $0 <IAM_ARN> <CLUSTER_NAME>"
    echo ""
    echo "Example:"
    echo "  $0 arn:aws:iam::612974049499:user/github-actions trantor"
    echo ""
    echo "To get the IAM ARN used by GitHub Actions, check the workflow output"
    echo "from the 'Testing AWS credentials' step which runs 'aws sts get-caller-identity'"
    exit 1
fi

IAM_ARN=$1
CLUSTER_NAME=$2
REGION=${AWS_REGION:-us-east-1}

echo "==========================================================="
echo "Grant GitHub Actions Access to EKS Cluster"
echo "==========================================================="
echo ""
echo "IAM ARN: $IAM_ARN"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Method: EKS Access Entry API (modern approach)"
echo ""

# Check if access entry already exists
echo "Checking if access entry already exists..."
if aws eks describe-access-entry \
    --cluster-name "$CLUSTER_NAME" \
    --principal-arn "$IAM_ARN" \
    --region "$REGION" &>/dev/null; then
    echo ""
    echo "⚠️  Access entry already exists for this IAM principal"
    echo ""
    read -p "Do you want to delete and recreate it? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing access entry..."
        aws eks delete-access-entry \
            --cluster-name "$CLUSTER_NAME" \
            --principal-arn "$IAM_ARN" \
            --region "$REGION"
        echo "Waiting for deletion to complete..."
        sleep 5
    else
        echo "Aborting."
        exit 0
    fi
fi

# Create access entry
echo "Creating access entry..."
aws eks create-access-entry \
    --cluster-name "$CLUSTER_NAME" \
    --principal-arn "$IAM_ARN" \
    --type STANDARD \
    --region "$REGION"

echo ""
echo "Access entry created successfully!"
echo ""

# Associate access policy
echo "Associating cluster admin policy..."
aws eks associate-access-policy \
    --cluster-name "$CLUSTER_NAME" \
    --principal-arn "$IAM_ARN" \
    --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
    --access-scope type=cluster \
    --region "$REGION"

echo ""
echo "✅ Successfully granted cluster admin access to IAM principal!"
echo ""
echo "The GitHub Actions workflow should now be able to authenticate to the cluster."
echo ""
echo "To verify, you can run:"
echo "  aws eks list-access-entries --cluster-name $CLUSTER_NAME --region $REGION"
echo ""
