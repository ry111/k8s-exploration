#!/bin/bash

# Script to apply Kubernetes manifests for a service
# Usage: ./apply-service.sh <service-name> [environment] [cluster-name] [region]
# Examples:
#   ./apply-service.sh dawn prod trantor us-east-1    # Deploy dawn prod to trantor
#   ./apply-service.sh dawn rc trantor us-east-1      # Deploy dawn rc to trantor
#   ./apply-service.sh dawn all trantor us-east-1     # Deploy dawn prod + rc to trantor
#   ./apply-service.sh day                            # Deploy day prod + rc to current context

set -e

SERVICE_NAME=${1}
ENVIRONMENT=${2:-all}
CLUSTER_NAME=${3}
REGION=${4:-us-east-1}

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

if [ -z "$SERVICE_NAME" ]; then
  echo "Error: Service name is required"
  echo ""
  echo "Usage: $0 <service-name> [environment] [cluster-name] [region]"
  echo ""
  echo "Arguments:"
  echo "  service-name    Required. Service to deploy: dawn, day, or dusk"
  echo "  environment     Optional. Environment: prod, rc, or all (default: all)"
  echo "  cluster-name    Optional. Target cluster name (uses current context if not specified)"
  echo "  region          Optional. AWS region (default: us-east-1)"
  echo ""
  echo "Examples:"
  echo "  $0 dawn prod trantor us-east-1    # Deploy dawn prod to trantor"
  echo "  $0 dawn rc trantor us-east-1      # Deploy dawn rc to trantor"
  echo "  $0 dawn all trantor us-east-1     # Deploy dawn prod + rc to trantor"
  echo "  $0 day                             # Deploy day prod + rc to current context"
  exit 1
fi

# Validate service name
if [[ ! "$SERVICE_NAME" =~ ^(dawn|day|dusk)$ ]]; then
  echo "Error: Invalid service name: $SERVICE_NAME"
  echo "Valid service names: dawn, day, dusk"
  exit 1
fi

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(prod|rc|all)$ ]]; then
  echo "Error: Invalid environment: $ENVIRONMENT"
  echo "Valid environments: prod, rc, all"
  exit 1
fi

# Get AWS account ID for ECR
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Applying Kubernetes Manifests${NC}"
echo -e "${BLUE}=========================================${NC}"
echo "Service: $SERVICE_NAME"
echo "Environment: $ENVIRONMENT"
echo "ECR Registry: $ECR_REGISTRY"
if [ -n "$CLUSTER_NAME" ]; then
  echo "Target cluster: $CLUSTER_NAME"
else
  echo "Target cluster: (current kubectl context)"
fi
echo ""

# Set kubectl context if cluster name provided
if [ -n "$CLUSTER_NAME" ]; then
  echo -e "${YELLOW}Setting kubectl context to cluster: $CLUSTER_NAME${NC}"
  aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
  echo ""
fi

# Function to apply manifests for a specific environment
apply_environment() {
  local env=$1
  local manifest_dir="foundation/k8s/${SERVICE_NAME}/${env}"

  if [ ! -d "$manifest_dir" ]; then
    echo -e "${YELLOW}Warning: Directory not found: $manifest_dir${NC}"
    return 1
  fi

  echo -e "${GREEN}Applying manifests for ${SERVICE_NAME} ${env}...${NC}"

  # Create temporary directory for manifests with updated image URLs
  TEMP_DIR=$(mktemp -d)

  # Copy manifests to temp directory
  cp -r "$manifest_dir" "$TEMP_DIR/"

  # Update image URLs in deployment.yaml (macOS and Linux compatible)
  if [ -f "$TEMP_DIR/$env/deployment.yaml" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      # macOS
      sed -i '' "s|image: ${SERVICE_NAME}:latest|image: ${ECR_REGISTRY}/${SERVICE_NAME}:latest|g" "$TEMP_DIR/$env/deployment.yaml"
      sed -i '' "s|image: ${SERVICE_NAME}:rc|image: ${ECR_REGISTRY}/${SERVICE_NAME}:rc|g" "$TEMP_DIR/$env/deployment.yaml"
    else
      # Linux
      sed -i "s|image: ${SERVICE_NAME}:latest|image: ${ECR_REGISTRY}/${SERVICE_NAME}:latest|g" "$TEMP_DIR/$env/deployment.yaml"
      sed -i "s|image: ${SERVICE_NAME}:rc|image: ${ECR_REGISTRY}/${SERVICE_NAME}:rc|g" "$TEMP_DIR/$env/deployment.yaml"
    fi
  fi

  # Apply all manifests in the environment directory
  kubectl apply -f "$TEMP_DIR/$env/"

  # Cleanup temp directory
  rm -rf "$TEMP_DIR"

  echo ""
}

# Apply manifests based on environment argument
if [ "$ENVIRONMENT" = "all" ]; then
  apply_environment "prod"
  apply_environment "rc"
elif [ "$ENVIRONMENT" = "prod" ]; then
  apply_environment "prod"
elif [ "$ENVIRONMENT" = "rc" ]; then
  apply_environment "rc"
fi

echo -e "${GREEN}Waiting for deployments to be ready...${NC}"

# Wait for prod deployment if applicable
if [[ "$ENVIRONMENT" =~ ^(prod|all)$ ]]; then
  kubectl wait --for=condition=available --timeout=300s \
    deployment/${SERVICE_NAME} -n ${SERVICE_NAME}-ns 2>/dev/null || \
    echo -e "${YELLOW}⚠️  Production deployment may still be in progress${NC}"
fi

# Wait for rc deployment if applicable
if [[ "$ENVIRONMENT" =~ ^(rc|all)$ ]]; then
  kubectl wait --for=condition=available --timeout=300s \
    deployment/${SERVICE_NAME}-rc -n ${SERVICE_NAME}-rc-ns 2>/dev/null || \
    echo -e "${YELLOW}⚠️  RC deployment may still be in progress${NC}"
fi

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Deployment Status${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Show status based on environment
if [[ "$ENVIRONMENT" =~ ^(prod|all)$ ]]; then
  echo -e "${GREEN}Production (${SERVICE_NAME}-ns):${NC}"
  kubectl get all -n ${SERVICE_NAME}-ns
  echo ""
fi

if [[ "$ENVIRONMENT" =~ ^(rc|all)$ ]]; then
  echo -e "${GREEN}RC (${SERVICE_NAME}-rc-ns):${NC}"
  kubectl get all -n ${SERVICE_NAME}-rc-ns
  echo ""
fi

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}✅ Manifests applied successfully!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "Next steps:"
echo ""
echo "Get service URLs:"
if [[ "$ENVIRONMENT" =~ ^(prod|all)$ ]]; then
  echo "  kubectl get ingress -n ${SERVICE_NAME}-ns"
fi
if [[ "$ENVIRONMENT" =~ ^(rc|all)$ ]]; then
  echo "  kubectl get ingress -n ${SERVICE_NAME}-rc-ns"
fi
echo ""
echo "Test service:"
if [[ "$ENVIRONMENT" =~ ^(prod|all)$ ]]; then
  echo "  curl http://\$(kubectl get ingress ${SERVICE_NAME}-ingress -n ${SERVICE_NAME}-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/health"
fi
echo ""
