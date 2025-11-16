# Pulumi Resource Management Strategy for EKS

## The Question: What Should Pulumi Manage?

When using Pulumi with EKS for large-scale services, there's a critical decision: **which Kubernetes resources should be managed through Pulumi Infrastructure as Code, and which should be managed elsewhere?**

## TL;DR - Two Valid Approaches

This project demonstrates **both approaches working successfully**:

### Approach 1: Two-Tier Pulumi (Day Service - What We Implemented)
**Separate Pulumi stacks for infrastructure and applications**

```
┌─────────────────────────────────────────────────────┐
│ INFRASTRUCTURE PULUMI STACK                         │
│ foundation/provisioning/pulumi/                   │
├─────────────────────────────────────────────────────┤
│ ✅ EKS Cluster, VPC, Nodes                          │
│ ✅ IAM Roles, OIDC Provider                         │
│ ✅ ALB Controller (Helm)                            │
└─────────────────────────────────────────────────────┘
                     ↓ references via stack outputs
┌─────────────────────────────────────────────────────┐
│ APPLICATION PULUMI STACK                            │
│ foundation/gitops/pulumi_deploy/         │
├─────────────────────────────────────────────────────┤
│ ✅ Deployments, Services, Ingresses                 │
│ ✅ ConfigMaps, Secrets                              │
│ ✅ HorizontalPodAutoscalers                         │
└─────────────────────────────────────────────────────┘
```

### Approach 2: Infrastructure Tool + GitOps (Dawn/Dusk Services)
**Pulumi/eksctl for infrastructure, kubectl/YAML for applications**

```
┌─────────────────────────────────────────────────────┐
│ INFRASTRUCTURE LAYER (Pulumi or eksctl)             │
├─────────────────────────────────────────────────────┤
│ ✅ EKS Cluster, VPC, Nodes                          │
│ ✅ IAM Roles, OIDC Provider                         │
│ ✅ ALB Controller (Helm)                            │
│                                                     │
│ Dusk: Pulumi (foundation/provisioning/pulumi/)   │
│ Dawn: eksctl (foundation/provisioning/manual/create-dawn-...)  │
└─────────────────────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────┐
│ KUBECTL/YAML MANAGES (Application Layer)           │
├─────────────────────────────────────────────────────┤
│ ✅ Deployments, Services, Ingresses                 │
│ ✅ ConfigMaps, Secrets                              │
│ ✅ HorizontalPodAutoscalers                         │
└─────────────────────────────────────────────────────┘
```

**Both are valid!** The key is separating concerns and preventing infrastructure and application changes from blocking each other.

## Why Separation Matters (Regardless of Approach)

### 1. **Different Lifecycles**

**Infrastructure:**
- Changes infrequently (weeks/months)
- Requires careful planning and review
- Has broad impact on entire cluster
- Managed by platform/DevOps team

**Applications:**
- Changes frequently (hours/days)
- Part of CI/CD pipeline
- Scoped to specific services
- Managed by application teams

### 2. **Different Ownership**

```
Platform Team             Application Teams
      ↓                          ↓
Infrastructure Stack      Application Stack/YAML
      ↓                          ↓
  EKS Cluster    →    Deployments, ConfigMaps, etc.
```

### 3. **Blast Radius**

- **Infrastructure changes**: Can affect entire cluster → needs rigorous approval
- **Application changes**: Isolated to namespace/service → faster iteration

## Approach 1: Two-Tier Pulumi (Implemented in This Project)

This is what we actually built for the Day service, proving Pulumi works great for applications when properly architected.

### Architecture

**Tier 1: Infrastructure Pulumi Stack**
```
Location: foundation/provisioning/pulumi/
Stack: day (or dusk)
Manages:
  - AWS EKS Cluster
  - VPC and Networking
  - Managed Node Groups
  - IAM Roles for IRSA
  - ALB Controller (Helm)
  - Platform-level resources
Outputs:
  - cluster_name
  - kubeconfig
  - oidc_provider_arn
```

**Tier 2: Application Pulumi Stack**
```
Location: foundation/gitops/pulumi_deploy/
Stack: dev, production
Manages:
  - Kubernetes Deployment
  - Service (ClusterIP)
  - ConfigMap
  - HorizontalPodAutoscaler
  - Ingress
References:
  - Imports kubeconfig from infrastructure stack
```

### How It Works

