# Pulumi Resource Management Strategy for EKS

## The Question: What Should Pulumi Manage?

When using Pulumi with EKS for large-scale services, there's a critical decision: **which Kubernetes resources should be managed through Pulumi Infrastructure as Code, and which should be managed elsewhere?**

## TL;DR - The Golden Rule

**Pulumi manages INFRASTRUCTURE. GitOps/kubectl manages APPLICATIONS.**

```
┌─────────────────────────────────────────────────────┐
│ PULUMI MANAGES (Infrastructure Layer)              │
├─────────────────────────────────────────────────────┤
│ ✅ EKS Cluster                                      │
│ ✅ VPC, Subnets, Security Groups                    │
│ ✅ Node Groups / Managed Node Groups                │
│ ✅ IAM Roles & Policies                             │
│ ✅ OIDC Provider for IRSA                           │
│ ✅ ALB/Ingress Controller (Helm chart)              │
│ ✅ Cluster Autoscaler                               │
│ ✅ Metrics Server                                   │
│ ✅ External DNS                                     │
│ ✅ EBS CSI Driver                                   │
│ ✅ Service Accounts with IRSA                       │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ GITOPS/KUBECTL MANAGES (Application Layer)         │
├─────────────────────────────────────────────────────┤
│ ✅ Deployments                                      │
│ ✅ ReplicaSets (managed by Deployments)             │
│ ✅ Pods (managed by ReplicaSets)                    │
│ ✅ ConfigMaps (application config)                  │
│ ✅ Secrets (application secrets)                    │
│ ✅ Services (ClusterIP, NodePort)                   │
│ ✅ Ingresses (application routing)                  │
│ ✅ HorizontalPodAutoscalers (HPA)                   │
│ ✅ PersistentVolumeClaims                           │
│ ✅ CronJobs / Jobs                                  │
│ ✅ NetworkPolicies (application-level)              │
└─────────────────────────────────────────────────────┘
```

## Why This Separation Matters

### 1. **Different Lifecycles**

**Infrastructure (Pulumi):**
- Changes infrequently (weeks/months)
- Requires careful planning and review
- Has broad impact on entire cluster
- Managed by platform/DevOps team

**Applications (GitOps/kubectl):**
- Changes frequently (hours/days)
- Part of CI/CD pipeline
- Scoped to specific services
- Managed by application teams

### 2. **Different Ownership**

```
Platform Team             Application Teams
      ↓                          ↓
   Pulumi                    GitOps/Helm
      ↓                          ↓
  EKS Cluster    →    Deployments, ConfigMaps, etc.
```

### 3. **Blast Radius**

- **Pulumi changes**: Can affect entire cluster → needs rigorous approval
- **Application changes**: Isolated to namespace/service → faster iteration

## Current Setup (Your Repository)

Your current Pulumi code (`foundation/infrastructure/pulumi/__main__.py`) follows best practices:

```python
# ✅ CORRECTLY MANAGED BY PULUMI
- VPC and networking (lines 46-117)
- EKS cluster (lines 120-127)
- Managed node group (lines 130-143)
- IAM roles for ALB controller (lines 225-266)
- ALB controller Helm chart (lines 284-307)

# ❌ NOT in Pulumi (correctly managed elsewhere)
- Application Deployments
- ConfigMaps for apps
- Application Services/Ingresses
```

## Detailed Breakdown

### ✅ Resources Commonly Managed by Pulumi

#### 1. **Core Infrastructure**
```python
# VPC, Subnets, Internet Gateways
vpc = aws.ec2.Vpc(...)
subnet = aws.ec2.Subnet(...)

# EKS Cluster
cluster = eks.Cluster(...)

# Node Groups
node_group = aws.eks.NodeGroup(...)
```

**Why Pulumi?**
- Foundational infrastructure
- Changes require cluster-wide coordination
- Cross-team dependency
- Long-lived resources

