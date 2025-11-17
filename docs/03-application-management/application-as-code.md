# Managing Day Service Application Resources with Pulumi

## Overview

This guide shows you how to manage your **Day service Kubernetes application resources** (Deployment, Service, ConfigMap, HPA, Ingress) using **Pulumi** instead of YAML manifests.

### Configuration Approach Comparison

This project demonstrates **two configuration approaches** for Kubernetes resources:

| Service | Configuration Approach | Why |
|---------|------------------------|-----|
| **Dawn** | YAML (kubectl) | Learn Kubernetes fundamentals |
| **Day** ← You are here | Pulumi IaC | Application-as-code with type safety |
| **Dusk** | TBD | Exploring different deployment strategies |

**Day service** demonstrates managing applications as code with Pulumi instead of YAML manifests. Both Dawn and Day are automated via GitHub Actions (push-based deployment), but Pulumi offers type safety, preview capabilities, and programmatic infrastructure management.

## The Architecture: Two Separate Pulumi Programs

```
foundation/
├── provisioning/
│   └── pulumi/                      # Infrastructure Pulumi Program
│       ├── __main__.py              # Manages: EKS cluster, VPC, nodes, ALB controller
│       ├── Pulumi.yaml
│       └── Pulumi.production.yaml
│
└── gitops/
    └── pulumi_deploy/               # Application Pulumi Program (SEPARATE)
        ├── __main__.py              # Manages: Deployment, Service, ConfigMap, HPA, Ingress
        ├── Pulumi.yaml
        ├── Pulumi.day-production.yaml
        └── Pulumi.day-rc.yaml
```

### Why Separate Programs?

| Aspect | Infrastructure Program | Application Program |
|--------|----------------------|-------------------|
| **Manages** | EKS cluster, VPC, nodes | Deployments, Services, ConfigMaps |
| **Owned by** | Platform/DevOps team | Application team |
| **Changes** | Monthly | Daily/Hourly |
| **Impact** | Entire cluster | Single service |
| **Stack names** | `production` | `day-production`, `day-rc` |

## What Gets Managed

### ✅ Application Pulumi Program Manages:
- **Deployment** - Pod template, replicas, container image, health checks
- **Service** - ClusterIP service for internal routing
- **ConfigMap** - Application environment variables
- **HorizontalPodAutoscaler** - Auto-scaling rules
- **Ingress** - External access via ALB

### ❌ Application Pulumi Does NOT Manage:
- EKS Cluster (managed by `foundation/provisioning/pulumi/`)
- VPC/Networking (managed by `foundation/provisioning/pulumi/`)
- Node Groups (managed by `foundation/provisioning/pulumi/`)
- ALB Controller (managed by `foundation/provisioning/pulumi/`)

## Setup

### Prerequisites

1. **Infrastructure already deployed**
   ```bash
   cd foundation/provisioning/pulumi
   pulumi stack select production
   pulumi stack output cluster_name  # Should show: terminus
   ```

2. **Kubernetes access configured**
   ```bash
   # Option 1: Using AWS CLI
   aws eks update-kubeconfig --name terminus --region us-east-1

   # Option 2: Export from infrastructure stack
   cd foundation/provisioning/pulumi
   pulumi stack output kubeconfig --show-secrets > ~/.kube/terminus-config
   export KUBECONFIG=~/.kube/terminus-config

   # Verify
   kubectl get nodes
   ```

### Installation

```bash
# Navigate to application Pulumi directory
cd foundation/gitops/pulumi_deploy/pulumi

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Verify Pulumi installation
pulumi version
```

## Initialize Stacks

### Development Stack

```bash
cd foundation/gitops/pulumi_deploy

# Create day-rc stack
pulumi stack init day-rc

# Configuration is already set in Pulumi.day-rc.yaml
pulumi config
```

### Production Stack

```bash
# Create day-production stack
pulumi stack init day-production

# Configuration is already set in Pulumi.day-production.yaml
pulumi config
```

## Deploy Day Service Application

### First Deployment

```bash
# Select stack
pulumi stack select day-rc

# Preview what will be created
pulumi preview

# Expected output:
# Previewing update (day-rc)
#
#     Type                                         Name                    Plan
# +   pulumi:pulumi:Stack                          foundation-services-day-rc create
# +   ├─ kubernetes:core/v1:ConfigMap              day-service-config      create
# +   ├─ kubernetes:apps/v1:Deployment             day-service             create
# +   ├─ kubernetes:core/v1:Service                day-service             create
# +   ├─ kubernetes:autoscaling/v2:HorizontalPod   day-service-hpa         create
# +   └─ kubernetes:networking.k8s.io/v1:Ingress   day-service             create
#
# Resources:
#     + 6 to create

# Deploy
pulumi up

# Review and confirm with 'yes'
```