**Infrastructure Stack:**
```python
# foundation/provisioning/pulumi/__main__.py
cluster = eks.Cluster("day-cluster", ...)
node_group = aws.eks.NodeGroup(...)
alb_controller = k8s.helm.v3.Release(...)

# Export for application stack
pulumi.export("kubeconfig", cluster.kubeconfig)
pulumi.export("cluster_name", cluster.eks_cluster.name)
```

**Application Stack:**
```python
# foundation/gitops/pulumi_deploy/__main__.py
config = pulumi.Config()

# Get infrastructure reference
infra_stack = pulumi.StackReference(f"organization/infrastructure/{stack}")
kubeconfig = infra_stack.get_output("kubeconfig")

# Create Kubernetes provider using infrastructure kubeconfig
k8s_provider = k8s.Provider("k8s", kubeconfig=kubeconfig)

# Manage application resources
deployment = k8s.apps.v1.Deployment(
    "day-service",
    spec={
        "replicas": config.get_int("replicas"),
        "template": {
            "spec": {
                "containers": [{
                    "image": f"day:{config.get('image_tag')}",
                    ...
                }]
            }
        }
    },
    opts=pulumi.ResourceOptions(provider=k8s_provider)
)

service = k8s.core.v1.Service(...)
configmap = k8s.core.v1.ConfigMap(...)
hpa = k8s.autoscaling.v2.HorizontalPodAutoscaler(...)
ingress = k8s.networking.v1.Ingress(...)
```

### Advantages of Two-Tier Pulumi

✅ **Type safety** - Catch configuration errors at preview time
✅ **Refactoring** - IDE support, find references, rename variables
✅ **Code reuse** - Functions, loops, conditionals for DRY manifests
✅ **Preview changes** - See exactly what will change before applying
✅ **Separate lifecycles** - Infrastructure and apps deploy independently
✅ **State tracking** - Pulumi knows what exists and what changed
✅ **Rollback** - Easy rollback to previous application state
✅ **Environment parity** - Same code, different configs (dev/prod)
✅ **No YAML** - Python/TypeScript instead of YAML templating
✅ **Validation** - Compile-time checks for resource definitions

### Deployment Workflow

**Infrastructure changes (rare):**
```bash
cd foundation/provisioning/pulumi
pulumi stack select day
pulumi preview  # Review infrastructure changes
pulumi up       # Apply after team review
```

**Application changes (frequent):**
```bash
cd foundation/gitops/day
pulumi stack select production
pulumi config set image_tag v1.2.3  # Update version
pulumi preview  # See what will change
pulumi up       # Deploy (triggers rolling update)
```

**CI/CD Integration:**
```yaml
# GitHub Actions
- name: Deploy Day Service
  uses: pulumi/actions@v4
  with:
    work-dir: foundation/gitops/day
    stack-name: production
    command: up
```

### When to Use Two-Tier Pulumi

✅ **You prefer code over YAML** - Type-safe infrastructure
✅ **Small-medium teams** - Everyone comfortable with Pulumi
✅ **Complex configurations** - Need loops, conditionals, functions
✅ **Multiple environments** - Want to parameterize everything
✅ **Full stack visibility** - Prefer one tool for everything
✅ **Strong typing** - Want compile-time validation

## Approach 2: Infrastructure Tool + GitOps (Also Used in This Project)

This is what we use for Dawn and Dusk services - traditional Kubernetes YAML with kubectl/CI.

### Architecture

**Infrastructure:**
```
Dusk: foundation/provisioning/pulumi/ (Pulumi managed)
Dawn: foundation/provisioning/manual/create-dawn-cluster.sh (eksctl manual script)

Both create:
  - AWS EKS Cluster
  - VPC and Networking
  - Managed Node Groups
  - IAM Roles
  - ALB Controller
```

**Applications (YAML + kubectl):**
```
Location: foundation/k8s/dawn/, foundation/k8s/dusk/
Files:
  - deployment.yaml
  - service.yaml
  - configmap.yaml
  - hpa.yaml
  - ingress.yaml
Deploy:
  kubectl apply -f foundation/k8s/dawn/
```

### Advantages of Infrastructure Tool + GitOps