#### 2. **Cluster Add-ons (via Helm)**
```python
# ALB/Ingress Controller
alb_controller = k8s.helm.v3.Release("aws-load-balancer-controller", ...)

# Cluster Autoscaler
cluster_autoscaler = k8s.helm.v3.Release("cluster-autoscaler", ...)

# External DNS
external_dns = k8s.helm.v3.Release("external-dns", ...)

# Metrics Server
metrics_server = k8s.helm.v3.Release("metrics-server", ...)
```

**Why Pulumi?**
- Cluster-scoped components
- Required for cluster functionality
- Managed by platform team
- Infrequent updates

#### 3. **IAM Roles & Service Accounts (IRSA)**
```python
# Service account with IAM role annotation
alb_service_account = k8s.core.v1.ServiceAccount(
    "aws-load-balancer-controller",
    metadata={
        "annotations": {
            "eks.amazonaws.com/role-arn": alb_role.arn,
        }
    }
)
```

**Why Pulumi?**
- Bridges K8s and AWS IAM
- Security-critical configuration
- Platform team responsibility

#### 4. **Cluster-Wide Resources**
```python
# Namespaces (for isolation)
production_namespace = k8s.core.v1.Namespace("production")

# ResourceQuotas (for resource limits)
quota = k8s.core.v1.ResourceQuota(...)

# LimitRanges (for default limits)
limit_range = k8s.core.v1.LimitRange(...)

# PriorityClasses
priority_class = k8s.scheduling.v1.PriorityClass(...)
```

**Why Pulumi?**
- Cluster-scoped governance
- Multi-tenancy requirements
- Platform team controls

### ❌ Resources NOT Managed by Pulumi

#### 1. **Application Deployments**
```yaml
# Managed via kubectl/GitOps, NOT Pulumi
apiVersion: apps/v1
kind: Deployment
metadata:
  name: day-service
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: day
        image: day-service:v1.2.3
```

**Why NOT Pulumi?**
- Changes frequently (every deployment)
- Application team owns this
- Part of CI/CD pipeline
- Needs fast iteration

#### 2. **ConfigMaps & Secrets**
```yaml
# Managed via kubectl/GitOps, NOT Pulumi
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  database_url: "postgres://..."
```

**Why NOT Pulumi?**
- Application-specific configuration
- Changes with app versions
- Different approval process
- Environment-specific (dev/staging/prod)

#### 3. **HorizontalPodAutoscaler (HPA)**
```yaml
# Managed via kubectl/GitOps, NOT Pulumi
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: day-service-hpa
spec:
  scaleTargetRef:
    kind: Deployment
    name: day-service
  minReplicas: 2
  maxReplicas: 10
```

**Why NOT Pulumi?**
- Tightly coupled to application Deployment
- Tuned per application
- Changes frequently during optimization
- Application team decision

#### 4. **Application Services & Ingresses**
```yaml
# Managed via kubectl/GitOps, NOT Pulumi
apiVersion: v1
kind: Service
metadata:
  name: day-service
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: day-ingress
```

**Why NOT Pulumi?**
- Application routing configuration
- Changes with feature releases
- Application team owns routing rules
- Part of application manifests

#### 5. **ReplicaSets & Pods**
```
❌ NEVER manage these directly - they're managed by Deployments
```

## The Exception: Shared Infrastructure ConfigMaps

There's ONE case where ConfigMaps might be in Pulumi:

```python
# Cluster-wide shared configuration (rarely changes)
shared_config = k8s.core.v1.ConfigMap(
    "cluster-shared-config",
    metadata={"namespace": "kube-system"},
    data={
        "cluster_region": region,
        "cluster_name": cluster_name,
        "vpc_id": vpc_id,
    }
)
```

**Only if:**
- Cluster-scoped, not application-scoped
- Rarely changes
- Shared across ALL applications
- Managed by platform team

## Recommended Architecture for Large-Scale

