# GitHub Actions CI/CD Setup

This guide shows you how to set up GitHub Actions to automatically build Docker images and push them to AWS ECR. No Docker installation needed on your laptop!

## 🎯 Learning Objectives

By completing this guide, you will:
- ✅ Configure GitHub Actions for automated image builds
- ✅ Set up AWS IAM permissions for CI/CD
- ✅ Understand the complete CI/CD workflow
- ✅ Deploy applications using CI-built images

**Benefits:**
- ✅ No Docker required on your laptop
- ✅ Automatic builds on every push
- ✅ Consistent build environment
- ✅ Free (GitHub Actions generous free tier)
- ✅ Images tagged with git SHA for version tracking

---

## Prerequisites

### Required Tools (NO Docker needed!)

```bash
# AWS CLI
aws --version

# eksctl (for cluster management)
eksctl version

# kubectl (for Kubernetes)
kubectl version

# Helm (for package management)
helm version
```

### AWS Setup

```bash
# Configure AWS credentials
aws configure

# Verify AWS access
aws sts get-caller-identity
```

### GitHub Repository

- This project code in a GitHub repository
- Admin access to configure repository secrets

---

## Part 1: Configure AWS and GitHub (One-Time Setup)

### Step 1: Create AWS IAM User for GitHub Actions

#### 1.1 Create the IAM User

```bash
# Login to AWS Console
# Navigate to: IAM → Users → Create User

# User name: github-actions-ecr
# Access type: Programmatic access (NOT console access)
```

#### 1.2 Attach ECR Permissions

You have two options:

**Option A: Use AWS Managed Policy (Easier)**
- Attach policy: `AmazonEC2ContainerRegistryPowerUser`

**Option B: Create Custom Policy (More Restrictive)**

Create a custom policy with these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:CreateRepository",
        "ecr:DescribeRepositories"
      ],
      "Resource": "*"
    }
  ]
}
```

#### 1.3 Save Credentials

After creating the user, **save these immediately**:
- **Access Key ID** (e.g., `AKIAIOSFODNN7EXAMPLE`)
- **Secret Access Key** (e.g., `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`)

⚠️ **You cannot retrieve the secret key later!**

---

### Step 2: Add Secrets to GitHub Repository

#### 2.1 Navigate to Repository Settings

```
Your GitHub Repo → Settings → Secrets and variables → Actions → New repository secret
```

#### 2.2 Add These Secrets

| Secret Name | Value | Example |
|-------------|-------|---------|
| `AWS_ACCESS_KEY_ID` | Your IAM user access key | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | Your IAM user secret key | `wJalrXUtnFEMI/K7MDENG...` |

Click "New repository secret" for each one.

#### 2.3 Verify Secrets

You should see in your repository settings:
```
AWS_ACCESS_KEY_ID          Updated X minutes ago
AWS_SECRET_ACCESS_KEY      Updated X minutes ago
```

---

### Step 3: Push Workflows to Trigger First Build

The workflows are already in your repository at `.github/workflows/`. Let's trigger them!

#### 3.1 Commit and Push (if needed)

```bash
# If workflows aren't already committed
git add .github/workflows/
git commit -m "Add GitHub Actions CI workflows for image builds"
git push origin main
```

#### 3.2 Watch the Build

Navigate to your repository:
```
GitHub Repo → Actions → "Build and Push Dawn Images"
```

You'll see the workflow running in real-time!

Each workflow takes ~2-3 minutes to:
1. Check out code
2. Configure AWS credentials
3. Log into ECR
4. Build Docker image
5. Tag image (latest, rc, git-sha)
6. Push to ECR

---

### Step 4: Verify Images in ECR

#### Via AWS Console:
```
AWS Console → ECR → Repositories → dawn
```

You should see images tagged:
- `latest`
- `rc`
- `<git-sha>` (e.g., `f0ee2c4a`)

#### Via AWS CLI:
```bash
aws ecr list-images --repository-name dawn --region us-east-1

# Expected output:
# {
#   "imageIds": [
#     { "imageTag": "latest" },
#     { "imageTag": "rc" },
#     { "imageTag": "f0ee2c4a" }
#   ]
# }
```

✅ **CI is working! Images are now in ECR.**

---

## Part 2: Deploy Using CI-Built Images

Now that GitHub Actions is building your images automatically, let's deploy them to EKS.

### Step 1: Create EKS Cluster (~20 minutes)

```bash
cd foundation/provisioning/manual

./create-dawn-cluster.sh us-east-1
```

This creates:
- `dawn-cluster` with 2 spot nodes
- VPC, subnets, security groups
- IAM roles

**Verify:**
```bash
kubectl get nodes
# Should show 2 nodes
```

---

### Step 2: Install AWS Load Balancer Controller (~5 minutes)

```bash
./install-alb-controller-dawn.sh us-east-1
```

**Verify:**
```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
# Should show 2/2 ready
```

---

### Step 3: Deploy Services (~5 minutes)

```bash
./deploy-dawn.sh us-east-1
```

This deploys both production and RC tiers using the images from ECR that GitHub Actions built.

**Note:** You skip the `build-and-push-dawn.sh` step because GitHub Actions already built the images!

**Verify:**
```bash
# Check pods are running
kubectl get pods -n dawn-ns
kubectl get pods -n dawn-rc-ns

