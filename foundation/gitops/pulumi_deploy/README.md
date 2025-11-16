# Day Service Application - Pulumi Program

This directory contains the Pulumi program for managing the **Day service application resources** on Kubernetes.

## What This Manages

✅ **Deployment** - Pod template, replicas, rolling update strategy
✅ **Service** - ClusterIP service for internal load balancing
✅ **ConfigMap** - Application configuration (env vars)
✅ **HorizontalPodAutoscaler** - Auto-scaling based on CPU/memory
✅ **Ingress** - External access via AWS ALB

## What This Does NOT Manage

❌ **EKS Cluster** - Managed by `foundation/provisioning/pulumi/` (infrastructure team)
❌ **VPC/Networking** - Managed by `foundation/provisioning/pulumi/`
❌ **Node Groups** - Managed by `foundation/provisioning/pulumi/`
❌ **ALB Controller** - Managed by `foundation/provisioning/pulumi/`

## Setup

### 1. Install Dependencies

```bash
cd foundation/gitops/pulumi_deploy
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### 2. Configure Kubernetes Access

**Option A: Use kubeconfig from infrastructure stack** (recommended for CI/CD)

Edit `Pulumi.production.yaml`:
```yaml
kubernetes:kubeconfig:
  fn::stackReference:
    name: your-org/infrastructure/production
    output: kubeconfig
```

**Option B: Use local kubeconfig** (recommended for local development)

```bash
# Get kubeconfig from your EKS cluster
aws eks update-kubeconfig --name day-cluster-eksCluster-f3c27b8 --region us-east-1

# Or from infrastructure Pulumi stack
cd ../../../pulumi
pulumi stack output kubeconfig --show-secrets > ~/.kube/day-cluster-config
export KUBECONFIG=~/.kube/day-cluster-config
```

### 3. Initialize Stack

```bash
cd foundation/gitops/pulumi_deploy

# Create dev stack
pulumi stack init dev

# Or create production stack
pulumi stack init production
```

## Deployment

### Preview Changes

```bash
pulumi stack select dev  # or production
pulumi preview
```

This shows what resources will be created/updated/deleted.

### Deploy

```bash
pulumi up
```

Review the preview, then select `yes` to deploy.

### View Outputs

```bash
pulumi stack output
```

Outputs include:
- `alb_hostname` - The ALB DNS name to access your service
- `deployment_name` - Name of the Deployment
- `service_name` - Name of the Service
- `hpa_name` - Name of the HPA
- `namespace` - Kubernetes namespace
- `replicas` - Current replica count

## Common Operations

### Update Image Version

```bash
# Set new image tag
pulumi config set image_tag v1.2.4

# Deploy (triggers rolling update)
pulumi up
```

### Scale Application

```bash
# Change replica count
pulumi config set replicas 10

# Deploy
pulumi up
```

### Adjust Autoscaling

```bash
# Change max replicas
pulumi config set max_replicas 30

# Change CPU target
pulumi config set cpu_target 60

# Deploy
pulumi up
```

### Update Environment Variables

```bash
# Change log level
pulumi config set log_level DEBUG

# Deploy (triggers rolling update of pods)
pulumi up
```

### Switch Between Environments

```bash
# Deploy to dev
pulumi stack select dev
pulumi up

# Deploy to production
pulumi stack select production
pulumi up
```

## CI/CD Integration

### GitHub Actions Example

Create `.github/workflows/deploy-day-service.yml`:

```yaml
name: Deploy Day Service

on:
  push:
    branches: [main]
    paths:
      - 'foundation/gitops/pulumi_deploy/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Install Dependencies
        run: |
          cd foundation/gitops/pulumi_deploy
          pip install -r requirements.txt

      - name: Deploy to Production
        uses: pulumi/actions@v4
        with:
          work-dir: foundation/gitops/pulumi_deploy
          stack-name: production
          command: up
        env:
          PULUMI_ACCESS_TOKEN: ${{ secrets.PULUMI_ACCESS_TOKEN }}
```

## Stack Configuration Reference

### Development (`Pulumi.dev.yaml`)
- Namespace: `dev`
- Replicas: 1
- Min/Max replicas: 1-3
- Resources: Small (50m CPU, 64Mi memory)
- Log level: DEBUG

### Production (`Pulumi.production.yaml`)
- Namespace: `production`
- Replicas: 5
- Min/Max replicas: 3-20
- Resources: Large (200m-1000m CPU, 256Mi-1Gi memory)
- Log level: INFO

## Workflow

### Development Workflow

```bash
# 1. Make changes to __main__.py or config
vim __main__.py

# 2. Preview changes
pulumi preview

# 3. Deploy to dev
pulumi stack select dev
pulumi up

# 4. Test in dev environment
curl http://$(pulumi stack output alb_hostname)/health

# 5. If working, deploy to production
pulumi stack select production
pulumi config set image_tag v1.2.5
pulumi up
```

### Production Deployment Workflow

```bash
# 1. Update image tag in stack config
pulumi stack select production
pulumi config set image_tag v1.2.5

# 2. Preview changes
pulumi preview

# 3. Create PR with changes to Pulumi.production.yaml
git add Pulumi.production.yaml
git commit -m "Update day-service to v1.2.5"
git push

# 4. Merge PR → GitHub Actions automatically runs pulumi up
```

## Troubleshooting

### "No resources to update" but you made changes

```bash
# Refresh state
pulumi refresh
pulumi preview
```

### Can't connect to cluster

```bash
# Verify kubeconfig
kubectl get nodes

# Or update kubeconfig
aws eks update-kubeconfig --name day-cluster-eksCluster-f3c27b8 --region us-east-1
```

### Deployment stuck in pending

```bash
# Check events
kubectl describe deployment day-service -n production

# Check pods
kubectl get pods -n production
kubectl describe pod <pod-name> -n production
```

### Want to see the generated Kubernetes YAML

```bash
# Pulumi doesn't generate YAML files, but you can inspect with kubectl
kubectl get deployment day-service -n production -o yaml
```

## Comparison: This Approach vs YAML

### Before (YAML):
```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: day-service
spec:
  replicas: 3  # Hardcoded
  template:
    spec:
      containers:
      - name: day
        image: day:latest  # Hardcoded
```

```bash
# Manual deployment
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f configmap.yaml
kubectl apply -f hpa.yaml
kubectl apply -f ingress.yaml
```

### Now (Pulumi):
```python
# __main__.py
replicas = config.get_int("replicas") or 3  # Configurable
image_tag = config.get("image_tag") or "latest"  # Configurable

deployment = k8s.apps.v1.Deployment(...)
```

```bash
# Type-safe deployment with preview
pulumi config set replicas 5
pulumi config set image_tag v1.2.3
pulumi preview  # See what will change
pulumi up       # Deploy all resources
```

## Next Steps

1. **Test in dev environment**
2. **Set up CI/CD pipeline**
3. **Add monitoring dashboards**
4. **Create similar structure for dusk-service**
5. **Add integration tests**

## Resources

- Main application code: `foundation/services/day/`
- Infrastructure Pulumi: `foundation/provisioning/pulumi/`
- Pulumi Kubernetes docs: https://www.pulumi.com/registry/packages/kubernetes/
