# Troubleshooting Common Issues

This guide covers common problems you might encounter while working with this project and how to resolve them.

---

## Table of Contents

- [Pulumi Issues](#pulumi-issues)
  - [Stack Reference Configuration](#stack-reference-configuration)
- [EKS and AWS Authentication Issues](#eks-and-aws-authentication-issues)
  - [GitHub Actions EKS Authentication](#github-actions-eks-authentication)
- [Kubernetes Issues](#kubernetes-issues)
  - [Pods Not Starting](#pods-not-starting)
  - [Image Pull Errors](#image-pull-errors)
  - [Ingress Not Creating ALB](#ingress-not-creating-alb)
- [CI/CD Issues](#cicd-issues)
  - [GitHub Actions Build Failures](#github-actions-build-failures)
  - [Images Not in ECR](#images-not-in-ecr)

---

## Pulumi Issues

### Stack Reference Configuration

#### Problem

`pulumi preview` works even when stack reference is mistyped in the YAML config file. The provider silently falls back to default kubeconfig.

**Symptoms:**
- No error when stack reference is invalid
- Deploys to wrong cluster or uses local kubeconfig
- Hard to verify which cluster is being used

#### Root Cause

The `fn::stackReference` syntax in Pulumi YAML config files doesn't work for Kubernetes provider configuration. Pulumi doesn't recognize the `fn::` syntax in regular config YAML files.

For example, this **does NOT work**:
```yaml
# ❌ This is IGNORED by Pulumi
config:
  kubernetes:kubeconfig:
    fn::stackReference:
      name: ry111/foundation/day
      output: kubeconfig
```

#### Solution

**Use `pulumi.StackReference()` in your Python code**, not in YAML config.

**Step 1: Update Your Python Code**

The code should:
1. Read a config flag to determine if stack reference should be used
2. Create a `StackReference` object in code (not YAML)
3. Create an explicit Kubernetes provider
4. Pass the provider to every resource

```python
import pulumi
import pulumi_kubernetes as k8s

config = pulumi.Config()

# Read config to determine if stack reference should be used
use_stack_reference = config.get_bool("use_stack_reference")
if use_stack_reference is None:
    use_stack_reference = True  # Default to using stack reference

if use_stack_reference:
    # Get the infrastructure stack name from config
    infra_stack_name = config.get("infra_stack_name") or "ry111/foundation/day"

    # Create stack reference to infrastructure stack
    infra_stack = pulumi.StackReference(infra_stack_name)

    # Get kubeconfig output from infrastructure stack
    kubeconfig = infra_stack.require_output("kubeconfig")

    # Create explicit Kubernetes provider
    k8s_provider = k8s.Provider("k8s-provider", kubeconfig=kubeconfig)

    # Use this provider for all resources
    provider_opts = pulumi.ResourceOptions(provider=k8s_provider)
else:
    # Use default kubeconfig (local development)
    # Will use ~/.kube/config or KUBECONFIG environment variable
    provider_opts = None

# Apply provider to every resource
deployment = k8s.apps.v1.Deployment(
    f"{app_name}-deployment",
    metadata={...},
    spec={...},
    opts=provider_opts,  # ← Pass provider to every resource
)
```

**Step 2: Update Config Files**

Use simple config values instead of `fn::` syntax:

```yaml
# Pulumi.dev.yaml or Pulumi.production.yaml
config:
  # Simple boolean and string configs - no fn:: syntax
  day-service-app:use_stack_reference: true
  day-service-app:infra_stack_name: ry111/foundation/day

  # Rest of config...
  day-service-app:namespace: dev
  day-service-app:image_tag: latest
```

**Step 3: Export Status for Debugging**

Add exports to show which mode is active:

```python
# Export which provider mode is being used
pulumi.export("using_stack_reference", use_stack_reference)
if use_stack_reference:
    pulumi.export("infra_stack_referenced", infra_stack_name)
```

#### Verification

**Test 1: Stack Reference Should Be Required**

```bash
# Temporarily change infra_stack_name to invalid value
pulumi config set infra_stack_name invalid/stack/name

# This should FAIL with clear error
pulumi preview
# Expected error: "failed to resolve stack reference 'invalid/stack/name'"

# Fix it back
pulumi config set infra_stack_name ry111/foundation/day
```

**Test 2: Check Outputs**

```bash
pulumi preview

# Should show in outputs:
# using_stack_reference: true
# infra_stack_referenced: ry111/foundation/day
```

**Test 3: Disable Stack Reference (Use Local Kubeconfig)**

```bash
# For local development, you can disable stack reference
pulumi config set use_stack_reference false

# Now it will use local kubeconfig instead
pulumi preview
```

#### Key Differences

| Aspect | Before (Broken) | After (Fixed) |
|--------|----------------|---------------|
| **Stack Reference Location** | YAML config file (`fn::stackReference`) | Python code (`pulumi.StackReference()`) |
| **Error on Misconfiguration** | ❌ Silent failure, falls back | ✅ Explicit error |
| **Verifiable** | ❌ Hard to test | ✅ Clear outputs and errors |
| **Provider Setup** | Implicit (doesn't work) | Explicit Provider object |
| **Resource Opts** | None | `opts=provider_opts` on every resource |

#### Why This Approach Works

1. **`pulumi.StackReference()` is the official Python API** for referencing other stacks
2. **Creates an explicit Provider object** that Kubernetes resources can use
3. **`require_output()` will fail immediately** if the stack or output doesn't exist
4. **Every resource explicitly uses the provider**, no implicit fallbacks
5. **Exports show which mode is active** for debugging

#### Switching Between Modes

```bash
# Use stack reference (production/CI-CD)
pulumi config set use_stack_reference true
pulumi config set infra_stack_name ry111/foundation/day

# Use local kubeconfig (development)
pulumi config set use_stack_reference false
# Make sure you have valid kubeconfig:
aws eks update-kubeconfig --name terminus
```

---

## EKS and AWS Authentication Issues

### GitHub Actions EKS Authentication

#### Problem

GitHub Actions workflow fails with:

```
error: configured Kubernetes cluster is unreachable: unable to load schema information from the API server: the server has asked for the client to provide credentials
```

#### Root Cause

The IAM user or role used by GitHub Actions (configured via `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` secrets) is not authorized to access the EKS cluster.

**Why this happens:**
- EKS uses AWS IAM for authentication
- When the cluster was created, only the creator's IAM principal was granted access
- The GitHub Actions IAM principal needs to be explicitly granted cluster access

#### Prerequisites

The IAM user/role must have these AWS permissions:
- `eks:DescribeCluster`
- `eks:ListClusters`
- `sts:GetCallerIdentity` (usually included by default)

If missing, add this IAM policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters"
      ],
      "Resource": "*"
    }
  ]
}
```

#### Solution

**Step 1: Get the IAM Principal ARN**

Check the GitHub Actions workflow logs for the "Testing AWS credentials" step, which runs `aws sts get-caller-identity`. You'll see output like:

```json
{
    "UserId": "AIDAXXXXXXXXXXXXX",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/github-actions-user"
}
```

Copy the `Arn` value - this is the IAM principal that needs cluster access.

**Step 2: Grant Access to the Cluster**

**RECOMMENDED:** Use the Access Entries method (Option A). It's cleaner and doesn't require modifying ConfigMaps.

**Option A: Using Access Entries (Recommended - EKS 1.23+)**

From your local machine (where you have admin access to the cluster):

```bash
./foundation/provisioning/manual/grant-github-actions-access-v2.sh \
  arn:aws:iam::123456789012:user/github-actions-user \
  your-cluster-name
```

This uses the modern EKS Access Entry API which is cleaner than aws-auth ConfigMap.

**Option B: Using aws-auth ConfigMap (Legacy)**

From your local machine:

```bash
./foundation/provisioning/manual/grant-github-actions-access.sh \
  arn:aws:iam::123456789012:user/github-actions-user \
  your-cluster-name
```

**Option C: Using eksctl**

```bash
# For IAM User
eksctl create iamidentitymapping \
  --cluster your-cluster-name \
  --region us-east-1 \
  --arn arn:aws:iam::123456789012:user/github-actions-user \
  --username github-actions \
  --group system:masters

# For IAM Role
eksctl create iamidentitymapping \
  --cluster your-cluster-name \
  --region us-east-1 \
  --arn arn:aws:iam::123456789012:role/github-actions-role \
  --username github-actions \
  --group system:masters
```

**Option D: Manual kubectl Edit**

```bash
# Update kubeconfig
aws eks update-kubeconfig --name your-cluster-name --region us-east-1

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

**Step 3: Verify**

Re-run the GitHub Actions workflow. The deployment should now succeed.

#### Troubleshooting

**Still Getting Authentication Errors?**

Run the diagnostic script from your local machine:

```bash
./foundation/provisioning/manual/diagnose-eks-auth.sh your-cluster-name arn:aws:iam::123456789012:user/your-iam-user
```

This will check:
- Your current IAM identity
- Cluster status and accessibility
- aws-auth ConfigMap contents
- EKS access entries
- kubectl connectivity
- IAM permissions

**Common Issues:**

1. **Wrong IAM ARN**
   - Make sure you're using the exact ARN from the GitHub Actions output
   - Check if it's a user (`arn:aws:iam::ACCOUNT:user/NAME`) vs role (`arn:aws:iam::ACCOUNT:role/NAME`)

2. **IAM Principal Lacks EKS Permissions**
   - The IAM user/role needs `eks:DescribeCluster` permission
   - Add the IAM policy shown in the Prerequisites section

3. **aws-auth ConfigMap Not Updated Properly**
   - Verify with: `kubectl get configmap aws-auth -n kube-system -o yaml`
   - Look for your IAM ARN in either `mapRoles` or `mapUsers`
   - Make sure indentation is correct (YAML is sensitive to whitespace)

4. **Using Access Entries but Cluster Doesn't Support Them**
   - Access Entries require EKS 1.23+
   - Check cluster version: `aws eks describe-cluster --name CLUSTER_NAME --query 'cluster.version'`
   - If < 1.23, use the aws-auth ConfigMap method instead

5. **Changes Haven't Propagated**
   - Wait 30-60 seconds after updating aws-auth ConfigMap
   - For access entries, changes should be immediate

#### Security Note

The solutions above grant `system:masters` (full admin) access to the GitHub Actions IAM principal. For production environments, consider creating a more restrictive RBAC role with only the permissions needed for deployments.

#### Debugging Commands

If you still have issues, run these commands locally:

```bash
# Verify AWS credentials
aws sts get-caller-identity

# Update kubeconfig
aws eks update-kubeconfig --name your-cluster-name --region us-east-1

# Test kubectl access
kubectl cluster-info

# View current aws-auth ConfigMap
kubectl get configmap aws-auth -n kube-system -o yaml

# Test eks get-token
aws eks get-token --cluster-name your-cluster-name --region us-east-1
```

---

## Kubernetes Issues

### Pods Not Starting

#### Symptoms

```bash
kubectl get pods -n your-namespace

# Shows:
# NAME                    READY   STATUS             RESTARTS   AGE
# app-xxxxxxxxxx-xxxxx   0/1     Pending            0          2m
# app-xxxxxxxxxx-xxxxx   0/1     ImagePullBackOff   0          3m
# app-xxxxxxxxxx-xxxxx   0/1     CrashLoopBackOff   3          5m
```

#### Diagnosis

```bash
# Get detailed pod information
kubectl describe pod -n your-namespace <pod-name>

# Check pod logs
kubectl logs -n your-namespace <pod-name>

# Check events
kubectl get events -n your-namespace --sort-by='.lastTimestamp'
```

#### Common Causes

**1. Pending Status**
- **Cause:** Not enough resources (CPU/memory) on nodes
- **Solution:**
  ```bash
  # Check node resources
  kubectl top nodes

  # Check if pods have resource requests that can't be satisfied
  kubectl describe pod -n your-namespace <pod-name> | grep -A 5 "Resources"

  # Scale up nodes or reduce resource requests
  ```

**2. ImagePullBackOff** (See dedicated section below)

**3. CrashLoopBackOff**
- **Cause:** Application is crashing immediately after starting
- **Solution:**
  ```bash
  # Check application logs
  kubectl logs -n your-namespace <pod-name>

  # Check previous container logs if pod restarted
  kubectl logs -n your-namespace <pod-name> --previous

  # Common issues:
  # - Missing environment variables
  # - Application configuration error
  # - Database connection failure
  ```

---

### Image Pull Errors

#### Symptoms

```bash
kubectl get pods -n your-namespace

# Shows:
# NAME                    READY   STATUS             RESTARTS   AGE
# app-xxxxxxxxxx-xxxxx   0/1     ImagePullBackOff   0          3m
```

#### Diagnosis

```bash
# Describe the pod to see the error
kubectl describe pod -n your-namespace <pod-name>

# Look for:
# Events:
#   Type     Reason     Message
#   ----     ------     -------
#   Warning  Failed     Failed to pull image "...": rpc error...
```

#### Common Causes and Solutions

**1. Image Not in ECR**
```bash
# Check if image exists in ECR
aws ecr describe-images --repository-name your-service --region us-east-1

# If missing, rebuild and push:
cd foundation/provisioning/manual
./build-and-push-dawn.sh us-east-1

# Or trigger GitHub Actions build
```

**2. Wrong Image URL**
```bash
# Check the image URL in deployment
kubectl get deployment -n your-namespace your-deployment -o yaml | grep image:

# Should be:
# image: 123456789.dkr.ecr.us-east-1.amazonaws.com/dawn:latest

# Update if wrong:
kubectl set image deployment/your-deployment your-container=CORRECT_IMAGE_URL -n your-namespace
```

**3. ECR Repository in Different Region**
```bash
# Verify ECR region matches cluster region
aws ecr describe-repositories --region us-east-1

# Update image URL to correct region
```

**4. Node IAM Role Lacks ECR Pull Permissions**
```bash
# Check node IAM role has AmazonEC2ContainerRegistryReadOnly policy
# AWS Console → IAM → Roles → <node-role> → Permissions

# Or add via CLI:
aws iam attach-role-policy \
  --role-name <node-role-name> \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

---

### Ingress Not Creating ALB

#### Symptoms

```bash
kubectl get ingress -n your-namespace

# Shows:
# NAME            CLASS    HOSTS   ADDRESS   PORTS   AGE
# your-ingress    <none>   *       <pending>  80      10m
```

#### Diagnosis

```bash
# Check Ingress details
kubectl describe ingress your-ingress -n your-namespace

# Check ALB controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

#### Common Causes and Solutions

**1. ALB Controller Not Running**
```bash
# Check if controller is deployed
kubectl get deployment -n kube-system aws-load-balancer-controller

# Should show 2/2 ready
# If not deployed:
cd foundation/provisioning/manual
./install-alb-controller-dawn.sh us-east-1
```

**2. Missing IAM Permissions**
```bash
# Check controller logs for permission errors
kubectl logs -n kube-system deployment/aws-load-balancer-controller | grep -i "error\|denied"

# If permission errors, verify IAM role has required ELB permissions
# See infrastructure Pulumi code for required permissions
```

**3. ALB Still Provisioning**
```bash
# AWS takes 2-3 minutes to provision ALB
# Just wait and check again:
watch kubectl get ingress -n your-namespace
```

**4. Missing Ingress Annotations**
```bash
# Check Ingress has required annotations
kubectl get ingress your-ingress -n your-namespace -o yaml

# Should have:
# metadata:
#   annotations:
#     kubernetes.io/ingress.class: alb
#     alb.ingress.kubernetes.io/scheme: internet-facing
#     alb.ingress.kubernetes.io/target-type: ip
```

**5. Subnet Tags Missing**
```bash
# Public subnets must be tagged for ALB:
# kubernetes.io/role/elb: "1"

# Check subnet tags in AWS Console or via CLI:
aws ec2 describe-subnets --subnet-ids <subnet-id> --query 'Subnets[0].Tags'
```

---

## CI/CD Issues

### GitHub Actions Build Failures

#### Symptoms

GitHub Actions workflow fails during build step.

#### Common Causes and Solutions

**1. "could not find any file" Error**
```bash
# Check that service code exists
ls -la foundation/services/dawn/

# Should show:
# - Dockerfile
# - main.py
# - requirements.txt

# If files are in wrong location, move them to correct path
```

**2. "Unable to locate credentials" Error**
```bash
# Verify GitHub secrets are set correctly
# GitHub Repo → Settings → Secrets and variables → Actions

# Check secret names match exactly:
# - AWS_ACCESS_KEY_ID
# - AWS_SECRET_ACCESS_KEY

# Ensure there are no extra spaces in the values
```

**3. "AccessDenied" when pushing to ECR**
```bash
# AWS Console → IAM → Users → github-actions-ecr → Permissions
# Ensure policy is attached: AmazonEC2ContainerRegistryPowerUser

# Or check via CLI:
aws iam list-attached-user-policies --user-name github-actions-ecr
```

**4. Build Succeeds but Takes Too Long**
```bash
# Enable Docker layer caching in workflow:
# - name: Set up Docker Buildx
#   uses: docker/setup-buildx-action@v2
#
# - name: Cache Docker layers
#   uses: actions/cache@v3
#   with:
#     path: /tmp/.buildx-cache
#     key: ${{ runner.os }}-buildx-${{ github.sha }}
```

---

### Images Not in ECR

#### Symptoms

GitHub Actions build completes successfully, but images don't appear in ECR.

#### Diagnosis

```bash
# Check if images exist
aws ecr list-images --repository-name dawn --region us-east-1

# Check GitHub Actions logs
# GitHub Repo → Actions → Click on workflow run → View logs
```

#### Common Causes and Solutions

**1. Workflow Succeeded but Push Failed**
```bash
# Check the "Push to ECR" step in GitHub Actions logs
# Look for errors in that specific step

# Common issue: IAM user lacks PutImage permission
# Add to IAM policy:
# "ecr:PutImage",
# "ecr:InitiateLayerUpload",
# "ecr:UploadLayerPart",
# "ecr:CompleteLayerUpload"
```

**2. Wrong AWS Region**
```bash
# Workflows use us-east-1 by default
# Check if ECR repository is in different region:
aws ecr describe-repositories --region us-west-2

# Update workflow file to match ECR region
```

**3. Repository Name Mismatch**
```bash
# Check repository name in workflow matches actual repo name
# Workflow uses service name (dawn, day, dusk)
aws ecr describe-repositories --region us-east-1
```

**4. Wrong AWS Account**
```bash
# Verify you're checking the correct AWS account
aws sts get-caller-identity

# Compare with GitHub Actions AWS_ACCESS_KEY_ID
```

---

## General Debugging Tips

### Enable Verbose Logging

**Pulumi:**
```bash
pulumi preview --logtostderr -v=9 2> pulumi.log
```

**kubectl:**
```bash
kubectl get pods -v=9
```

**AWS CLI:**
```bash
aws eks describe-cluster --name your-cluster --debug
```

### Check Resource Status

```bash
# Check all resources in namespace
kubectl get all -n your-namespace

# Check events (sorted by time)
kubectl get events -n your-namespace --sort-by='.lastTimestamp'

# Check resource quotas
kubectl describe resourcequota -n your-namespace

# Check limit ranges
kubectl describe limitrange -n your-namespace
```

### Useful kubectl Commands

```bash
# Get pod YAML
kubectl get pod -n your-namespace <pod-name> -o yaml

# Get deployment YAML
kubectl get deployment -n your-namespace <deployment-name> -o yaml

# Watch resources update in real-time
watch kubectl get pods -n your-namespace

# Get logs from all pods in deployment
kubectl logs -n your-namespace deployment/your-deployment --all-containers=true

# Execute command in pod
kubectl exec -it -n your-namespace <pod-name> -- /bin/bash
```

---

## Getting Help

If you're still stuck after trying these troubleshooting steps:

1. **Check the logs** - Most issues have clues in logs
2. **Search for the exact error message** - Often someone else has hit it
3. **Simplify** - Try to isolate the problem to one component
4. **Start fresh** - Sometimes cleanup and redeploy reveals the issue

**Useful resources:**
- [Kubernetes Troubleshooting Guide](https://kubernetes.io/docs/tasks/debug/)
- [EKS Troubleshooting](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
- [Pulumi Troubleshooting](https://www.pulumi.com/docs/support/troubleshooting/)