### View Outputs

```bash
pulumi stack output

# Expected outputs:
# Current stack outputs (6):
#     OUTPUT           VALUE
#     alb_hostname     k8s-production-dayservi-abc123.us-east-1.elb.amazonaws.com
#     deployment_name  day-service
#     hpa_name         day-service-hpa
#     image            your-registry/day-service:latest
#     namespace        dev
#     replicas         1
#     service_name     day-service
```

### Test the Deployment

```bash
# Get the ALB hostname
ALB_HOST=$(pulumi stack output alb_hostname)

# Test health endpoint (wait a few minutes for ALB to provision)
curl http://$ALB_HOST/health

# Check Kubernetes resources
kubectl get deployments,services,configmaps,hpa,ingress -n dev
```

## Common Operations

### 1. Update Application Image (Deploy New Version)

```bash
# Update image tag
pulumi config set image_tag v1.2.4

# Preview changes
pulumi preview

# Expected output:
# Previewing update (day-rc)
#
#     Type                                Name              Plan       Info
#     pulumi:pulumi:Stack                 foundation-services-day-rc
# ~   └─ kubernetes:apps/v1:Deployment    day-service       update     [diff: ~spec]
#
# Resources:
#     ~ 1 to update
#     5 unchanged

# Deploy (triggers rolling update)
pulumi up

# Watch the rolling update
kubectl rollout status deployment/day-service -n day-rc-ns
```

### 2. Scale Application

```bash
# Manual scaling (change base replica count)
pulumi config set replicas 5
pulumi up

# Adjust autoscaling limits
pulumi config set min_replicas 3
pulumi config set max_replicas 20
pulumi up

# View current scaling
kubectl get hpa -n dev
```

### 3. Update Environment Variables

```bash
# Update configuration
pulumi config set log_level DEBUG
pulumi config set cache_ttl "60"
pulumi up

# This triggers a rolling update because ConfigMap changed
kubectl rollout status deployment/day-service -n dev
```

### 4. Adjust Resources

```bash
# Update CPU/memory limits
pulumi config set cpu_limit "1000m"
pulumi config set memory_limit "1Gi"
pulumi up

# Triggers pod restart with new resource limits
```

### 5. Switch Between Environments

```bash
# Work on RC
pulumi stack select day-rc
pulumi config set image_tag v1.2.5-rc1
pulumi up

# Test in RC...

# Promote to production
pulumi stack select day-production
pulumi config set image_tag v1.2.5
pulumi preview  # Always preview first!
pulumi up
```

## Configuration Reference

All configuration is set in the stack-specific YAML files:

### RC (`Pulumi.day-rc.yaml`)

```yaml
config:
  foundation-services:namespace: day-rc-ns
  foundation-services:image_tag: rc
  foundation-services:replicas: 1
  foundation-services:min_replicas: 1
  foundation-services:max_replicas: 3
  foundation-services:cpu_request: 50m
  foundation-services:memory_request: 64Mi
  foundation-services:cpu_limit: 200m
  foundation-services:memory_limit: 256Mi
  foundation-services:log_level: DEBUG
  foundation-services:database_host: postgres.day-rc-ns.svc.cluster.local
```

### Production (`Pulumi.day-production.yaml`)

```yaml
config:
  foundation-services:namespace: day-ns
  foundation-services:image_tag: v1.2.3
  foundation-services:replicas: 5
  foundation-services:min_replicas: 3
  foundation-services:max_replicas: 20
  foundation-services:cpu_request: 200m
  foundation-services:memory_request: 256Mi
  foundation-services:cpu_limit: 1000m
  foundation-services:memory_limit: 1Gi
  foundation-services:log_level: INFO
  foundation-services:database_host: postgres.day-ns.svc.cluster.local
```

## Understanding the Code

### Key Sections in `__main__.py`

#### 1. Configuration Loading
```python
config = pulumi.Config()
image_tag = config.get("image_tag") or "latest"
replicas = config.get_int("replicas") or 3
# ... etc
```

#### 2. ConfigMap - Application Environment Variables
```python
config_map = k8s.core.v1.ConfigMap(
    f"{app_name}-config",
    metadata=k8s.meta.v1.ObjectMetaArgs(
        name=f"{app_name}-config",
        namespace=namespace,
        labels=labels,
    ),
    data={
        "LOG_LEVEL": log_level,
        "DATABASE_HOST": database_host,
        # ... your app config
    },
)
```