✅ **Standard Kubernetes** - Pure YAML, works with any tool
✅ **Ecosystem compatibility** - Works with Kustomize, Helm, ArgoCD
✅ **Team skills** - Most teams know YAML and kubectl
✅ **GitOps native** - Perfect fit for ArgoCD/Flux
✅ **Tool flexibility** - Choose infrastructure tool that fits (Pulumi, Terraform, eksctl)
✅ **Clear separation** - Infrastructure vs applications very explicit
✅ **Declarative** - Familiar kubectl apply workflow
✅ **Learning friendly** - Manual scripts (like eksctl) help understand each step

### Deployment Workflow

**Infrastructure changes (rare):**
```bash
cd foundation/provisioning/pulumi
pulumi stack select dusk
pulumi up
```

**Application changes (frequent):**
```bash
# Edit YAML
vim foundation/k8s/dawn/deployment.yaml

# Apply directly
kubectl apply -f foundation/k8s/dawn/

# OR with GitOps (ArgoCD syncs automatically)
git commit -m "Update dawn to v1.2.3"
git push
```

### When to Use Infrastructure Tool + GitOps

✅ **Large teams** - Different teams own infrastructure vs apps
✅ **GitOps culture** - Already using ArgoCD/Flux
✅ **Kubernetes expertise** - Team knows YAML well
✅ **Tool diversity** - Want to use Kustomize, Helm, etc.
✅ **Separation of concerns** - Strict infrastructure/app boundaries
✅ **Existing workflows** - Don't want to change app deployment process
✅ **Learning focus** - Manual scripts help understand each step (Dawn example)

## Current Setup (Your Repository)

We demonstrate **both approaches** to show they're equally valid:

### Dawn Service: eksctl (Manual) + kubectl Applications
```
Infrastructure: foundation/provisioning/manual/create-dawn-cluster.sh (eksctl manual script)
Applications:   foundation/k8s/dawn/*.yaml (kubectl)
```

### Day Service: Two-Tier Pulumi
```
Infrastructure: foundation/provisioning/pulumi/ (Pulumi stack: day)
Applications:   foundation/gitops/pulumi_deploy/ (Pulumi stacks: dev, production)
```

### Dusk Service: Pulumi Infrastructure + kubectl Applications
```
Infrastructure: foundation/provisioning/pulumi/ (Pulumi stack: dusk)
Applications:   foundation/k8s/dusk/*.yaml (kubectl)
```

## Detailed Resource Breakdown

### ✅ Always Managed by Infrastructure Layer (Pulumi)

#### Core Infrastructure
```python
# VPC, Subnets, Internet Gateways
vpc = aws.ec2.Vpc(...)
subnet = aws.ec2.Subnet(...)

# EKS Cluster
cluster = eks.Cluster(...)

# Node Groups
node_group = aws.eks.NodeGroup(...)
```

**Why:**
- Foundational infrastructure
- Cluster-wide impact
- Platform team responsibility
- Changes infrequently

#### Cluster Add-ons (via Helm)
```python
# ALB/Ingress Controller
alb_controller = k8s.helm.v3.Release("aws-load-balancer-controller", ...)

# Cluster Autoscaler
cluster_autoscaler = k8s.helm.v3.Release("cluster-autoscaler", ...)

# Metrics Server
metrics_server = k8s.helm.v3.Release("metrics-server", ...)
```

**Why:**
- Cluster-scoped components
- Required for platform functionality
- Platform team manages

#### IAM & IRSA
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

**Why:**
- Security-critical
- Bridges AWS and Kubernetes
- Platform team controls

### ✅ Application Layer (Pulumi OR kubectl/GitOps)

Both approaches work! Choose based on team preferences and requirements.

#### Application Resources
```
✅ Deployments
✅ Services (ClusterIP, NodePort)
✅ ConfigMaps (application config)
✅ Secrets (application secrets)
✅ HorizontalPodAutoscalers
✅ Ingresses (application routing)
✅ PersistentVolumeClaims
✅ CronJobs / Jobs
```

**Two-Tier Pulumi Version:**
```python
# foundation/gitops/pulumi_deploy/__main__.py
deployment = k8s.apps.v1.Deployment(
    "day-service",
    spec={"replicas": config.get_int("replicas"), ...}
)
```

**kubectl/GitOps Version:**
```yaml
# foundation/k8s/dawn/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dawn-service
spec:
  replicas: 2
```

**Both work! Choose based on:**
- Team skills and preferences
- Desire for type safety vs YAML familiarity
- CI/CD integration preferences
- GitOps tooling (ArgoCD works with both)

### ❌ Never Manage Directly

