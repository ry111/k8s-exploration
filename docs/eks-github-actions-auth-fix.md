# Fixing EKS Authentication for GitHub Actions

## Problem

The GitHub Actions workflow fails with:

```
error: configured Kubernetes cluster is unreachable: unable to load schema information from the API server: the server has asked for the client to provide credentials
```

## Root Cause

The IAM user or role used by GitHub Actions (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` secrets) is not authorized to access the EKS cluster.

EKS uses AWS IAM for authentication. When the cluster was created by Pulumi, only the cluster creator's IAM principal was automatically granted access. The GitHub Actions IAM principal needs to be explicitly added to the cluster's `aws-auth` ConfigMap.

## Solution

### Step 1: Get the IAM Principal ARN

The workflow now includes debugging output. Check the GitHub Actions workflow logs for the "Testing AWS credentials" step, which runs `aws sts get-caller-identity`. You'll see output like:

```json
{
    "UserId": "AIDAXXXXXXXXXXXXX",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/github-actions-user"
}
```

Copy the `Arn` value - this is the IAM principal that needs cluster access.

### Step 2: Grant Access to the Cluster

#### Option A: Using the Helper Script (Recommended)

From your local machine (with kubectl access to the cluster):

```bash
./scripts/grant-github-actions-access.sh \
  arn:aws:iam::123456789012:user/github-actions-user \
  day-cluster-eksCluster-f3c27b8
```

Replace the ARN with the one from Step 1.

#### Option B: Using eksctl

```bash
# For IAM User
eksctl create iamidentitymapping \
  --cluster day-cluster-eksCluster-f3c27b8 \
  --region us-east-1 \
  --arn arn:aws:iam::123456789012:user/github-actions-user \
  --username github-actions \
  --group system:masters

# For IAM Role
eksctl create iamidentitymapping \
  --cluster day-cluster-eksCluster-f3c27b8 \
  --region us-east-1 \
  --arn arn:aws:iam::123456789012:role/github-actions-role \
  --username github-actions \
  --group system:masters
```

#### Option C: Manual kubectl Edit

```bash
# Update kubeconfig
aws eks update-kubeconfig --name day-cluster-eksCluster-f3c27b8 --region us-east-1

# Edit the aws-auth ConfigMap
kubectl edit configmap aws-auth -n kube-system
```

Add to the appropriate section:

**For IAM User:**
```yaml
mapUsers: |
  - userarn: arn:aws:iam::123456789012:user/github-actions-user
    username: github-actions
    groups:
      - system:masters
```

**For IAM Role:**
```yaml
mapRoles: |
  - rolearn: arn:aws:iam::123456789012:role/github-actions-role
    username: github-actions
    groups:
      - system:masters
```

### Step 3: Verify

Re-run the GitHub Actions workflow. The deployment should now succeed.

## Alternative Solution: Update Infrastructure Code

For a more permanent solution, update the infrastructure Pulumi code to include the IAM mapping when creating the cluster. Add to `foundation/infrastructure/pulumi/Pulumi.day.yaml`:

```yaml
config:
  service-infrastructure:github_actions_iam_arn: arn:aws:iam::123456789012:user/github-actions-user
```

Then update `foundation/infrastructure/pulumi/__main__.py` to use this configuration when creating the cluster.

## Debugging Commands

If you still have issues, run these commands locally:

```bash
# Verify AWS credentials
aws sts get-caller-identity

# Update kubeconfig
aws eks update-kubeconfig --name day-cluster-eksCluster-f3c27b8 --region us-east-1

# Test kubectl access
kubectl cluster-info

# View current aws-auth ConfigMap
kubectl get configmap aws-auth -n kube-system -o yaml

# Test eks get-token
aws eks get-token --cluster-name day-cluster-eksCluster-f3c27b8 --region us-east-1
```

## Security Note

The solution above grants `system:masters` (full admin) access to the GitHub Actions IAM principal. For production environments, consider creating a more restrictive RBAC role with only the permissions needed for deployments.
