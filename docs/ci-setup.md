# CI Setup Guide - GitHub Actions for Image Builds

This guide shows you how to set up GitHub Actions to automatically build Docker images and push them to AWS ECR.

**Benefits:**
- ✅ No Docker required on your laptop
- ✅ Automatic builds on every push
- ✅ Consistent build environment
- ✅ Free (GitHub Actions generous free tier)
- ✅ Images tagged with git SHA for tracking

## Prerequisites

1. **GitHub repository** for this project
2. **AWS Account** with ECR access
3. **AWS IAM User** with ECR permissions

## Step 1: Create AWS IAM User for GitHub Actions

### 1.1 Create IAM User

```bash
# Login to AWS Console
# Navigate to: IAM → Users → Create User

# User name: github-actions-ecr
# Access type: Programmatic access (not console)
```

### 1.2 Attach ECR Permissions

Create a custom policy for ECR:

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

Or use AWS managed policy: `AmazonEC2ContainerRegistryPowerUser`

### 1.3 Save Credentials

After creating the user, save:
- **Access Key ID** (e.g., `AKIAIOSFODNN7EXAMPLE`)
- **Secret Access Key** (e.g., `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`)

⚠️ **Save these now** - you can't retrieve the secret key later!

## Step 2: Add Secrets to GitHub Repository

### 2.1 Navigate to Repository Settings

```
GitHub Repo → Settings → Secrets and variables → Actions → New repository secret
```

### 2.2 Add These Secrets

| Secret Name | Value | Example |
|-------------|-------|---------|
| `AWS_ACCESS_KEY_ID` | Your IAM user access key | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | Your IAM user secret key | `wJalrXUtnFEMI/K7MDENG...` |

### 2.3 Verify Secrets

You should see:
```
AWS_ACCESS_KEY_ID          Updated X minutes ago
AWS_SECRET_ACCESS_KEY      Updated X minutes ago
```

## Step 3: Push Code to Trigger Workflow

### 3.1 Commit and Push

```bash
# Add workflows to git
git add .github/workflows/

# Commit
git commit -m "Add GitHub Actions CI workflows for image builds"

# Push to trigger workflow
git push origin main
```

### 3.2 Watch the Build

Navigate to your repo:
```
GitHub Repo → Actions → Build and Push Dawn Images
```

You'll see the workflow running in real-time!

## Step 4: Verify Images in ECR

### Via AWS Console:
```
AWS Console → ECR → Repositories → dawn
```

You should see images tagged:
- `latest`
- `rc`
- `<git-sha>` (e.g., `f0ee2c4a...`)

### Via AWS CLI:
```bash
aws ecr list-images --repository-name dawn --region us-east-1
```

## Workflow Triggers

The workflows automatically run when:

### Dawn Service:
- Push to `main` or `claude/**` branches
- Changes in `foundation/services/dawn/**`
- Manual trigger via GitHub UI

### Day Service:
- Push to `main` or `claude/**` branches
- Changes in `foundation/services/day/**`

### Dusk Service:
- Push to `main` or `claude/**` branches
- Changes in `foundation/services/dusk/**`

## Manual Trigger

You can manually trigger a build:

```
GitHub Repo → Actions → Select workflow → Run workflow
```

## What Gets Built

Each workflow:
1. ✅ Checks out code
2. ✅ Configures AWS credentials
3. ✅ Logs into ECR
4. ✅ Creates ECR repository (if needed)
5. ✅ Builds Docker image
6. ✅ Tags with `latest`, `rc`, and git SHA
7. ✅ Pushes all tags to ECR

## Image Tagging Strategy

| Tag | Purpose | Example |
|-----|---------|---------|
| `latest` | Production deployments | `dawn:latest` |
| `rc` | RC tier deployments | `dawn:rc` |
| `<git-sha>` | Specific version tracking | `dawn:f0ee2c4a` |

This allows:
- **Prod** uses `:latest` (auto-updates on merge)
- **RC** uses `:rc` (test before prod)
- **Rollback** uses specific SHA (pin to known good version)

## Troubleshooting

### Workflow fails with "could not find any file"
- Check that service code exists in `foundation/services/<service>/`
- Verify Dockerfile exists

### "Unable to locate credentials"
- Verify GitHub secrets are set correctly
- Check secret names match exactly: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`

### "AccessDenied" when pushing to ECR
- Verify IAM user has ECR permissions
- Check the IAM policy is attached to the user

### Images not appearing in ECR
- Check workflow completed successfully in Actions tab
- Verify AWS region matches (`us-east-1`)
- Check repository name matches service name

## Viewing Build Logs

```
GitHub Repo → Actions → Click on workflow run → Click on job
```

You'll see detailed logs for each step.

## Next Steps

After CI is working:

1. **Deploy to EKS** - Use the images built by CI
2. **Add image scanning** - Scan for vulnerabilities
3. **Add notifications** - Slack/email on build status
4. **Optimize builds** - Use build cache for faster builds

## Modified Deployment Workflow

Since images are now built automatically:

```bash
# 1. Create EKS cluster
./create-dawn-cluster.sh us-east-1

# 2. Install ALB controller
./install-alb-controller-dawn.sh us-east-1

# 3. Skip build - images already in ECR from CI!

# 4. Deploy to cluster
./deploy-dawn.sh us-east-1
```

No Docker installation needed on your laptop!

## Monitoring Builds

Set up notifications:

```yaml
# Add to workflow
- name: Notify on failure
  if: failure()
  run: |
    echo "Build failed! Check Actions tab"
    # Add Slack webhook, email, etc.
```

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [AWS ECR Documentation](https://docs.aws.amazon.com/ecr/)
- [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials)
- [aws-actions/amazon-ecr-login](https://github.com/aws-actions/amazon-ecr-login)