```
❌ ReplicaSets - Managed by Deployments
❌ Pods - Managed by ReplicaSets
```

## Comparison: Two-Tier Pulumi vs Infrastructure + GitOps

| Aspect | Two-Tier Pulumi | Infrastructure Tool + GitOps |
|--------|----------------|------------------------------|
| **Infrastructure** | Pulumi | Pulumi, eksctl, Terraform, etc. |
| **Applications** | Pulumi (Python/TypeScript) | YAML manifests + kubectl |
| **Type Safety** | ✅ Compile-time validation | ❌ Runtime validation only |
| **Change Preview** | `pulumi preview` | `kubectl diff` |
| **Rollback** | `pulumi up --target-dependents` | `kubectl rollout undo` |
| **Environment Management** | Stack configs (Pulumi.dev.yaml) | Kustomize overlays |
| **Team Skills** | Need Pulumi knowledge | Standard Kubernetes |
| **GitOps Tools** | Works with ArgoCD | Native ArgoCD/Flux |
| **Code Reuse** | Functions, loops, modules | Helm, Kustomize |
| **Debugging** | Stack traces, IDE | kubectl describe |
| **Ecosystem** | Pulumi providers | Full K8s ecosystem |

**This project uses both approaches (plus manual eksctl for learning) to demonstrate all are valid!**

## Recommended Architecture (What We Implemented)

```
┌────────────────────────────────────────────────────────────┐
│ Layer 1: AWS Infrastructure (Pulumi)                      │
│ - VPC, Subnets, IAM Roles                                 │
│ - Managed by: Platform Team                               │
│ - Change Frequency: Monthly                               │
│ - Repository: foundation/provisioning/pulumi/           │
│ - Stacks: day, dusk                                       │
└────────────────────────────────────────────────────────────┘
                         ↓
┌────────────────────────────────────────────────────────────┐
│ Layer 2: EKS Cluster & Add-ons (Pulumi)                   │
│ - EKS Cluster, Node Groups                                │
│ - ALB Controller, Metrics Server                          │
│ - Managed by: Platform Team                               │
│ - Change Frequency: Weekly                                │
│ - Repository: foundation/provisioning/pulumi/           │
└────────────────────────────────────────────────────────────┘
                         ↓
┌────────────────────────────────────────────────────────────┐
│ Layer 3: Applications (CHOOSE ONE)                        │
│                                                            │
│ Option A: Two-Tier Pulumi (Day Service)                   │
│ - Location: foundation/gitops/pulumi_deploy/   │
│ - Stacks: dev, production                                 │
│ - Manages: Deployment, Service, ConfigMap, HPA, Ingress   │
│                                                            │
│ Option B: GitOps/kubectl (Dawn, Dusk Services)            │
│ - Location: foundation/k8s/dawn/, foundation/k8s/dusk/    │
│ - Tool: kubectl apply or ArgoCD                           │
│ - Manages: Deployment, Service, ConfigMap, HPA, Ingress   │
└────────────────────────────────────────────────────────────┘
```

## Anti-Patterns to Avoid

### ❌ Mixing Infrastructure and Applications in One Stack

**DON'T:**
```python
# foundation/provisioning/pulumi/__main__.py
cluster = eks.Cluster(...)
node_group = aws.eks.NodeGroup(...)

# ❌ BAD: Application resources in infrastructure stack
day_deployment = k8s.apps.v1.Deployment("day-service", ...)
dusk_deployment = k8s.apps.v1.Deployment("dusk-service", ...)
```

**Problems:**
- Application updates require infrastructure stack changes
- No separation of concerns
- Long deployment times
- Coupled lifecycles

**DO:**
```python
# foundation/provisioning/pulumi/__main__.py
cluster = eks.Cluster(...)

# Export for application stacks
pulumi.export("kubeconfig", cluster.kubeconfig)

# foundation/gitops/pulumi_deploy/__main__.py
# ✅ GOOD: Applications in separate stack
deployment = k8s.apps.v1.Deployment(...)
```

### ❌ Managing Node Groups in Application Layer

```yaml
# ❌ DON'T: Infrastructure in application manifests
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
```

**Problems:**
- Infrastructure control in wrong place
- No centralized management

## Migration Strategies

### From YAML to Two-Tier Pulumi

We did this for Day service! Here's how:

**Step 1: Keep infrastructure Pulumi as-is**
```bash
# Already managed
foundation/provisioning/pulumi/
```