```
┌────────────────────────────────────────────────────────────┐
│ Layer 1: AWS Infrastructure (Pulumi)                      │
│ - VPC, Subnets, IAM Roles                                 │
│ - Managed by: Platform/DevOps Team                        │
│ - Change Frequency: Monthly                               │
│ - Repository: foundation/infrastructure/pulumi/           │
└────────────────────────────────────────────────────────────┘
                         ↓
┌────────────────────────────────────────────────────────────┐
│ Layer 2: EKS Cluster & Add-ons (Pulumi)                   │
│ - EKS Cluster, Node Groups                                │
│ - ALB Controller, Cluster Autoscaler, Metrics Server      │
│ - Managed by: Platform/DevOps Team                        │
│ - Change Frequency: Weekly                                │
│ - Repository: foundation/infrastructure/pulumi/           │
└────────────────────────────────────────────────────────────┘
                         ↓
┌────────────────────────────────────────────────────────────┐
│ Layer 3: Platform Services (Helm/GitOps)                  │
│ - Monitoring (Prometheus, Grafana)                        │
│ - Logging (Fluentd, CloudWatch)                           │
│ - Service Mesh (Istio/Linkerd) - optional                 │
│ - Managed by: Platform Team                               │
│ - Change Frequency: Weekly                                │
│ - Repository: platform/helm-charts/ or ArgoCD             │
└────────────────────────────────────────────────────────────┘
                         ↓
┌────────────────────────────────────────────────────────────┐
│ Layer 4: Applications (GitOps/kubectl)                    │
│ - Deployments, Services, Ingresses                        │
│ - ConfigMaps, Secrets, HPAs                               │
│ - Managed by: Application Teams                           │
│ - Change Frequency: Daily/Hourly                          │
│ - Repository: services/day/, services/dusk/               │
└────────────────────────────────────────────────────────────┘
```

## Workflow Comparison

### Infrastructure Change (Pulumi)
```bash
# 1. Platform team makes change
cd foundation/infrastructure/pulumi
vim __main__.py  # Add new node group

# 2. Preview changes
pulumi preview

# 3. Create PR → Review by senior engineers
gh pr create

# 4. After approval, merge triggers deployment
# 5. Pulumi updates infrastructure (10-15 min)
```

### Application Change (GitOps)
```bash
# 1. Developer makes change
cd services/day
vim deployment.yaml  # Update image tag

# 2. Commit and push
git commit -m "Update to v1.2.3"
git push

# 3. ArgoCD/CI automatically syncs (30 sec)
# 4. Rolling update to new version
```

## Best Practices for Large-Scale

### 1. **Clear Ownership**
```
Pulumi Repository     Application Repositories
      ↓                         ↓
  Platform Team           Application Teams
      ↓                         ↓
   Infrastructure              Applications
```

### 2. **Use GitOps for Applications**
```
Infrastructure (Pulumi)  →  Cluster Created
         ↓
GitOps Tool (ArgoCD)     →  Deploy Applications
         ↓
Applications (Deployments, ConfigMaps, etc.)
```

**Recommended Setup:**
- Pulumi for cluster infrastructure
- ArgoCD/Flux for application deployment
- Helm for packaging applications

### 3. **Namespace Isolation**
```python
# Pulumi creates namespaces
production_ns = k8s.core.v1.Namespace("production")
staging_ns = k8s.core.v1.Namespace("staging")
dev_ns = k8s.core.v1.Namespace("dev")

# Applications deploy into namespaces (via GitOps)
# - production/day-service
# - production/dusk-service
# - staging/day-service
```

### 4. **Separate State**
```
Pulumi State → S3 or Pulumi Cloud
   ↓
Tracks: VPC, EKS, Node Groups, IAM

GitOps State → Git Repository
   ↓
Tracks: Deployments, Services, ConfigMaps
```

## Real-World Example

### Your Current Setup (Correct Approach!)

**`foundation/infrastructure/pulumi/__main__.py`** (Platform team):
```python
# ✅ Infrastructure managed here
cluster = eks.Cluster(...)
node_group = aws.eks.NodeGroup(...)
alb_controller = k8s.helm.v3.Release(...)
```

