#!/bin/bash
#
# Grant GitHub Actions IAM Principal Access to EKS Cluster
#
# This script adds the IAM user or role used by GitHub Actions to the
# EKS cluster's aws-auth ConfigMap, granting it system:masters access.
#
# Usage:
#   ./grant-github-actions-access.sh <IAM_ARN> <CLUSTER_NAME>
#
# Example:
#   ./grant-github-actions-access.sh arn:aws:iam::123456789012:user/github-actions trantor
#

set -e

if [ $# -ne 2 ]; then
    echo "Usage: $0 <IAM_ARN> <CLUSTER_NAME>"
    echo ""
    echo "Example:"
    echo "  $0 arn:aws:iam::123456789012:user/github-actions trantor"
    echo ""
    echo "To get the IAM ARN used by GitHub Actions, check the workflow output"
    echo "from the 'Testing AWS credentials' step which runs 'aws sts get-caller-identity'"
    exit 1
fi

IAM_ARN=$1
CLUSTER_NAME=$2

echo "Adding IAM principal to EKS cluster aws-auth ConfigMap..."
echo "IAM ARN: $IAM_ARN"
echo "Cluster: $CLUSTER_NAME"
echo ""

# Update kubeconfig
echo "Updating kubeconfig..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region us-east-1

# Determine if it's a role or user
if [[ "$IAM_ARN" == *":role/"* ]]; then
    MAPPING_TYPE="role"
    echo "Detected IAM Role"
elif [[ "$IAM_ARN" == *":user/"* ]]; then
    MAPPING_TYPE="user"
    echo "Detected IAM User"
else
    echo "Error: IAM ARN must be a role or user ARN"
    exit 1
fi

# Get current aws-auth ConfigMap
echo "Fetching current aws-auth ConfigMap..."
kubectl get configmap aws-auth -n kube-system -o yaml > /tmp/aws-auth-backup.yaml
echo "Backup saved to /tmp/aws-auth-backup.yaml"

# Check if eksctl is available (easier method)
if command -v eksctl &> /dev/null; then
    echo "Using eksctl to create IAM identity mapping..."

    if [ "$MAPPING_TYPE" = "role" ]; then
        eksctl create iamidentitymapping \
            --cluster "$CLUSTER_NAME" \
            --region us-east-1 \
            --arn "$IAM_ARN" \
            --username github-actions \
            --group system:masters
    else
        eksctl create iamidentitymapping \
            --cluster "$CLUSTER_NAME" \
            --region us-east-1 \
            --arn "$IAM_ARN" \
            --username github-actions \
            --group system:masters \
            --no-duplicate-arns
    fi

    echo ""
    echo "✅ Successfully added IAM principal to cluster!"
    echo ""
    echo "The GitHub Actions workflow should now be able to authenticate to the cluster."
else
    echo ""
    echo "eksctl not found. You can:"
    echo "1. Install eksctl: https://eksctl.io/installation/"
    echo "2. Manually edit the aws-auth ConfigMap:"
    echo ""
    echo "   kubectl edit configmap aws-auth -n kube-system"
    echo ""
    echo "   Add this entry to the appropriate section (mapRoles or mapUsers):"
    echo ""
    if [ "$MAPPING_TYPE" = "role" ]; then
        cat << EOF
   mapRoles: |
     - rolearn: $IAM_ARN
       username: github-actions
       groups:
         - system:masters
EOF
    else
        cat << EOF
   mapUsers: |
     - userarn: $IAM_ARN
       username: github-actions
       groups:
         - system:masters
EOF
    fi
    echo ""
fi
