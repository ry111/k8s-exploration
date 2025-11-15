# Dawn Infrastructure with Pulumi

This directory contains Infrastructure as Code (IaC) for the Dawn EKS cluster using Pulumi.

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
├── __main__.py           # Main Pulumi program (EKS cluster definition)
├── Pulumi.yaml           # Project metadata
├── Pulumi.dev.yaml       # Dev environment config
├── requirements.txt      # Python dependencies
├── .gitignore           # Git ignore rules
└── README.md            # This file
```

## Quick Start

See **[PULUMI-SETUP.md](../PULUMI-SETUP.md)** for detailed setup instructions.

**TL;DR:**
```bash
cd foundation/pulumi
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
pulumi login
pulumi stack init dev
pulumi up
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

**Manual approach:**
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

**Pulumi approach:**
```python
# Edit __main__.py
cluster = eks.Cluster(
    "dawn-cluster",
    max_size=5,  # Changed from 3
    # ... rest stays the same
)
```
```bash
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

## Integration with Existing Scripts

You can still use existing deployment scripts with Pulumi-managed cluster:

```bash
# Deploy app to Pulumi-managed cluster
./foundation/scripts/deploy-dawn.sh

# Run health checks
./foundation/scripts/health-check-dawn.sh
```

The difference is the **cluster itself** is now managed by Pulumi.

## Migration Path

If you have an existing manually-created cluster:

**Option 1: Fresh Start (Recommended)**
1. Deploy new cluster with Pulumi
2. Migrate workloads to new cluster
3. Delete old cluster

**Option 2: Import Existing Resources**
1. Import cluster: `pulumi import eks:Cluster dawn-cluster <cluster-id>`
2. Import VPC, subnets, etc. (complex)
3. Future changes managed by Pulumi

**We recommend Option 1** - cleaner and faster.

## Next Steps

1. ✅ **Set up Pulumi** - Follow PULUMI-SETUP.md
2. ⏭️ **Deploy cluster** - Run `pulumi up`
3. ⏭️ **Deploy applications** - Use existing deploy scripts
4. ⏭️ **Set up ArgoCD** - Automate application deployment (Phase 5)
5. ⏭️ **Add Day/Dusk** - Create additional stacks

## Cost

Same cost as manual deployment:
- **~$111-121/month** per cluster with spot instances

Pulumi itself is free (using Pulumi Cloud free tier or S3 backend).

## Support

- Main docs: [PULUMI-SETUP.md](../PULUMI-SETUP.md)
- Pulumi docs: https://www.pulumi.com/docs/
- AWS EKS guide: https://www.pulumi.com/registry/packages/eks/
- Questions: Create an issue