**`foundation/k8s/day/`** (Application team):
```yaml
# ✅ Applications managed here
apiVersion: apps/v1
kind: Deployment
metadata:
  name: day-service
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: day-config
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: day-hpa
```

## Anti-Patterns to Avoid

### ❌ Managing Deployments in Pulumi
```python
# DON'T DO THIS for application deployments
app_deployment = k8s.apps.v1.Deployment(
    "day-service",
    spec={
        "replicas": 3,
        "template": {...}
    }
)
```

**Problems:**
- Every image update requires Pulumi run
- Application team blocked by platform team
- Slow feedback loop
- Mixed concerns

### ❌ Managing Node Groups in Application Repo
```yaml
# DON'T DO THIS - node groups are infrastructure
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: day-cluster
nodeGroups:
  - name: workers
```

**Problems:**
- Infrastructure decisions in wrong hands
- No centralized management
- Potential conflicts

## Migration Strategy

If you already have Deployments in Pulumi, migrate gradually:

### Phase 1: Document Current State
```bash
pulumi stack export > current-state.json
kubectl get deployments,configmaps,hpa -A -o yaml > apps.yaml
```

### Phase 2: Move Applications to GitOps
```bash
# 1. Extract application resources
# 2. Commit to application repository
# 3. Set up ArgoCD to manage them
```

### Phase 3: Remove from Pulumi
```python
# Comment out application resources from Pulumi
# app_deployment = k8s.apps.v1.Deployment(...)  # Removed - now in GitOps
```

### Phase 4: Run Pulumi with Exclusions
```bash
pulumi up --target-dependents aws.eks.Cluster
```

## Summary: Decision Framework

When deciding whether to manage a resource with Pulumi, ask:

| Question | Pulumi? | GitOps? |
|----------|---------|---------|
| Is it foundational infrastructure? | ✅ | ❌ |
| Changes monthly or less? | ✅ | ❌ |
| Managed by platform team? | ✅ | ❌ |
| Cluster-scoped impact? | ✅ | ❌ |
| Application-specific? | ❌ | ✅ |
| Changes daily/hourly? | ❌ | ✅ |
| Managed by app team? | ❌ | ✅ |
| Part of CI/CD pipeline? | ❌ | ✅ |

## Your Answer

**For your large-scale EKS service with Pulumi:**

### ✅ Manage with Pulumi:
- EKS Cluster
- VPC, Subnets, Security Groups
- Node Groups / Managed Node Groups
- IAM Roles for IRSA
- ALB Controller (Helm)
- Cluster Autoscaler
- Metrics Server
- External DNS
- Platform-level namespaces

### ❌ Do NOT Manage with Pulumi:
- **Deployments** → Use kubectl/ArgoCD
- **ReplicaSets** → Managed by Deployments
- **Pods** → Managed by ReplicaSets
- **ConfigMaps** (app config) → Use kubectl/ArgoCD
- **Secrets** (app secrets) → Use kubectl/ArgoCD
- **HPA** → Use kubectl/ArgoCD (tied to Deployment)
- **Services** (app services) → Use kubectl/ArgoCD
- **Ingresses** (app routing) → Use kubectl/ArgoCD

## Next Steps

1. **Keep current Pulumi setup** for infrastructure
2. **Set up ArgoCD** for application deployment automation
3. **Create application repositories** with K8s manifests
4. **Define namespace strategy** for multi-tenancy
5. **Implement GitOps workflow** for application teams

## References

- Your current Pulumi code: `foundation/infrastructure/pulumi/__main__.py:1-318`
- Deployment hierarchy guide: `deployment-hierarchy.md`
- ConfigMap relationships: `configmap-relationships.md`
- Pulumi Kubernetes Best Practices: https://www.pulumi.com/docs/clouds/kubernetes/guides/
- GitOps with ArgoCD: https://argo-cd.readthedocs.io/