#### 3. Deployment - Pod Template & Strategy
```python
deployment = k8s.apps.v1.Deployment(
    app_name,
    spec=k8s.apps.v1.DeploymentSpecArgs(
        replicas=replicas,
        selector=k8s.meta.v1.LabelSelectorArgs(
            match_labels={"app": app_name},
        ),
        template=k8s.core.v1.PodTemplateSpecArgs(
            spec=k8s.core.v1.PodSpecArgs(
                containers=[
                    k8s.core.v1.ContainerArgs(
                        name=app_name,
                        image=f"{image_registry}/{app_name}:{image_tag}",
                        # ... container config
                    )
                ],
            ),
        ),
        strategy=k8s.apps.v1.DeploymentStrategyArgs(
            type="RollingUpdate",
            rolling_update=k8s.apps.v1.RollingUpdateDeploymentArgs(
                max_unavailable=1,
                max_surge=1,
            ),
        ),
    ),
)
```

#### 4. Service - Internal Load Balancing
```python
service = k8s.core.v1.Service(
    app_name,
    spec=k8s.core.v1.ServiceSpecArgs(
        type="ClusterIP",
        selector={"app": app_name},
        ports=[
            k8s.core.v1.ServicePortArgs(
                port=80,
                target_port=8080,
            )
        ],
    ),
)
```

#### 5. HPA - Autoscaling
```python
hpa = k8s.autoscaling.v2.HorizontalPodAutoscaler(
    f"{app_name}-hpa",
    spec=k8s.autoscaling.v2.HorizontalPodAutoscalerSpecArgs(
        scale_target_ref=k8s.autoscaling.v2.CrossVersionObjectReferenceArgs(
            api_version="apps/v1",
            kind="Deployment",
            name=app_name,
        ),
        min_replicas=min_replicas,
        max_replicas=max_replicas,
        metrics=[
            # CPU-based scaling
            k8s.autoscaling.v2.MetricSpecArgs(
                type="Resource",
                resource=k8s.autoscaling.v2.ResourceMetricSourceArgs(
                    name="cpu",
                    target=k8s.autoscaling.v2.MetricTargetArgs(
                        type="Utilization",
                        average_utilization=70,
                    ),
                ),
            ),
        ],
    ),
)
```

#### 6. Ingress - External Access
```python
ingress = k8s.networking.v1.Ingress(
    app_name,
    metadata=k8s.meta.v1.ObjectMetaArgs(
        annotations={
            "alb.ingress.kubernetes.io/scheme": "internet-facing",
            "alb.ingress.kubernetes.io/target-type": "ip",
            "alb.ingress.kubernetes.io/healthcheck-path": "/health",
        },
    ),
    spec=k8s.networking.v1.IngressSpecArgs(
        ingress_class_name="alb",
        rules=[
            k8s.networking.v1.IngressRuleArgs(
                http=k8s.networking.v1.HTTPIngressRuleValueArgs(
                    paths=[
                        k8s.networking.v1.HTTPIngressPathArgs(
                            path="/",
                            path_type="Prefix",
                            backend=k8s.networking.v1.IngressBackendArgs(
                                service=k8s.networking.v1.IngressServiceBackendArgs(
                                    name=app_name,
                                    port=k8s.networking.v1.ServiceBackendPortArgs(
                                        number=80,
                                    ),
                                ),
                            ),
                        )
                    ],
                ),
            )
        ],
    ),
)
```

## Workflow: Development to Production

### Step 1: Develop Locally
```bash
# Build and test your application code locally
cd foundation/gitops/pulumi_deploy/src
# ... develop and test ...
```

### Step 2: Deploy to Dev
```bash
cd foundation/gitops/pulumi_deploy/pulumi

# Select dev stack
pulumi stack select dev

# Set image tag (from your CI build)
pulumi config set image_tag v1.2.5-rc1

# Deploy
pulumi preview
pulumi up

# Get the dev URL
echo "Dev URL: http://$(pulumi stack output alb_hostname)"
```

### Step 3: Test in Dev
```bash
# Run integration tests against dev environment
ALB_HOST=$(pulumi stack output alb_hostname)
curl http://$ALB_HOST/health
curl http://$ALB_HOST/api/v1/status
```

