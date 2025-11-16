#!/bin/bash
# Get your ECR registry URL for Pulumi config
# Run this from anywhere

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
AWS_REGION=${AWS_REGION:-us-east-1}

if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo "❌ Unable to get AWS account ID"
    echo "   Make sure AWS credentials are configured:"
    echo "   aws configure"
    exit 1
fi

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "✅ Your ECR Registry URL:"
echo ""
echo "   $ECR_REGISTRY"
echo ""
echo "📝 Update your Pulumi config with:"
echo ""
echo "   cd foundation/gitops/day"
echo "   pulumi config set image_registry $ECR_REGISTRY --stack dev"
echo "   pulumi config set image_registry $ECR_REGISTRY --stack production"
echo ""
echo "Or manually edit the YAML files to:"
echo "   day-service-app:image_registry: $ECR_REGISTRY"
