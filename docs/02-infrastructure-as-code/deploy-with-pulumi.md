# Deploy Terminus Cluster with Pulumi

This guide walks you through deploying the **Terminus cluster** using Pulumi Infrastructure as Code.

## Prerequisites

1. **Pulumi CLI installed** - See [pulumi-setup.md](pulumi-setup.md) for installation
2. **Pulumi login completed** - Either Pulumi Cloud or S3 backend
3. **AWS credentials configured** - Already set up for CI/CD

## Quick Start

### 1. Navigate to Pulumi directory

```bash
cd foundation/provisioning/pulumi
```

### 2. Set up Python environment

```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### 3. Select the Terminus stack

```bash
pulumi stack select production
# If stack doesn't exist yet:
# pulumi stack init production
```

The stack configuration is already defined in `Pulumi.production.yaml`:
- **Cluster name**: terminus
- **VPC CIDR**: 10.2.0.0/16 (different from Trantor's 10.0.0.0/16)
- **Nodes**: 2 desired, 1-4 range
- **Instance type**: t3.small spot instances

### 4. Preview infrastructure changes

```bash
pulumi preview
```

This shows what will be created:
- ✅ VPC with 10.2.0.0/16 CIDR
- ✅ 2 public subnets (10.2.1.0/24, 10.2.2.0/24)
- ✅ Internet Gateway and route table
- ✅ EKS cluster named "terminus"
- ✅ Managed node group with spot instances
- ✅ IAM roles for ALB controller
- ✅ ALB controller installed via Helm

**Expected resources**: ~20 resources will be created

### 5. Deploy the cluster

```bash
pulumi up
```

Review the preview, type "yes" to proceed.

**Deployment time**: ~10-15 minutes

### 6. Get cluster information

```bash
# View all outputs
pulumi stack output

# Get kubeconfig
pulumi stack output kubeconfig --show-secrets > day-kubeconfig.yaml
export KUBECONFIG=$(pwd)/day-kubeconfig.yaml

# Verify cluster is running
kubectl get nodes
kubectl get pods -A
```

## What Gets Created

| Resource | Name | Details |
|----------|------|---------|
| **VPC** | terminus-vpc | 10.2.0.0/16 CIDR |
| **Subnets** | terminus-public-subnet-1/2 | us-east-1a, us-east-1b |
| **EKS Cluster** | terminus | v1.28+ |
| **Node Group** | Managed spot instances | 2x t3.small (1-4 range) |
| **IAM Role** | terminus-alb-controller-role | For ALB controller IRSA |
| **ALB Controller** | Helm release | In kube-system namespace |

## Deploy Day Application

After the cluster is created, deploy the Day service:

### Option 1: Using Existing Scripts

```bash
# Update kubeconfig
aws eks update-kubeconfig --name terminus --region us-east-1

# Apply manifests
kubectl apply -f foundation/gitops/manual_deploy/day/prod/namespace.yaml
kubectl apply -f foundation/gitops/manual_deploy/day/prod/configmap.yaml
kubectl apply -f foundation/gitops/manual_deploy/day/prod/deployment.yaml
kubectl apply -f foundation/gitops/manual_deploy/day/prod/service.yaml
kubectl apply -f foundation/gitops/manual_deploy/day/prod/hpa.yaml
kubectl apply -f foundation/gitops/manual_deploy/day/prod/ingress.yaml
```

### Option 2: Create Deployment Script

Example deployment script for Terminus cluster:

```bash
#!/bin/bash
CLUSTER_NAME="terminus"
REGION="us-east-1"

aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION
# Deploy your services (see gitops/ folder for deployment scripts)
```

## Verify Deployment

```bash
# Check pods are running
kubectl get pods -n day-ns

# Check ingress provisioned ALB
kubectl get ingress -n day-ns

# Get ALB URL
kubectl get ingress day-ingress -n day-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Test the service (replace ALB_URL with actual URL)
curl -H "Host: day.example.com" http://ALB_URL/health
```

Expected response:
```json
{
  "status": "healthy",
  "service": "Day",
  "timestamp": "2025-11-15T12:00:00.000000"
}
```

## Multi-Cluster Management

You can switch between clusters:

```bash
# Work with Trantor cluster (manually provisioned)
aws eks update-kubeconfig --name trantor --region us-east-1
kubectl get pods -A

# Work with Terminus cluster (Pulumi-managed)
pulumi stack select production
aws eks update-kubeconfig --name terminus --region us-east-1
kubectl get pods -A
```

Or use kubeconfig context switching:
```bash
kubectl config get-contexts
kubectl config use-context arn:aws:eks:us-east-1:612974049499:cluster/terminus
```

## Update Infrastructure

To change cluster configuration:

```bash
# Edit Pulumi.production.yaml
# For example, increase max nodes from 4 to 6:
vim Pulumi.production.yaml
# Change: foundation-provisioning:max_nodes: "6"

# Preview changes
pulumi preview

# Apply changes
pulumi up
```

Changes are applied **in-place** without recreating the cluster.

## Destroy Cluster

When done experimenting:

```bash
pulumi stack select production
pulumi destroy
```

⚠️ **WARNING**: This deletes all resources including the cluster!

Type the stack name to confirm.

## CI/CD Integration

The same GitHub Actions workflows work for Terminus cluster:

- **pulumi-preview.yml**: Runs on PRs to preview changes
- **pulumi-up.yml**: Deploys on merge to main

Simply change code and create PR - infrastructure updates automatically.

## Comparison: Manual vs Pulumi Provisioning

| Aspect | Trantor (Manual) | Terminus (Pulumi) |
|--------|------------------|-------------------|
| **Creation** | eksctl script | `pulumi up` |
| **VPC** | Auto-created (10.0.0.0/16) | Explicit (10.2.0.0/16) |
| **Updates** | Delete/recreate | In-place updates |
| **State** | None | Pulumi state |
| **Preview** | ❌ | ✅ |
| **Repeatable** | ⚠️ Requires scripts | ✅ Codified as IaC |

## Next Steps

1. ✅ **Deploy Terminus cluster** - Run `pulumi up`
2. ⏭️ **Deploy applications** - Deploy services to Terminus (see gitops/)
3. ⏭️ **Set up CI/CD** - Update GitHub Actions for automated deployments
4. ⏭️ **Add ArgoCD** - Automate application deployment
5. ⏭️ **Scale infrastructure** - Adjust cluster sizing as needed

## Troubleshooting

### Preview shows no resources
```bash
# Verify stack is selected
pulumi stack ls
pulumi stack select production
```

### AWS authentication errors
```bash
aws sts get-caller-identity
# Re-configure if needed
aws configure
```

### Cluster creation fails
- Check AWS account limits (EKS clusters, VPCs, EIPs)
- Verify region has t3.small spot availability
- Check CloudWatch Logs for eksctl errors

### Can't connect to cluster
```bash
# Update kubeconfig
aws eks update-kubeconfig --name terminus --region us-east-1

# Verify
kubectl get svc
```

## Support

- Main setup guide: [pulumi-setup.md](pulumi-setup.md)
- Infrastructure Pulumi README: [foundation/provisioning/pulumi/README.md](../../foundation/provisioning/pulumi/README.md)
- Pulumi docs: https://www.pulumi.com/docs/
