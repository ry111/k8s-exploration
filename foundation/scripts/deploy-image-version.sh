#!/bin/bash
set -e

# Script to deploy a specific image version to a Pulumi stack
# Usage: ./deploy-image-version.sh <stack> <image-tag>
# Example: ./deploy-image-version.sh dev abc123def456

STACK=${1:-dev}
IMAGE_TAG=${2}

if [ -z "$IMAGE_TAG" ]; then
  echo "Error: Image tag required"
  echo "Usage: $0 <stack> <image-tag>"
  echo "Example: $0 dev abc123def456"
  exit 1
fi

echo "🚀 Deploying Day Service"
echo "   Stack: $STACK"
echo "   Image Tag: $IMAGE_TAG"
echo ""

cd foundation/applications/day-service/pulumi

# Update the image tag
pulumi stack select $STACK
pulumi config set image_tag $IMAGE_TAG

# Preview changes
echo "📋 Preview:"
pulumi preview

# Prompt for confirmation
read -p "Deploy to $STACK? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cancelled"
  exit 0
fi

# Deploy
echo "🚢 Deploying..."
pulumi up --yes

# Show outputs
echo ""
echo "✅ Deployment complete!"
pulumi stack output
