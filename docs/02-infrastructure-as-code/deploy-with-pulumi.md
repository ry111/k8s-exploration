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
pulumi stack output kubeconfig --show-secrets > terminus-kubeconfig.yaml
export KUBECONFIG=$(pwd)/terminus-kubeconfig.yaml

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

## Verify Infrastructure

After deployment, verify the infrastructure components:

```bash
# Check nodes are ready
kubectl get nodes

# Verify ALB controller is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check cluster info
kubectl cluster-info

# View all namespaces
kubectl get namespaces
```

Expected output:
- 2 nodes in Ready state
- ALB controller pods running in kube-system namespace
- Cluster accessible via kubectl

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
2. ⏭️ **Deploy applications** - Use Pulumi application deployment for services (see [two-tier-architecture.md](two-tier-architecture.md))
3. ⏭️ **Set up CI/CD** - GitHub Actions for automated infrastructure updates
4. ⏭️ **Scale infrastructure** - Adjust cluster sizing as needed
5. ⏭️ **Add monitoring** - Set up CloudWatch, Prometheus, or other monitoring tools

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
- Check CloudWatch Logs for EKS cluster errors
- Ensure IAM permissions are sufficient

### Can't connect to cluster
```bash
# Update kubeconfig
aws eks update-kubeconfig --name terminus --region us-east-1

# Verify
kubectl get svc
```

### ALB controller not running
```bash
# Check controller pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

## Support

- Main setup guide: [pulumi-setup.md](pulumi-setup.md)
- Infrastructure Pulumi README: [foundation/provisioning/pulumi/README.md](../../foundation/provisioning/pulumi/README.md)
- Architecture overview: [two-tier-architecture.md](two-tier-architecture.md)
- Pulumi docs: https://www.pulumi.com/docs/
