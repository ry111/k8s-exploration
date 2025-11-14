# Quick Start: Deploy Dawn with GitHub Actions CI

This guide uses **GitHub Actions** to build images automatically - no Docker installation needed on your laptop!

## Overview

**Your Learning Path:**
1. ✅ Set up GitHub Actions (CI)
2. ✅ Push code → Images automatically build → Push to ECR
3. ✅ Deploy EKS cluster
4. ✅ Deploy services (using CI-built images)

**Time:** ~1 hour total
**Cost:** ~$111-121/month (while cluster running)

## Prerequisites

### Required Tools (NO Docker needed!)

```bash
# AWS CLI
aws --version

# eksctl
eksctl version

# kubectl
kubectl version

# Helm
helm version
```

### AWS Setup

```bash
# Configure AWS credentials
aws configure

# Verify AWS access
aws sts get-caller-identity
```

## Step 1: Set Up GitHub Actions CI (~15 minutes)

### 1.1 Create AWS IAM User for GitHub

```bash
# AWS Console → IAM → Users → Create User
# Name: github-actions-ecr
# Attach policy: AmazonEC2ContainerRegistryPowerUser
```

Save the credentials:
- Access Key ID
- Secret Access Key

### 1.2 Add Secrets to GitHub

```
Your GitHub Repo → Settings → Secrets and variables → Actions
```

Add these secrets:
- `AWS_ACCESS_KEY_ID` = your access key
- `AWS_SECRET_ACCESS_KEY` = your secret key

**See [CI-SETUP.md](CI-SETUP.md) for detailed instructions**

### 1.3 Push Code to Trigger Build

```bash
# Commit the workflows (already in repo)
git add .github/workflows/
git commit -m "Add CI workflows"
git push origin main
```

### 1.4 Watch Build in GitHub

```
GitHub Repo → Actions → "Build and Push Dawn Images"
```

Wait ~2-3 minutes for build to complete.

### 1.5 Verify Images in ECR

```bash
# Check images were pushed
aws ecr list-images --repository-name dawn --region us-west-2
```

You should see tags: `latest`, `rc`, and a git SHA.

✅ **CI is working! Images are now in ECR.**

## Step 2: Create EKS Cluster (~20 minutes)

```bash
cd foundation/scripts

./create-dawn-cluster.sh us-west-2
```

This creates:
- dawn-cluster with 2 spot nodes
- VPC, subnets, security groups
- IAM roles

**Verify:**
```bash
kubectl get nodes
# Should show 2 nodes
```

## Step 3: Install AWS Load Balancer Controller (~5 minutes)

```bash
./install-alb-controller-dawn.sh us-west-2
```

**Verify:**
```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
# Should show 2/2 ready
```

## Step 4: Deploy Dawn Services (~5 minutes)

```bash
./deploy-dawn.sh us-west-2
```

This deploys both production and RC tiers using the images from ECR that GitHub Actions built.

**Verify:**
```bash
# Check pods are running
kubectl get pods -n dawn-ns
kubectl get pods -n dawn-rc-ns

# Check ingress
kubectl get ingress -n dawn-ns
kubectl get ingress -n dawn-rc-ns
```

## Step 5: Test Your Service (~3 minutes)

### Wait for ALB to provision
```bash
# This will be <pending> for 2-3 minutes
kubectl get ingress dawn-ingress -n dawn-ns

# Once you see a hostname:
# k8s-dawnclus-abc123.us-west-2.elb.amazonaws.com
```

### Test endpoints
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

## Complete Workflow

```bash
# Setup CI (one-time)
# 1. Create IAM user
# 2. Add GitHub secrets
# 3. Push code

# Deploy cluster (30 minutes)
cd foundation/scripts
./create-dawn-cluster.sh us-west-2
./install-alb-controller-dawn.sh us-west-2
./deploy-dawn.sh us-west-2

# Test
curl http://$(kubectl get ingress dawn-ingress -n dawn-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/health
```

## Making Changes

Now when you update code:

```bash
# 1. Edit service code
vim foundation/services/dawn/main.py

# 2. Commit and push
git add foundation/services/dawn/
git commit -m "Update Dawn service"
git push

# 3. GitHub Actions automatically:
#    - Builds new image
#    - Pushes to ECR with :latest tag
#
# (Watch build in GitHub Actions tab)

# 4. Update deployment to use new image
kubectl rollout restart deployment/dawn -n dawn-ns

# 5. Verify new version deployed
kubectl rollout status deployment/dawn -n dawn-ns
```

## What GitHub Actions Does

Every time you push code changes:

1. ✅ Detects changes to `foundation/services/dawn/**`
2. ✅ Spins up Ubuntu container
3. ✅ Builds Docker image
4. ✅ Tags with `latest`, `rc`, and git SHA
5. ✅ Pushes to ECR
6. ✅ Takes ~2-3 minutes

**You get:**
- ✅ No Docker on your laptop
- ✅ Consistent builds
- ✅ Version tracking (git SHA tags)
- ✅ Free (GitHub Actions free tier)

## Architecture

```
Code Change
    ↓
git push
    ↓
GitHub Actions (CI)
    ├─ Build Docker image
    ├─ Push to ECR
    └─ Tag: latest, rc, sha-abc123
         ↓
    ECR (Image Registry)
         ↓
kubectl rollout restart
         ↓
    EKS pulls new image
         ↓
    Pods restart with new code
```

## Cost Breakdown

| Item | Monthly Cost |
|------|--------------|
| EKS Control Plane | $73.00 |
| 2× t3.small spot | $9.08 |
| ALB | $21-26 |
| EBS | $3.20 |
| ECR | $0.06 |
| GitHub Actions | $0 (free tier) |
| **TOTAL** | **~$106-111/month** |

## Cleanup

```bash
# Delete everything
./cleanup-dawn.sh us-west-2

# Type: DELETE

# This removes:
# - EKS cluster
# - EC2 nodes
# - ALBs
# - ECR repository
```

## Troubleshooting

### GitHub Actions build fails

```
GitHub Repo → Actions → Click failed build → View logs
```

Common issues:
- GitHub secrets not set correctly
- IAM user lacks ECR permissions

### Pods show ImagePullBackOff

```bash
kubectl describe pod -n dawn-ns <pod-name>
```

Common issues:
- Image not in ECR (check GitHub Actions completed)
- Wrong image URL in deployment

### ALB not creating

```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

Common issues:
- ALB controller not installed
- Takes 2-3 minutes to provision

## Next Steps

After Dawn is working:

1. **Add Day and Dusk** - Same process for other services
2. **Pulumi** - Automate cluster creation
3. **ArgoCD** - Auto-deploy on manifest changes
4. **Monitoring** - Add Prometheus/Grafana
5. **Custom domains** - Point your domain to ALB

## Resources

- [CI Setup Guide](CI-SETUP.md) - Detailed CI configuration
- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [AWS ECR Docs](https://docs.aws.amazon.com/ecr/)

## What You Learned

✅ GitHub Actions CI/CD basics
✅ AWS ECR image registry
✅ EKS cluster creation
✅ Kubernetes deployments
✅ Application Load Balancers
✅ Modern cloud-native development workflow

No Docker on your laptop needed!
