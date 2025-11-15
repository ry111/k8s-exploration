# Multi-Service Infrastructure with Pulumi

This directory contains Infrastructure as Code (IaC) for managing EKS clusters for **Day** and **Dusk** services using Pulumi.

**Note**: The **Dawn** cluster was created manually using eksctl scripts and is NOT managed by Pulumi.

## What's Managed by Pulumi

Instead of running bash scripts manually, Pulumi declaratively manages:

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
foundation/pulumi/
├── __main__.py           # Main Pulumi program (generic for all services)
├── Pulumi.yaml           # Project metadata
├── Pulumi.day.yaml       # Day cluster config (VPC: 10.1.0.0/16)
├── Pulumi.dusk.yaml      # Dusk cluster config (VPC: 10.2.0.0/16)
├── requirements.txt      # Python dependencies
├── .gitignore           # Git ignore rules
└── README.md            # This file
```

## Multi-Service Support

The same Pulumi code manages Day and Dusk clusters. Each service gets:
- **Separate VPC** (non-overlapping CIDR blocks)
- **Dedicated EKS cluster**
- **Independent ALB and node groups**
- **Separate Pulumi stack** for state management

| Service | Stack Name | VPC CIDR | Cluster Name | Management |
|---------|------------|----------|--------------|------------|
| **Dawn** | N/A | 10.0.0.0/16 | dawn-cluster | Manual (eksctl) |
| **Day** | day | 10.1.0.0/16 | day-cluster | Pulumi |
| **Dusk** | dusk | 10.2.0.0/16 | dusk-cluster | Pulumi |

## Quick Start

See **[PULUMI-SETUP.md](../PULUMI-SETUP.md)** for detailed setup instructions.

### Deploy Day Cluster
See **[DEPLOY-DAY-CLUSTER.md](../DEPLOY-DAY-CLUSTER.md)** for detailed Day cluster deployment guide.

```bash
cd foundation/pulumi
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
pulumi login
pulumi stack select day  # or: pulumi stack init day
pulumi up
```

### Deploy Dusk Cluster
```bash
cd foundation/pulumi
pulumi stack select dusk  # or: pulumi stack init dusk
pulumi up
```

### Switch Between Services
```bash
# Work on Day infrastructure
pulumi stack select day
pulumi preview

# Work on Dusk infrastructure
pulumi stack select dusk
pulumi preview

# View all stacks
pulumi stack ls
```

## Comparison: Manual vs Pulumi

### Manual Deployment (Current)
```bash
# Step 1: Create cluster
./foundation/scripts/create-dawn-cluster.sh

# Step 2: Install ALB controller
./foundation/scripts/install-alb-controller-dawn.sh

# Step 3: Deploy app
./foundation/scripts/deploy-dawn.sh
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

### Pulumi Deployment (New)
```bash
# All-in-one deployment
cd foundation/pulumi
pulumi up
```

**Pros:**
- Preview changes before applying
- State tracking (know what exists)
- Easy updates (change code, run `pulumi up`)
- Repeatable across environments (dev/staging/prod stacks)
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
1. Edit __main__.py (change node count, instance type, etc.)
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

**Manual approach (Dawn cluster):**
```bash
# Edit create-dawn-cluster.sh
# Change --nodes-max 3 to --nodes-max 5
# Delete cluster
eksctl delete cluster --name dawn-cluster
# Recreate cluster
./foundation/scripts/create-dawn-cluster.sh
# Reinstall everything
./foundation/scripts/install-alb-controller-dawn.sh
./foundation/scripts/deploy-dawn.sh
```

**Pulumi approach (Day/Dusk clusters):**
```yaml
# Edit Pulumi.day.yaml
service-infrastructure:max_nodes: "5"  # Changed from "3"
```
```bash
pulumi stack select day
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

## Dawn vs Day/Dusk: Management Comparison

**Dawn cluster (Manual - Already Running):**
- Created with `./foundation/scripts/create-dawn-cluster.sh`
- Managed with eksctl and kubectl commands
- No Pulumi state tracking
- Updates require manual script execution

**Day/Dusk clusters (Pulumi - New):**
- Created with `pulumi up`
- Managed declaratively via Infrastructure as Code
- State tracked in Pulumi backend
- Updates via `pulumi up` after config changes

## Application Deployment

After creating Day cluster with Pulumi, deploy the Day application:

```bash
# Get kubeconfig
pulumi stack output kubeconfig --show-secrets > day-kubeconfig.yaml
export KUBECONFIG=$(pwd)/day-kubeconfig.yaml

# Deploy Day service
kubectl apply -f foundation/k8s/day/
```

## Next Steps

1. ✅ **Set up Pulumi** - Follow PULUMI-SETUP.md
2. ⏭️ **Deploy Day cluster** - Run `pulumi up` with day stack
3. ⏭️ **Deploy Day application** - Apply K8s manifests
4. ⏭️ **Deploy Dusk cluster** - Run `pulumi up` with dusk stack (optional)
5. ⏭️ **Set up ArgoCD** - Automate application deployment (Phase 5)

## Cost

Same cost as manual deployment:
- **~$111-121/month** per cluster with spot instances

Pulumi itself is free (using Pulumi Cloud free tier or S3 backend).

## Support

- Main docs: [PULUMI-SETUP.md](../PULUMI-SETUP.md)
- Pulumi docs: https://www.pulumi.com/docs/
- AWS EKS guide: https://www.pulumi.com/registry/packages/eks/
- Questions: Create an issue
