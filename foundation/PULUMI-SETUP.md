# Pulumi Setup Guide

This guide walks you through setting up Pulumi to manage your Dawn EKS cluster infrastructure as code.

## Overview

Pulumi manages:
- VPC with public/private subnets
- EKS cluster with OIDC provider
- Managed node group using **spot instances** (t3.small)
- IAM roles for ALB controller
- ALB controller installation via Helm

## Prerequisites

1. **Pulumi CLI** - [Install Pulumi](https://www.pulumi.com/docs/get-started/install/)
   ```bash
   curl -fsSL https://get.pulumi.com | sh
   ```

2. **Python 3.11+** - Already installed for your Flask services

3. **AWS CLI** - Already configured with credentials

4. **kubectl** - Already installed for EKS management

## State Backend Options

Pulumi needs to store state. Choose one:

### Option 1: Pulumi Cloud (Recommended - Free tier available)

1. Create account at https://app.pulumi.com
2. Login via CLI:
   ```bash
   pulumi login
   ```
3. Get access token from https://app.pulumi.com/account/tokens
4. Add to GitHub Secrets:
   - `PULUMI_ACCESS_TOKEN` - Your Pulumi access token

**Benefits:**
- Free for individuals
- Built-in state locking
- Team collaboration features
- Automatic state backup
- Web UI to view resources

### Option 2: AWS S3 Backend (Self-managed)

1. Create S3 bucket for state:
   ```bash
   aws s3 mb s3://your-pulumi-state-bucket --region us-east-1
   ```

2. Enable versioning (recommended):
   ```bash
   aws s3api put-bucket-versioning \
     --bucket your-pulumi-state-bucket \
     --versioning-configuration Status=Enabled
   ```

3. Login to S3 backend:
   ```bash
   pulumi login s3://your-pulumi-state-bucket
   ```

**Benefits:**
- Full control over state
- No external dependencies
- Works in air-gapped environments

## Initial Setup (Local)

1. **Navigate to Pulumi directory:**
   ```bash
   cd foundation/pulumi
   ```

2. **Install Python dependencies:**
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   pip install -r requirements.txt
   ```

3. **Login to Pulumi:**
   ```bash
   pulumi login  # For Pulumi Cloud
   # OR
   pulumi login s3://your-pulumi-state-bucket  # For S3
   ```

4. **Initialize the stack:**
   ```bash
   pulumi stack init dev
   ```

5. **Set AWS region (if not using default):**
   ```bash
   pulumi config set aws:region us-east-1
   ```

## Deploy Infrastructure

### Preview changes (dry-run):
```bash
pulumi preview
```

This shows what will be created/modified/deleted **without actually making changes**.

### Deploy infrastructure:
```bash
pulumi up
```

Review the preview, then select `yes` to proceed.

**Expected resources created:**
- 1 VPC
- 2 Public subnets
- 1 Internet Gateway
- 1 Route table
- 1 EKS cluster
- 1 Managed node group (spot instances)
- IAM roles and policies for ALB controller
- Kubernetes service account
- ALB controller (Helm release)

**Deployment time:** ~10-15 minutes

### View stack outputs:
```bash
pulumi stack output
```

Outputs include:
- `cluster_name` - EKS cluster name
- `cluster_endpoint` - EKS API endpoint
- `kubeconfig` - Full kubeconfig (sensitive)
- `vpc_id` - VPC identifier
- `oidc_provider_arn` - For IRSA setup
- `region` - AWS region

### Get kubeconfig:
```bash
pulumi stack output kubeconfig --show-secrets > kubeconfig.yaml
export KUBECONFIG=$(pwd)/kubeconfig.yaml
kubectl get nodes
```

## CI/CD Integration (GitHub Actions)

### Required GitHub Secrets

Add these secrets to your repository at **Settings → Secrets → Actions**:

1. **AWS_ACCESS_KEY_ID** - Already configured
2. **AWS_SECRET_ACCESS_KEY** - Already configured
3. **PULUMI_ACCESS_TOKEN** - Your Pulumi access token

### Workflow Behavior

**On Pull Request:**
- `.github/workflows/pulumi-preview.yml` runs
- Shows infrastructure changes in PR comments
- No actual changes made

**On Merge to Main:**
- `.github/workflows/pulumi-up.yml` runs
- Deploys infrastructure changes automatically
- Outputs displayed in GitHub Actions summary

### Test the Workflow

1. Make a change to `foundation/pulumi/__main__.py`
2. Create a PR
3. Check PR comments for Pulumi preview
4. Merge PR → infrastructure updates automatically

## Import Existing Cluster (Optional)

If you already have a Dawn cluster running and want to manage it with Pulumi:

```bash
# This is complex - contact for guidance
# Generally: pulumi import <resource-type> <resource-name> <aws-id>
```

**Note:** Importing existing resources is advanced. It's usually easier to:
1. Deploy a new cluster with Pulumi
2. Migrate workloads
3. Delete old cluster

## Common Operations

### View current infrastructure:
```bash
pulumi stack
```

### Update a configuration value:
```bash
pulumi config set dawn-infrastructure:max_nodes 5
pulumi up
```

### Destroy all infrastructure:
```bash
pulumi destroy
```

⚠️ **WARNING:** This deletes everything! Type the stack name to confirm.

### View resource details:
```bash
pulumi stack export | jq
```

### Refresh state (detect drift):
```bash
pulumi refresh
```

This compares Pulumi state with actual AWS resources and updates state.

## Stack Management

Create separate stacks for different environments:

```bash
# Create staging stack
pulumi stack init staging
pulumi config set aws:region us-east-1
pulumi up

# Create production stack
pulumi stack init production
pulumi config set aws:region us-east-1
pulumi config set dawn-infrastructure:min_nodes 3
pulumi config set dawn-infrastructure:max_nodes 10
pulumi up

# Switch between stacks
pulumi stack select dev
pulumi stack select staging
pulumi stack select production
```

Each stack maintains separate state and resources.

## Cost Estimate

Use the same cost breakdown as manual deployment:

**Per cluster (spot instances):**
- EKS control plane: ~$73/month
- 2x t3.small spot nodes: ~$9/month each (~$18 total)
- ALB: ~$21-26/month
- Data transfer: ~$1-3/month

**Total: ~$111-121/month per cluster**

## Troubleshooting

### Preview shows no changes but you made edits:
```bash
# Refresh state first
pulumi refresh
pulumi preview
```

### "Stack not found" error:
```bash
# Verify you're logged in
pulumi whoami

# List available stacks
pulumi stack ls
```

### AWS authentication errors:
```bash
# Verify credentials
aws sts get-caller-identity

# Re-configure if needed
aws configure
```

### State conflicts in CI/CD:
- Pulumi Cloud has built-in locking
- S3 backend: enable DynamoDB locking table

### Resource already exists errors:
- Another stack owns the resource
- Or resource created outside Pulumi
- Use `pulumi import` or delete the resource

## Best Practices

✅ **Always run `pulumi preview` before `pulumi up`**
✅ **Use separate stacks for dev/staging/prod**
✅ **Store sensitive outputs as secrets**
✅ **Enable versioning on S3 state bucket**
✅ **Use Pulumi Cloud for team collaboration**
✅ **Tag all resources with stack name**
✅ **Review preview output in PR comments**
✅ **Set up drift detection (scheduled `pulumi refresh`)**

## Next Steps

After Pulumi is managing your infrastructure:

1. **Deploy applications** - Apply K8s manifests to the Pulumi-managed cluster
2. **Add ArgoCD** - Set up GitOps continuous deployment
3. **Expand to Day/Dusk** - Create additional stacks for other services
4. **Monitoring** - Add CloudWatch dashboards via Pulumi
5. **Alerts** - Define SNS topics and alarms in Pulumi code

## Resources

- [Pulumi AWS Guide](https://www.pulumi.com/docs/clouds/aws/get-started/)
- [Pulumi EKS Examples](https://github.com/pulumi/examples/tree/master/aws-py-eks)
- [Pulumi Kubernetes Provider](https://www.pulumi.com/registry/packages/kubernetes/)
- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
