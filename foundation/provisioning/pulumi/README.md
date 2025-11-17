# Infrastructure as Code with Pulumi

This directory contains Pulumi programs for provisioning the **Terminus** EKS cluster using Infrastructure as Code (IaC).

## Architecture Overview

**Decoupled Design:**
- **Trantor cluster** (manual provisioning) → General-purpose cluster
- **Terminus cluster** (Pulumi provisioning) → IaC-managed cluster

This architecture decouples services from clusters, allowing multiple services to share infrastructure.

## What's Managed by Pulumi

Pulumi declaratively manages all infrastructure components:

| Component | Manual Approach | Pulumi Approach |
|-----------|----------------|-----------------|
| **EKS Cluster** | `eksctl create cluster` | Defined in `__main__.py` |
| **Node Group** | eksctl YAML config | Python code with spot instances |
| **VPC & Networking** | Auto-created by eksctl | Explicit VPC, subnets, routing |
| **IAM Roles** | Manual IAM policy creation | Automated IRSA setup |
| **ALB Controller** | Helm install script | Helm release in code |
| **State Tracking** | None (imperative) | Pulumi state (declarative) |
| **Change Preview** | Manual verification | `pulumi preview` |
| **CI/CD** | Manual runs | Automated via GitHub Actions |

## File Structure

```
foundation/provisioning/pulumi/
├── __main__.py            # Main Pulumi program (EKS infrastructure)
├── Pulumi.yaml            # Project metadata
├── Pulumi.terminus.yaml   # Terminus cluster config (VPC: 10.2.0.0/16)
├── requirements.txt       # Python dependencies
├── .gitignore            # Git ignore rules
└── README.md             # This file
```

## Cluster Architecture

| Cluster | Stack Name | VPC CIDR | Management |
|---------|------------|----------|------------|
| **Trantor** | N/A | 10.0.0.0/16 | Manual (eksctl) |
| **Terminus** | terminus | 10.2.0.0/16 | Pulumi (IaC) |

## Quick Start

See **[pulumi-setup.md](../../../docs/02-infrastructure-as-code/pulumi-setup.md)** for detailed setup instructions.

### Deploy Terminus Cluster

```bash
cd foundation/provisioning/pulumi
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
pulumi login
pulumi stack select terminus  # or: pulumi stack init terminus
pulumi up
```

### View Stack State

```bash
# Preview changes
pulumi preview

# View current configuration
pulumi config

# View outputs
pulumi stack output

# View all stacks
pulumi stack ls
```

## Comparison: Manual vs Pulumi

### Manual Deployment (Trantor)

```bash
# Step 1: Create cluster
./foundation/provisioning/manual/create-trantor-cluster.sh us-east-1

# Step 2: Install ALB controller
./foundation/provisioning/manual/install-alb-controller-trantor.sh us-east-1

# Step 3: Deploy services (see gitops/manual_deploy for deployment scripts)
```

**Pros:**
- Quick to understand
- No learning curve
- Direct control

**Cons:**
- No change preview
- No state tracking
- Hard to update existing resources
- Difficult to replicate across environments
- Manual coordination required

### Pulumi Deployment (Terminus)

```bash
# All-in-one deployment
cd foundation/provisioning/pulumi
pulumi up
```

**Pros:**
- Preview changes before applying
- State tracking (know what exists)
- Easy updates (change code, run `pulumi up`)
- Repeatable across environments
- CI/CD integration (automatic deployment)
- Drift detection (`pulumi refresh`)
- Team collaboration (shared state)

**Cons:**
- Learning curve (Pulumi concepts)
- Additional dependency (Pulumi CLI)
- State management required

## CI/CD Workflow

Once set up, infrastructure changes follow GitOps:

```
1. Edit __main__.py or Pulumi.terminus.yaml
   ↓
2. Create PR
   ↓
3. GitHub Actions runs `pulumi preview`
   ↓
4. Review preview in PR comments
   ↓
5. Merge PR
   ↓
6. GitHub Actions runs `pulumi up`
   ↓
7. Infrastructure updated automatically
```

## Example: Scaling Node Group

**Manual approach (Trantor cluster):**
```bash
# Edit create-trantor-cluster.sh
# Change --nodes-max 4 to --nodes-max 6
# Delete cluster
eksctl delete cluster --name trantor
# Recreate cluster
./foundation/provisioning/manual/create-trantor-cluster.sh
# Reinstall everything
./foundation/provisioning/manual/install-alb-controller-trantor.sh
# Redeploy services (see gitops/manual_deploy)
```

**Pulumi approach (Terminus cluster):**
```yaml
# Edit Pulumi.terminus.yaml
foundation:max_nodes: "6"  # Changed from "4"
```
```bash
pulumi stack select terminus
pulumi preview  # See what will change
pulumi up       # Apply change (takes ~2 minutes)
```

## Stack Outputs

After deployment, get important values:

```bash
# Get cluster name
pulumi stack output cluster_name

# Get kubeconfig
pulumi stack output kubeconfig --show-secrets > kubeconfig.yaml

# Get all outputs
pulumi stack output --json
```

Outputs:
- `cluster_name` - For kubectl/eksctl commands
- `cluster_endpoint` - EKS API server
- `kubeconfig` - Complete kubeconfig file
- `vpc_id` - VPC identifier
- `oidc_provider_arn` - For additional IRSA roles
- `alb_controller_role_arn` - ALB controller IAM role

## Cluster Comparison

**Trantor cluster (Manual provisioning):**
- Created with `./foundation/provisioning/manual/create-trantor-cluster.sh`
- Managed with eksctl and kubectl commands
- No Pulumi state tracking
- Updates require manual script execution
- General-purpose cluster for any services

**Terminus cluster (Pulumi provisioning):**
- Created with `pulumi up`
- Managed declaratively via Infrastructure as Code
- State tracked in Pulumi backend
- Updates via `pulumi up` after config changes
- IaC-managed cluster for any services

## Application Deployment

After creating Terminus cluster with Pulumi, deploy applications:

```bash
# Get kubeconfig
pulumi stack output kubeconfig --show-secrets > terminus-kubeconfig.yaml
export KUBECONFIG=$(pwd)/terminus-kubeconfig.yaml

# Deploy applications using Pulumi
cd ../../gitops/pulumi_deploy
pulumi up
```

## Next Steps

1. ✅ **Set up Pulumi** - Follow [pulumi-setup.md](../../../docs/02-infrastructure-as-code/pulumi-setup.md)
2. ⏭️ **Deploy Terminus cluster** - Run `pulumi up` with terminus stack
3. ⏭️ **Deploy applications** - Use gitops/pulumi_deploy for declarative app deployment
4. ⏭️ **Set up CI/CD** - Automate infrastructure and app deployments

## Support

- Main docs: [pulumi-setup.md](../../../docs/02-infrastructure-as-code/pulumi-setup.md)
- Pulumi docs: https://www.pulumi.com/docs/
- AWS EKS guide: https://www.pulumi.com/registry/packages/eks/
- Questions: Create an issue