### Step 4: Promote to Production
```bash
# Switch to production stack
pulumi stack select prod

# Set production image tag
pulumi config set image_tag v1.2.5

# Preview changes
pulumi preview

# Review carefully!
# Expected output:
#     Type                              Name           Plan       Info
#     pulumi:pulumi:Stack               day-service
# ~   └─ kubernetes:apps/v1:Deployment  day-service    update     [diff: ~spec]

# Deploy to production
pulumi up

# Monitor the rollout
kubectl rollout status deployment/day-service -n production
kubectl get pods -n production -w
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
  deploy-dev:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Update kubeconfig
        run: |
          aws eks update-kubeconfig --name terminus --region us-east-1

      - name: Install dependencies
        run: |
          cd foundation/gitops/pulumi_deploy/pulumi
          pip install -r requirements.txt

      - name: Deploy to RC
        uses: pulumi/actions@v4
        with:
          work-dir: foundation/gitops/pulumi_deploy
          stack-name: day-rc
          command: up
        env:
          PULUMI_ACCESS_TOKEN: ${{ secrets.PULUMI_ACCESS_TOKEN }}

  deploy-production:
    needs: deploy-rc
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    environment: production  # Requires approval
    steps:
      - uses: actions/checkout@v3

      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Update kubeconfig
        run: |
          aws eks update-kubeconfig --name terminus --region us-east-1

      - name: Install dependencies
        run: |
          cd foundation/gitops/pulumi_deploy/pulumi
          pip install -r requirements.txt

      - name: Deploy to Production
        uses: pulumi/actions@v4
        with:
          work-dir: foundation/gitops/pulumi_deploy
          stack-name: day-production
          command: up
        env:
          PULUMI_ACCESS_TOKEN: ${{ secrets.PULUMI_ACCESS_TOKEN }}
```

## Troubleshooting

### Can't connect to cluster

```bash
# Verify AWS credentials
aws sts get-caller-identity

# Update kubeconfig
aws eks update-kubeconfig --name terminus --region us-east-1

# Verify connection
kubectl get nodes
```

### Deployment stuck

```bash
# Check deployment status
kubectl describe deployment day-service -n day-rc-ns

# Check pod events
kubectl get pods -n day-rc-ns
kubectl describe pod <pod-name> -n day-rc-ns

# Check logs
kubectl logs -f deployment/day-service -n day-rc-ns
```

### Pulumi state conflicts

```bash
# Refresh state from cluster
pulumi refresh

# View current state
pulumi stack export
```

### Want to see generated Kubernetes YAML

```bash
# Pulumi doesn't generate YAML, but you can inspect with kubectl
kubectl get deployment day-service -n day-ns -o yaml
kubectl get service day-service -n day-ns -o yaml
```

## Comparison: Pulumi vs YAML

### Before (YAML approach):

**Multiple YAML files to manage:**
```bash
foundation/k8s/day/prod/
├── deployment.yaml      # 50 lines
├── service.yaml         # 20 lines
├── configmap.yaml       # 15 lines
├── hpa.yaml            # 25 lines
└── ingress.yaml        # 30 lines
```

**Deployment:**
```bash
kubectl apply -f foundation/k8s/day/prod/
```

**Problems:**
- ❌ No type checking
- ❌ No preview of changes
- ❌ Hard to share configuration across environments
- ❌ Manual variable substitution
- ❌ No dependency tracking

### After (Pulumi approach):

**Single Python program:**
```bash
foundation/gitops/pulumi_deploy/
├── __main__.py                 # Single file, type-safe
├── Pulumi.day-rc.yaml          # RC config
└── Pulumi.day-production.yaml  # Production config
```

**Deployment:**
```bash
pulumi config set image_tag v1.2.5
pulumi preview  # See what will change!
pulumi up
```

**Benefits:**
- ✅ Type-safe Python code
- ✅ Preview changes before applying
- ✅ Easy environment management
- ✅ IDE autocomplete and refactoring
- ✅ State tracking and drift detection
- ✅ Programmatic logic and loops

## Next Steps

1. **Customize the configuration** for your Day service
   ```bash
   cd foundation/gitops/pulumi_deploy
   vim Pulumi.day-rc.yaml  # Update image registry, etc.
   ```

2. **Deploy to RC**
   ```bash
   pulumi stack select day-rc
   pulumi up
   ```

3. **Test your deployment**
   ```bash
   curl http://$(pulumi stack output alb_hostname)/health
   ```

4. **Set up CI/CD** pipeline for automated deployments

5. **Create similar structure for dusk-service**
   ```bash
   cp -r foundation/gitops/pulumi_deploy foundation/applications/dusk-service
   # Update configuration
   ```

## Resources

- Day service Pulumi code: `foundation/gitops/pulumi_deploy/pulumi/__main__.py`
- Infrastructure Pulumi code: `foundation/provisioning/pulumi/__main__.py`
- Pulumi Kubernetes provider docs: https://www.pulumi.com/registry/packages/kubernetes/
- Kubernetes API reference: https://kubernetes.io/docs/reference/kubernetes-api/
