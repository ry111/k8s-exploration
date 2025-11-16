# Health Check & Monitoring Scripts

Quick reference for monitoring and troubleshooting Dawn cluster.

## Scripts Overview

### 1. `health-check-dawn.sh` - Comprehensive Health Check

**Usage:**
```bash
./foundation/gitops/manual_deploy/health-check-dawn.sh [region]
```

**What it checks:**
- ✅ Cluster connectivity
- ✅ Node status (ready/not ready)
- ✅ ALB Controller status
- ✅ Pod status (production + RC)
- ✅ Service endpoints
- ✅ Ingress/ALB provisioning
- ✅ Application health endpoints
- ✅ HPA configuration

**Output:** Detailed report with pass/fail for each check

**Exit codes:**
- `0` - All checks passed
- `1` - Some issues detected
- `2` - Critical issues

**Example:**
```bash
./foundation/gitops/manual_deploy/health-check-dawn.sh us-east-1

# Sample output:
# ✓ Cluster dawn-cluster exists
# ✓ 2/2 nodes ready
# ✓ ALB Controller running (2/2)
# ✓ 2/2 pods running
# ✓ Production /health endpoint responding (200)
# All systems operational!
```

### 2. `quick-status-dawn.sh` - Fast Status Check

**Usage:**
```bash
./foundation/gitops/manual_deploy/quick-status-dawn.sh [region]
```

**What it shows:**
- Node count (ready/total)
- Pod count (running/total)
- ALB URL
- Quick health check
- Test command

**Example output:**
```
Nodes:     2/2 Ready
Pods:      2/2 Running (prod)
RC Pods:   1/1 Running
ALB:       k8s-dawncluster-abc123.us-east-1.elb.amazonaws.com
Health:    ✓ OK (200)

Test command:
curl -H "Host: dawn.example.com" http://k8s-dawncluster-abc123.us-east-1.elb.amazonaws.com/health
```

**Use when:** You just want a quick status snapshot

### 3. `watch-dawn.sh` - Real-time Monitoring

**Usage:**
```bash
./foundation/gitops/manual_deploy/watch-dawn.sh [region]
```

**What it does:**
- Refreshes every 2 seconds
- Shows live view of:
  - Nodes
  - Pods (production + RC)
  - Ingress
  - HPA

**Use when:** Deploying changes or troubleshooting issues in real-time

**Press Ctrl+C to exit**

### 4. `test-dawn-app.sh` - Application Test Suite

**Usage:**
```bash
./foundation/gitops/manual_deploy/test-dawn-app.sh [region]
```

**What it tests:**
- ✅ Production endpoints (/, /health, /info)
- ✅ RC endpoints
- ✅ Load balancing (calls endpoint 10× to verify distribution)
- ✅ Performance (measures response times)

**Example output:**
```
Testing ALB: k8s-dawncluster-abc123.us-east-1.elb.amazonaws.com

Testing / ... ✓ 200
{
  "service": "Dawn",
  "message": "Welcome to the Dawn service",
  "version": "1.0.0"
}

=== Load Balancing Test ===
1. Pod: dawn-6b8df4797b-fp2zp
2. Pod: dawn-6b8df4797b-mkz68
3. Pod: dawn-6b8df4797b-fp2zp
...

Average response time: 45ms
✓ Excellent (<100ms)
```

**Use when:** Validating a deployment or checking application behavior

### 5. `troubleshoot-dawn.sh` - Troubleshooting Assistant

**Usage:**
```bash
./foundation/gitops/manual_deploy/troubleshoot-dawn.sh [region]
```

**What it checks:**
1. **Pod problems** - Identifies pods not running, shows events and logs
2. **Ingress issues** - Checks ALB provisioning status
3. **ALB controller** - Shows recent logs
4. **Service endpoints** - Verifies service is finding pods
5. **Node resources** - Shows CPU/memory usage
6. **Common solutions** - Provides fixes for typical issues

**Example output:**
```
1. Checking for pod problems...
Found problematic pods:
dawn-6b8df4797b-xyz12   0/1     ImagePullBackOff   0          2m

Details for pod: dawn-6b8df4797b-xyz12
Events:
  Failed to pull image "dawn:latest": rpc error: code = Unknown desc = Error response from daemon: pull access denied

Common Issues & Solutions:
Issue: Pods in ImagePullBackOff
  → Check if images exist in ECR:
    aws ecr list-images --repository-name dawn --region us-east-1
```

**Use when:** Something is broken and you need to diagnose

## Quick Reference

### Daily Health Check
```bash
# Fast check before starting work
./quick-status-dawn.sh
```

### After Deployment
```bash
# Watch rollout in real-time
./watch-dawn.sh

# When pods are ready, run full test suite
./test-dawn-app.sh
```

### When Something Breaks
```bash
# Run comprehensive health check
./health-check-dawn.sh

# If issues found, run troubleshooter
./troubleshoot-dawn.sh

# Watch live while fixing
./watch-dawn.sh
```

### CI/CD Integration

Add to your deployment pipeline:

```bash
# After kubectl apply, verify health
./health-check-dawn.sh us-east-1

# Exit code 0 = success, continue
# Exit code != 0 = failure, rollback
```

## What Each Script Does NOT Do

**These scripts do NOT:**
- ❌ Make changes to your cluster
- ❌ Fix issues automatically
- ❌ Deploy or update resources

**They only:**
- ✅ Read cluster state
- ✅ Test endpoints
- ✅ Display information
- ✅ Suggest solutions

## Customization

All scripts accept region as parameter:

```bash
./health-check-dawn.sh us-east-1   # Default region
./quick-status-dawn.sh eu-west-1   # Europe
```

Default region: `us-east-1`

## Troubleshooting the Scripts

### "Command not found"
```bash
chmod +x foundation/gitops/manual_deploy/*.sh
```

### "Cluster not found"
```bash
# Verify cluster exists
aws eks list-clusters --region us-east-1

# Update kubeconfig manually
aws eks update-kubeconfig --name dawn-cluster --region us-east-1
```

### "Permission denied"
```bash
# Verify AWS credentials
aws sts get-caller-identity

# Verify kubectl access
kubectl get nodes
```

## Integration with Monitoring

These scripts complement but don't replace:

- **Prometheus/Grafana** - Metrics over time
- **CloudWatch** - AWS-level monitoring
- **ArgoCD** - GitOps deployment status
- **DataDog/NewRelic** - APM tools

Use these scripts for:
- Quick manual checks
- CI/CD health gates
- Troubleshooting sessions
- Learning cluster behavior