**Step 2: Create application Pulumi stack**
```bash
mkdir -p foundation/gitops/pulumi_deploy
cd foundation/gitops/pulumi_deploy
pulumi new kubernetes-python
```

**Step 3: Convert YAML to Pulumi**
```python
# Read existing YAML
with open("../../k8s/pulumi_deploy/deployment.yaml") as f:
    # Convert to Pulumi resources

deployment = k8s.apps.v1.Deployment(
    "day-service",
    spec={...}  # From YAML
)
```

**Step 4: Deploy and verify**
```bash
pulumi preview
pulumi up
kubectl get pods -n production  # Verify
```

**Step 5: Remove old YAML deployments**
```bash
kubectl delete -f foundation/k8s/pulumi_deploy/
```

### From Two-Tier Pulumi to GitOps

If you decide Pulumi isn't right for applications:

**Step 1: Export current state**
```bash
kubectl get deployment,service,configmap,hpa,ingress -n production -o yaml > exported.yaml
```

**Step 2: Clean up and commit YAML**
```bash
# Edit exported.yaml (remove runtime fields)
git add foundation/k8s/pulumi_deploy/
git commit -m "Migrate Day to kubectl management"
```

**Step 3: Import into Pulumi with deletion protection**
```python
# Mark for deletion later
deployment = k8s.apps.v1.Deployment(
    "day-service",
    ...,
    opts=pulumi.ResourceOptions(protect=True)
)
```

**Step 4: Remove from Pulumi stack**
```bash
pulumi state delete kubernetes:apps/v1:Deployment::day-service
```

## Summary: Decision Framework

### Should I use Two-Tier Pulumi for applications?

| Scenario | Recommendation |
|----------|----------------|
| Small team, everyone knows Pulumi | ✅ Two-Tier Pulumi |
| Need type safety and validation | ✅ Two-Tier Pulumi |
| Complex config with conditionals | ✅ Two-Tier Pulumi |
| Prefer code over YAML | ✅ Two-Tier Pulumi |
| Already using ArgoCD/Flux | ⚠️ Consider GitOps |
| Large org, many app teams | ⚠️ Consider GitOps |
| Teams unfamiliar with Pulumi | ⚠️ Consider GitOps |
| Heavy Helm/Kustomize usage | ⚠️ Consider GitOps |

**Both work! This project proves it.** Choose based on team preferences, not dogma.

## What We Actually Built

### Infrastructure (Multiple Approaches)
✅ `foundation/provisioning/pulumi/` - EKS clusters for Day and Dusk (Pulumi)
✅ `foundation/provisioning/manual/create-dawn-cluster.sh` - Dawn cluster (eksctl manual script)

### Applications (Demonstrating Both Approaches)
✅ **Day Service** - Two-Tier Pulumi (`foundation/gitops/pulumi_deploy/`)
✅ **Dawn Service** - kubectl/YAML (`foundation/k8s/dawn/`)
✅ **Dusk Service** - kubectl/YAML (`foundation/k8s/dusk/`)

**Key Insight:** We use both approaches in the same project successfully. The separation via stacks (for Pulumi) or directories (for YAML) is what matters, not the tool choice.

## Next Steps

### If Choosing Two-Tier Pulumi:
1. Set up application Pulumi stack (like Day service)
2. Configure stack references to infrastructure
3. Parameterize with stack configs
4. Set up CI/CD with Pulumi Actions
5. Read: [application-as-code.md](../03-application-management/application-as-code.md)

### If Choosing GitOps:
1. Keep infrastructure Pulumi as-is
2. Create application YAML manifests (like Dawn/Dusk)
3. Set up ArgoCD for GitOps
4. Configure CI/CD for image builds
5. Implement namespace strategy

## References

- Two-tier Pulumi example: `foundation/gitops/pulumi_deploy/`
- Infrastructure Pulumi: `foundation/provisioning/pulumi/__main__.py`
- GitOps examples: `foundation/k8s/dawn/`, `foundation/k8s/dusk/`
- Application guide: [application-as-code.md](../03-application-management/application-as-code.md)
- Deployment concepts: [deployment-hierarchy.md](../05-kubernetes-deep-dives/deployment-hierarchy.md)
- Pulumi Best Practices: https://www.pulumi.com/docs/using-pulumi/best-practices/
- Stack References: https://www.pulumi.com/learn/building-with-pulumi/stack-references/
