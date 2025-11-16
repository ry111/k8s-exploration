# CI/CD Image Deployment with Pulumi

## The Challenge

When using Pulumi to manage Kubernetes Deployments, you need to coordinate:
1. **Building** the Docker image (CI/CD)
2. **Pushing** to a registry (CI/CD)
3. **Updating** the Pulumi config with the new image tag
4. **Deploying** to Kubernetes via Pulumi

## Current Setup

Your current workflow only covers steps 1-2:

**`.github/workflows/build-day.yml`:**
```yaml
- Build Docker image with tag: ${{ github.sha }}
- Push to ECR
- Tags: <sha>, latest, rc
```

**Missing:** Steps 3-4 (updating Pulumi config and deploying)

## Solution Options

### Option 1: Sequential Jobs in One Workflow ⭐ (Recommended)

**Pros:**
- ✅ Atomic - build and deploy together
- ✅ Automatic deployment on merge
- ✅ Can add manual approval for production
- ✅ Single source of truth

**Cons:**
- ❌ Longer CI/CD pipeline
- ❌ Build failures block everything

**Example:** `.github/workflows/build-and-deploy-day.yml.example`

**Workflow:**
```
1. Push to main
   ↓
2. Build image → tag with git SHA
   ↓
3. Push to ECR
   ↓
4. Deploy to Dev (automatic)
   ↓
5. Deploy to Production (manual approval)
```

**Key Feature:** Uses Pulumi's `config-map` parameter to dynamically set image tag:

```yaml
- name: Deploy to Dev
  uses: pulumi/actions@v4
  with:
    command: up
    config-map: |
      {
        "image_tag": { "value": "${{ github.sha }}" }
      }
```

### Option 2: GitOps Approach

**Pros:**
- ✅ Clear audit trail in Git
- ✅ Separate build and deploy concerns
- ✅ Can review config changes before deploy
- ✅ Works with ArgoCD/Flux

**Cons:**
- ❌ More complex (2 workflows)
- ❌ Potential for config drift
- ❌ Extra commit per deployment

**Example:** `.github/workflows/build-and-commit-day.yml.example`

**Workflow:**
```
1. Push to main
   ↓
2. Build & push image
   ↓
3. Update Pulumi.dev.yaml in Git
   ↓
4. Commit change
   ↓
5. Separate workflow detects config change
   ↓
6. Runs pulumi up
```

**Two Workflows Needed:**

**Workflow 1: Build and update config**
```yaml
- Build image
- Update Pulumi.dev.yaml with new image_tag
- Commit and push
```

**Workflow 2: Deploy on config change**
```yaml
on:
  push:
    paths:
      - 'foundation/applications/day-service/pulumi/Pulumi.*.yaml'

jobs:
  deploy:
    - Run pulumi up
```

### Option 3: Manual Deployment

**Pros:**
- ✅ Full control over when to deploy
- ✅ Can test image before deploying
- ✅ Simple to understand
- ✅ Good for learning/experimentation

**Cons:**
- ❌ Manual step required
- ❌ Slower deployment
- ❌ Human error possible

**Script:** `foundation/scripts/deploy-image-version.sh`

**Workflow:**
```bash
# 1. CI builds and pushes image
git push origin main
# CI runs, outputs: "Pushed: <ecr-registry>/day:abc123"

# 2. Developer deploys manually
./foundation/scripts/deploy-image-version.sh dev abc123

# 3. Test in dev
curl http://$(pulumi stack output alb_hostname)/health

# 4. Deploy to production
./foundation/scripts/deploy-image-version.sh production abc123
```

### Option 4: Hybrid - Build Auto, Deploy Manual

**Pros:**
- ✅ Fast builds
- ✅ Controlled deployments
- ✅ Easy rollback

**Cons:**
- ❌ Manual deployment step

**Workflow:**
```yaml
# build-day.yml - runs automatically
on:
  push:
    paths: ['foundation/services/day/**']
jobs:
  build:
    - Build and push image
    - Output image tag

# deploy-day.yml - runs manually via workflow_dispatch
on:
  workflow_dispatch:
    inputs:
      image_tag:
        description: 'Image tag to deploy'
        required: true
      stack:
        description: 'Stack to deploy to'
        required: true
        default: 'dev'

jobs:
  deploy:
    - pulumi config set image_tag ${{ github.event.inputs.image_tag }}
    - pulumi up
```

## Comparison Table

| Approach | Automation | Control | Complexity | Audit Trail | Best For |
|----------|------------|---------|------------|-------------|----------|
| **Option 1: Sequential** | High | Medium | Low | Good | Production teams |
| **Option 2: GitOps** | High | High | High | Excellent | Large teams |
| **Option 3: Manual** | Low | High | Low | Manual | Learning/Testing |
| **Option 4: Hybrid** | Medium | High | Medium | Good | Small teams |

## Recommended Approach by Team Size

### Solo/Learning (You)
**Start with:** Option 3 (Manual)
```bash
# Simple, predictable, full control
./foundation/scripts/deploy-image-version.sh dev <sha>
```

