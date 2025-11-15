# Deploy Day Cluster with Pulumi

This guide walks you through deploying the **Day cluster** using Pulumi Infrastructure as Code.

## Prerequisites

1. **Pulumi CLI installed** - See [pulumi-setup.md](pulumi-setup.md) for installation
2. **Pulumi login completed** - Either Pulumi Cloud or S3 backend
3. **AWS credentials configured** - Already set up for CI/CD

## Quick Start

### 1. Navigate to Pulumi directory

```bash
cd foundation/infrastructure/pulumi
```

### 2. Set up Python environment

```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### 3. Select the Day stack

```bash
pulumi stack select day
# If stack doesn't exist yet:
# pulumi stack init day
```

The stack configuration is already defined in `Pulumi.day.yaml`:
- **Service**: day
- **VPC CIDR**: 10.1.0.0/16 (different from Dawn's 10.0.0.0/16)
- **Cluster name**: day-cluster
- **Nodes**: 2 desired, 1-3 range
- **Instance type**: t3.small spot instances

### 4. Preview infrastructure changes

```bash
pulumi preview
```

This shows what will be created:
- ✅ VPC with 10.1.0.0/16 CIDR
- ✅ 2 public subnets (10.1.1.0/24, 10.1.2.0/24)
- ✅ Internet Gateway and route table
- ✅ EKS cluster named "day-cluster"
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
| **VPC** | day-vpc | 10.1.0.0/16 CIDR |
| **Subnets** | day-public-subnet-1/2 | us-east-1a, us-east-1b |
| **EKS Cluster** | day-cluster | v1.28+ |
| **Node Group** | Managed spot instances | 2x t3.small (1-3 range) |
| **IAM Role** | day-alb-controller-role | For ALB controller IRSA |
| **ALB Controller** | Helm release | In kube-system namespace |

## Deploy Day Application

After the cluster is created, deploy the Day service:

### Option 1: Using Existing Scripts

```bash
# Update kubeconfig
aws eks update-kubeconfig --name day-cluster --region us-east-1

# Apply manifests
kubectl apply -f foundation/k8s/day/namespace.yaml
kubectl apply -f foundation/k8s/day/configmap.yaml
kubectl apply -f foundation/k8s/day/deployment.yaml
kubectl apply -f foundation/k8s/day/service.yaml
kubectl apply -f foundation/k8s/day/hpa.yaml
kubectl apply -f foundation/k8s/day/ingress.yaml
```

### Option 2: Create Deployment Script

Similar to `deploy-dawn.sh`, but for Day cluster:

```bash
#!/bin/bash
CLUSTER_NAME="day-cluster"
REGION="us-east-1"
ECR_REGISTRY="612974049499.dkr.ecr.us-east-1.amazonaws.com"

aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION
kubectl apply -f foundation/k8s/day/
# ... update image references to ECR
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

## Cost Estimate

Same as Dawn cluster:
- **EKS control plane**: ~$73/month
- **2x t3.small spot nodes**: ~$9/month each (~$18 total)
- **ALB**: ~$21-26/month
- **Data transfer**: ~$1-3/month

**Total: ~$113-123/month**

## Multi-Cluster Management

You can switch between clusters:

```bash
# Work with Dawn cluster
pulumi stack select dev
aws eks update-kubeconfig --name dawn-cluster --region us-east-1
kubectl get pods -A

# Work with Day cluster
pulumi stack select day
aws eks update-kubeconfig --name day-cluster --region us-east-1
kubectl get pods -A
```

Or use kubeconfig context switching:
```bash
kubectl config get-contexts
kubectl config use-context arn:aws:eks:us-east-1:612974049499:cluster/day-cluster
```

## Update Infrastructure

To change cluster configuration:

```bash
# Edit Pulumi.day.yaml
# For example, increase max nodes from 3 to 5:
vim Pulumi.day.yaml
# Change: service-infrastructure:max_nodes: "5"

# Preview changes
pulumi preview

# Apply changes
pulumi up
```

Changes are applied **in-place** without recreating the cluster.

## Destroy Cluster

When done experimenting:

```bash
pulumi stack select day
pulumi destroy
```

⚠️ **WARNING**: This deletes all resources including the cluster!

Type the stack name "day" to confirm.

## CI/CD Integration

The same GitHub Actions workflows work for Day cluster:

- **pulumi-preview.yml**: Runs on PRs to preview changes
- **pulumi-up.yml**: Deploys on merge to main

Simply change code and create PR - infrastructure updates automatically.

## Comparison with Dawn Cluster

| Aspect | Dawn (Manual) | Day (Pulumi) |
|--------|---------------|--------------|
| **Creation** | eksctl script | `pulumi up` |
| **VPC** | Auto-created | Explicit (10.1.0.0/16) |
| **Updates** | Delete/recreate | In-place updates |
| **State** | None | Pulumi state |
| **Preview** | ❌ | ✅ |
| **Repeatable** | ⚠️ Requires scripts | ✅ Fully declarative |

## Next Steps

1. ✅ **Deploy Day cluster** - Run `pulumi up`
2. ⏭️ **Deploy Day app** - Apply K8s manifests
3. ⏭️ **Set up CI for Day** - Update GitHub Actions for Day service
4. ⏭️ **Add ArgoCD** - Automate application deployment
5. ⏭️ **Deploy Dusk cluster** - Use Pulumi again

## Troubleshooting

### Preview shows no resources
```bash
# Verify stack is selected
pulumi stack ls
pulumi stack select day
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
aws eks update-kubeconfig --name day-cluster --region us-east-1

# Verify
kubectl get svc
```

## Support

- Main setup guide: [pulumi-setup.md](pulumi-setup.md)
- Multi-cluster README: [pulumi/README.md](pulumi/README.md:1)
- Pulumi docs: https://www.pulumi.com/docs/