# Should show:
# NAME                    READY   STATUS    RESTARTS   AGE
# dawn-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
```

---

### Step 4: Test Your Service (~3 minutes)

#### Wait for ALB to provision
```bash
# Check ingress (will be <pending> for 2-3 minutes)
kubectl get ingress dawn-ingress -n dawn-ns

# Once you see a hostname:
# k8s-dawnclus-abc123.us-east-1.elb.amazonaws.com
```

#### Test endpoints
```bash
# Get ALB URL
ALB_URL=$(kubectl get ingress dawn-ingress -n dawn-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test production
curl http://$ALB_URL/
curl http://$ALB_URL/health
curl http://$ALB_URL/info

# Expected response:
# {
#   "service": "Dawn",
#   "message": "Welcome to the Dawn service",
#   "version": "1.0.0"
# }
```

---

## Complete Workflow Summary

```bash
# === ONE-TIME SETUP ===
# 1. Create IAM user for GitHub Actions
# 2. Add AWS secrets to GitHub repository
# 3. Push code to trigger first build

# === DEPLOY CLUSTER (30 minutes) ===
cd foundation/provisioning/manual

# Create cluster
./create-dawn-cluster.sh us-east-1

# Install ALB controller
./install-alb-controller-dawn.sh us-east-1

# Skip build - images already in ECR from CI!

# Deploy services
./deploy-dawn.sh us-east-1

# === TEST ===
curl http://$(kubectl get ingress dawn-ingress -n dawn-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/health
```

**Total time:** ~1 hour (including CI setup)

---

## CI/CD Workflow: Making Changes

Now when you update code, the workflow is completely automated:

```bash
# 1. Edit service code
vim foundation/services/dawn/main.py

# 2. Commit and push
git add foundation/services/dawn/
git commit -m "Update Dawn service message"
git push

# 3. GitHub Actions automatically:
#    ✅ Detects changes to foundation/services/dawn/**
#    ✅ Builds new Docker image
#    ✅ Pushes to ECR with :latest tag
#    ✅ Takes ~2-3 minutes
#
# Watch the build: GitHub Repo → Actions

# 4. Update deployment to use new image
kubectl rollout restart deployment/dawn -n dawn-ns

# 5. Verify new version deployed
kubectl rollout status deployment/dawn -n dawn-ns

# 6. Test the change
curl http://$ALB_URL/
```

---

## How GitHub Actions Works

### Workflow Triggers

The workflows automatically run when:

**Dawn Service:**
- Push to `main` or `claude/**` branches
- Changes in `foundation/services/dawn/**`
- Manual trigger via GitHub UI

**Day Service:**
- Push to `main` or `claude/**` branches
- Changes in `foundation/services/day/**`

**Dusk Service:**
- Push to `main` or `claude/**` branches
- Changes in `foundation/services/dusk/**`

### Manual Trigger

You can manually trigger a build anytime:

```
GitHub Repo → Actions → Select workflow → Run workflow
```

### What Each Workflow Does

Every time you push code changes:

1. ✅ Checks out code from GitHub
2. ✅ Configures AWS credentials (using secrets)
3. ✅ Logs into ECR
4. ✅ Creates ECR repository (if it doesn't exist)
5. ✅ Builds Docker image
6. ✅ Tags with `latest`, `rc`, and git SHA
7. ✅ Pushes all tags to ECR

---

## Image Tagging Strategy

| Tag | Purpose | Example | When to Use |
|-----|---------|---------|-------------|
| `latest` | Latest stable build | `dawn:latest` | Production deployments (auto-updates) |
| `rc` | Release candidate | `dawn:rc` | RC tier testing |
| `<git-sha>` | Specific version | `dawn:f0ee2c4a` | Rollback to known good version |

> 💡 **Learning Pattern: Mutable Tags**
>
> We use `:latest` and `:rc` tags that get overwritten on each build.
>
> **For production:** Many teams use **only immutable tags** (git SHA or semver):
> ```yaml
> # Deployment references specific version
> image: 123456789.dkr.ecr.us-east-1.amazonaws.com/dawn:sha-f0ee2c4a
> ```
>
> **Benefits:**
> - Guaranteed deployment consistency
> - Easier rollback (just change the tag)
> - Clear deployment history
>
> **The workflows already create SHA tags!** To use them:
> ```bash
> # Get the latest SHA tag
> SHA=$(git rev-parse --short HEAD)
>
> # Update deployment to use that specific SHA
> kubectl set image deployment/dawn dawn=$ECR_REGISTRY/dawn:$SHA -n dawn-ns
> ```

---

## Architecture

```
Developer
    ↓
Edit code locally
    ↓
git add, commit, push
    ↓
GitHub Repository
    ↓
GitHub Actions (CI)
    ├─ Checkout code
    ├─ Build Docker image
    ├─ Push to ECR
    └─ Tag: latest, rc, sha-abc123
         ↓
    Amazon ECR (Image Registry)
         ↓
kubectl rollout restart
         ↓
    Amazon EKS (Kubernetes Cluster)
         ├─ Pulls new image from ECR
         ├─ Performs rolling update
         └─ Pods restart with new code
              ↓
         Application Load Balancer
              ↓
         Internet Users
```

---

## Troubleshooting

### Workflow fails with "could not find any file"

**Problem:** GitHub Actions can't find the Dockerfile or service code.

**Solution:**
```bash
# Check that service code exists
ls -la foundation/services/dawn/

# Should show:
# Dockerfile
# main.py
# requirements.txt
```

---

### "Unable to locate credentials"

**Problem:** GitHub secrets not configured correctly.

**Solution:**
- Verify secrets exist: GitHub Repo → Settings → Secrets and variables → Actions
- Check secret names match **exactly**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
- Ensure there are no extra spaces in the values

---

### "AccessDenied" when pushing to ECR

**Problem:** IAM user lacks ECR permissions.

**Solution:**
```bash
# AWS Console → IAM → Users → github-actions-ecr → Permissions
# Ensure policy is attached: AmazonEC2ContainerRegistryPowerUser
```

---

### Images not appearing in ECR

**Problem:** Build succeeded but images aren't in ECR.

**Solution:**
```bash
# 1. Check workflow completed successfully
# GitHub Repo → Actions → View build logs

# 2. Verify AWS region matches
# Workflows use us-east-1 by default

# 3. Check repository name matches service name
aws ecr describe-repositories --region us-east-1

# 4. Verify you're looking at the right AWS account
aws sts get-caller-identity
```

---

### Pods show ImagePullBackOff after deployment

**Problem:** Kubernetes can't pull the image from ECR.

**Solution:**
```bash
# Describe the pod to see the error
kubectl describe pod -n dawn-ns <pod-name>

# Common causes:
# 1. Image not in ECR (check GitHub Actions completed)
# 2. Wrong image URL in deployment
# 3. ECR repository in different region
# 4. Node IAM role lacks ECR pull permissions

# Verify image exists
aws ecr describe-images --repository-name dawn --region us-east-1
```

---

## Viewing Build Logs

Detailed logs are available in GitHub:

```
GitHub Repo → Actions → Click on workflow run → Click on job
```

You'll see:
- Checkout logs
- Docker build output
- ECR push confirmation
- Any errors

---

## Monitoring and Notifications

### Check Build Status

```
GitHub Repo → Actions
```

Green checkmark = build succeeded
Red X = build failed

### Add Slack Notifications (Optional)

Add to your workflow to get notified of failures:

```yaml
# .github/workflows/build-dawn.yml
- name: Notify on failure
  if: failure()
  run: |
    echo "Build failed! Check Actions tab"
    # Add Slack webhook or email notification here
```

---

## ✅ What You Learned

Congratulations! You've set up a complete CI/CD pipeline:

- [x] Configured GitHub Actions for automated builds
- [x] Set up AWS IAM permissions for CI/CD
- [x] Automated Docker image builds on every push
- [x] Deployed applications using CI-built images
- [x] Understood image tagging strategies
- [x] Troubleshooted common CI/CD issues

**Key concepts mastered:**
- GitHub Actions workflows and triggers
- AWS IAM for CI/CD access
- ECR image registry
- Automated build pipelines
- Image tagging and versioning
- CI/CD best practices

---

## Next Steps

### Enhance Your CI/CD Pipeline

1. **Image Deployment Workflow**
   - See [image-deployment-workflow.md](./image-deployment-workflow.md) for advanced deployment strategies

2. **Add Image Scanning**
   - Scan for vulnerabilities before pushing to ECR
   - Tools: Trivy, Snyk, AWS ECR scanning

3. **Implement GitOps**
   - ArgoCD or Flux for declarative deployments
   - Automatic deployment when manifests change

4. **Add Automated Testing**
   - Run unit tests before building images
   - Integration tests before deployment

### Explore Other Topics

- **Infrastructure as Code:** [../02-infrastructure-as-code/](../02-infrastructure-as-code/)
- **Application Management:** [../03-application-management/](../03-application-management/)
- **Kubernetes Deep Dives:** [../05-kubernetes-deep-dives/](../05-kubernetes-deep-dives/)

---

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [AWS ECR Documentation](https://docs.aws.amazon.com/ecr/)
- [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials)
- [aws-actions/amazon-ecr-login](https://github.com/aws-actions/amazon-ecr-login)
- [Docker build-push-action](https://github.com/docker/build-push-action)

---

**Questions or issues?** Check our [troubleshooting guide](../06-troubleshooting/common-issues.md).