**Graduate to:** Option 1 (Sequential) when ready
```yaml
# Automatic dev deployment, manual production approval
```

### Small Team (2-5 people)
**Use:** Option 4 (Hybrid)
- Auto build
- Manual deploy via workflow_dispatch
- Good balance of automation and control

### Large Team (5+ people)
**Use:** Option 1 or 2
- Full automation
- Manual approval gates
- Clear ownership

## Implementation Guide

### Implementing Option 1 (Recommended)

**Step 1: Create new workflow**
```bash
cp .github/workflows/build-and-deploy-day.yml.example \
   .github/workflows/build-and-deploy-day.yml
```

**Step 2: Update image registry**
```yaml
# Edit the file
vim .github/workflows/build-and-deploy-day.yml

# Update ECR_REPOSITORY to match your ECR repo name
env:
  ECR_REPOSITORY: day  # or your actual ECR repo name
```

**Step 3: Set up GitHub Environment**
```bash
# In GitHub UI: Settings → Environments → New environment
# Name: production
# Add protection rule: Required reviewers
```

**Step 4: Test in dev**
```bash
# Make a change to day service
vim foundation/services/day/main.py

# Commit and push
git add .
git commit -m "test: trigger build and deploy"
git push

# Watch GitHub Actions
# ✅ Build completes
# ✅ Dev deployment runs automatically
# ⏸️  Production deployment waits for approval
```

**Step 5: Approve production**
- Go to GitHub Actions
- Click on production deployment
- Click "Review deployments"
- Approve

## Image Tag Strategies

### 1. Git SHA (Current/Recommended)
```yaml
IMAGE_TAG: ${{ github.sha }}
```
**Pros:** Unique, traceable, immutable
**Cons:** Not human-friendly

### 2. Semantic Version
```yaml
IMAGE_TAG: v1.2.3
```
**Pros:** Human-readable
**Cons:** Requires version management

### 3. Timestamp
```yaml
IMAGE_TAG: ${{ github.run_number }}-$(date +%Y%m%d-%H%M%S)
```
**Pros:** Ordered, unique
**Cons:** No git traceability

### 4. Branch + SHA
```yaml
IMAGE_TAG: ${{ github.ref_name }}-${{ github.sha }}
```
**Pros:** Shows branch context
**Cons:** Longer tag names

### Recommendation
Use **Git SHA** for immutability and traceability:
```yaml
IMAGE_TAG: ${{ github.sha }}
```

## Rollback Strategies

### With Pulumi

**Option A: Change config and redeploy**
```bash
# Rollback to previous version
pulumi config set image_tag abc123  # previous SHA
pulumi up
```

**Option B: Use Pulumi history**
```bash
# View stack history
pulumi stack history

# Rollback to specific update
pulumi stack select production
pulumi cancel  # if needed
pulumi refresh
# Manually set to previous image tag
```

**Option C: kubectl (quick emergency)**
```bash
# Quick rollback (bypasses Pulumi)
kubectl rollout undo deployment/day-service -n production

# Then sync Pulumi config to match
pulumi config set image_tag <rolled-back-sha>
pulumi refresh
```

## Monitoring Deployments

### Track Deployment Progress

**In workflow:**
```yaml
- name: Wait for rollout
  run: |
    kubectl rollout status deployment/day-service -n dev --timeout=5m
```

**Locally:**
```bash
# Watch deployment
kubectl get pods -n production -w

# Check rollout status
kubectl rollout status deployment/day-service -n production

# View rollout history
kubectl rollout history deployment/day-service -n production
```

## Common Issues

### Issue 1: Image tag doesn't update

**Symptom:** `pulumi up` shows no changes even though you set new image_tag

**Solution:** Pulumi state might be out of sync
```bash
pulumi refresh
pulumi preview
```

### Issue 2: Old pods still running

**Symptom:** Deployment has new image but old pods remain

**Solution:** Check rolling update strategy
```bash
# Force recreate
kubectl rollout restart deployment/day-service -n production
```

### Issue 3: Config-map not working in GitHub Actions

**Symptom:** Config values not being set

**Solution:** Use proper JSON escaping
```yaml
config-map: |
  {
    "image_tag": { "value": "${{ needs.build.outputs.tag }}" }
  }
```

## Next Steps

1. **Choose your approach** based on team size and needs
2. **Implement the workflow** using the examples provided
3. **Test with a small change** to verify it works
4. **Add monitoring** to track deployment health
5. **Document your process** for team members

## Examples Location

- **Option 1 (Sequential):** `.github/workflows/build-and-deploy-day.yml.example`
- **Option 2 (GitOps):** `.github/workflows/build-and-commit-day.yml.example`
- **Option 3 (Manual):** `foundation/scripts/deploy-image-version.sh`

## Related Documentation

- [Application as Code Guide](application-as-code-guide.md) - Managing apps with Pulumi
- [Pulumi Setup](pulumi-setup.md) - Infrastructure setup
- [CI Setup](ci-setup.md) - General CI/CD configuration
