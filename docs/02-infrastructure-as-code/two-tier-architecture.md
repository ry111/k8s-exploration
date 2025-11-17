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
│ Terminus: Pulumi (foundation/provisioning/pulumi/)   │
│ Trantor: eksctl (foundation/provisioning/manual/...)  │
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

## Approach 1: Two-Tier Pulumi (Pulumi for BOTH Infrastructure AND Applications)

This approach uses Pulumi to manage **both** infrastructure provisioning and application deployment. We will implement this for the **Dusk service** on the Terminus cluster.

### Architecture

**Tier 1: Infrastructure Pulumi Stack**
```
Location: foundation/provisioning/pulumi/
Stack: production
Manages:
  - Terminus EKS Cluster
  - VPC and Networking (10.2.0.0/16)
  - Managed Node Groups
  - IAM Roles for IRSA
  - ALB Controller (Helm)
Outputs:
  - cluster_name
  - kubeconfig
  - oidc_provider_arn
```

**Tier 2: Application Pulumi Stack**
```
Location: foundation/gitops/pulumi_deploy/ (for Dusk)
Stacks: dusk-production, dusk-rc (to be created)
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
cluster = eks.Cluster("terminus", ...)
node_group = aws.eks.NodeGroup(...)
alb_controller = k8s.helm.v3.Release(...)

# Export for application stack
pulumi.export("kubeconfig", cluster.kubeconfig)
pulumi.export("cluster_name", cluster.eks_cluster.name)
```

**Application Stack:**
```python
# foundation/gitops/pulumi_deploy/__main__.py (for Dusk)
config = pulumi.Config()

# Get infrastructure reference
infra_stack = pulumi.StackReference("organization/foundation-provisioning/production")
kubeconfig = infra_stack.get_output("kubeconfig")

# Create Kubernetes provider using infrastructure kubeconfig
k8s_provider = k8s.Provider("k8s", kubeconfig=kubeconfig)

# Manage application resources
deployment = k8s.apps.v1.Deployment(
    "dusk-service",
    spec={
        "replicas": config.get_int("replicas"),
        "template": {
            "spec": {
                "containers": [{
                    "image": f"dusk:{config.get('image_tag')}",
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
✅ **Unified tooling** - Same tool and language for both layers

### Deployment Workflow

**Infrastructure changes (rare):**
```bash
cd foundation/provisioning/pulumi
pulumi stack select production
pulumi preview  # Review infrastructure changes
pulumi up       # Apply after team review
```

**Application changes (frequent):**
```bash
cd foundation/gitops/pulumi_deploy
pulumi stack select dusk-production
pulumi config set image_tag v1.2.3  # Update version
pulumi preview  # See what will change
pulumi up       # Deploy (triggers rolling update)
```

**CI/CD Integration:**
```yaml
# GitHub Actions
- name: Deploy Dusk Service
  uses: pulumi/actions@v4
  with:
    work-dir: foundation/gitops/pulumi_deploy
    stack-name: dusk-production
    command: up
```

### When to Use Two-Tier Pulumi

✅ **You prefer code over YAML** - Type-safe infrastructure
✅ **Small-medium teams** - Everyone comfortable with Pulumi
✅ **Complex configurations** - Need loops, conditionals, functions
✅ **Multiple environments** - Want to parameterize everything
✅ **Full stack visibility** - Prefer one tool for everything
✅ **Strong typing** - Want compile-time validation
✅ **New greenfield projects** - Starting fresh with full IaC

### Current Status for Dusk

- ✅ Infrastructure: Terminus cluster provisioned with Pulumi
- ⏳ Application: Dusk service deployment with Pulumi (not yet implemented)

## Approach 2: Application-Layer Pulumi Only (Manual Infrastructure + Pulumi Applications)

This approach uses **manual infrastructure** (eksctl) but **Pulumi for application deployment**. This is what we currently use for the **Day service** on the Trantor cluster.

### Architecture

**Tier 1: Infrastructure (Manual)**
```
Location: foundation/provisioning/manual/
Method: eksctl scripts
Manages:
  - Trantor EKS Cluster
  - VPC and Networking (10.0.0.0/16)
  - Managed Node Groups
  - IAM Roles for IRSA
  - ALB Controller (manual installation)
```

**Tier 2: Application Pulumi Stack**
```
Location: foundation/gitops/pulumi_deploy/
Stacks: day-production, day-rc
Manages:
  - Kubernetes Deployment
  - Service (ClusterIP)
  - ConfigMap
  - HorizontalPodAutoscaler
  - Ingress
References:
  - Uses kubeconfig from Trantor cluster (via AWS CLI)
```

### How It Works

**Infrastructure (Manual):**
```bash
# foundation/provisioning/manual/
./create-trantor-cluster.sh us-east-1
./install-alb-controller-trantor.sh us-east-1
```

**Application Stack:**
```python
# foundation/gitops/pulumi_deploy/__main__.py (for Day)
config = pulumi.Config()

# Uses local kubeconfig (connected to Trantor)
# No stack reference needed - cluster already exists

# Manage application resources
deployment = k8s.apps.v1.Deployment(
    "day-service",
    spec={
        "replicas": config.get_int("replicas"),
        ...
    }
)

service = k8s.core.v1.Service(...)
configmap = k8s.core.v1.ConfigMap(...)
hpa = k8s.autoscaling.v2.HorizontalPodAutoscaler(...)
ingress = k8s.networking.v1.Ingress(...)
```

### Advantages of Application-Layer Pulumi

✅ **Type safety** - Application resources are type-safe
✅ **Preview changes** - See application changes before applying
✅ **Separate lifecycles** - Infrastructure and apps deploy independently
✅ **State tracking** - Pulumi knows application state
✅ **Rollback** - Easy rollback to previous application state
✅ **No YAML** - Python/TypeScript for applications
✅ **Easier migration** - Can adopt Pulumi incrementally for apps first
✅ **Reuse existing infrastructure** - Don't need to recreate clusters

### Deployment Workflow

**Infrastructure changes (never - already provisioned):**
```bash
# Infrastructure is manually managed
cd foundation/provisioning/manual/
./create-trantor-cluster.sh us-east-1  # Already done
```

**Application changes (frequent):**
```bash
cd foundation/gitops/pulumi_deploy
pulumi stack select day-production
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
    work-dir: foundation/gitops/pulumi_deploy
    stack-name: day-production
    command: up
```

### When to Use Application-Layer Pulumi

✅ **Existing infrastructure** - Already have clusters provisioned manually
✅ **Incremental adoption** - Want to try Pulumi without re-provisioning infrastructure
✅ **Learning Pulumi** - Start with applications before managing infrastructure
✅ **Mixed teams** - Platform team handles infra, app team uses Pulumi
✅ **Brownfield projects** - Can't recreate existing clusters
✅ **Want Pulumi benefits for apps** - Type safety, previews, state tracking for applications

### Current Status for Day

- ✅ Infrastructure: Trantor cluster manually provisioned with eksctl
- ✅ Application: Day service deployed with Pulumi

## Approach 3: Infrastructure-Layer Pulumi Only (Pulumi Infrastructure + YAML Applications)

This approach uses **Pulumi for infrastructure provisioning** but **YAML manifests for application deployment**. We do NOT use this approach in this project, but it's a perfectly valid strategy used by many teams.

### Architecture

**Tier 1: Infrastructure Pulumi Stack**
```
Location: foundation/provisioning/pulumi/ (hypothetical)
Stack: production
Manages:
  - EKS Cluster
  - VPC and Networking
  - Managed Node Groups
  - IAM Roles for IRSA
  - ALB Controller (Helm)
Outputs:
  - cluster_name
  - kubeconfig
```

**Tier 2: Applications (YAML + kubectl)**
```
Location: foundation/gitops/manual_deploy/ (hypothetical)
Structure:
  ├── prod/          # Production manifests
  │   ├── namespace.yaml
  │   ├── configmap.yaml
  │   ├── deployment.yaml
  │   ├── service.yaml
  │   ├── hpa.yaml
  │   └── ingress.yaml
  └── rc/            # RC manifests
      └── ...

Deploy:
  # Apply manually or via GitOps
  kubectl apply -f foundation/gitops/manual_deploy/prod/
```

### How It Works

**Infrastructure Stack:**
```python
# foundation/provisioning/pulumi/__main__.py
cluster = eks.Cluster("my-cluster", ...)
node_group = aws.eks.NodeGroup(...)
alb_controller = k8s.helm.v3.Release(...)

# Export for kubectl access
pulumi.export("kubeconfig", cluster.kubeconfig)
pulumi.export("cluster_name", cluster.eks_cluster.name)
```

**Application (YAML):**
```yaml
# foundation/gitops/manual_deploy/prod/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-service
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: my-service
        image: my-registry/my-service:v1.2.3
```

**Deployment:**
```bash
# Get kubeconfig from Pulumi
cd foundation/provisioning/pulumi
pulumi stack output kubeconfig --show-secrets > kubeconfig.yaml
export KUBECONFIG=$(pwd)/kubeconfig.yaml

# Deploy applications with kubectl
kubectl apply -f foundation/gitops/manual_deploy/prod/
```

### Advantages of Infrastructure-Layer Pulumi

✅ **IaC for infrastructure** - Preview, track, and version infrastructure
✅ **Standard apps** - Applications use familiar YAML and kubectl
✅ **Team separation** - Platform team uses Pulumi, app teams use YAML
✅ **GitOps ready** - Applications work with ArgoCD/Flux out of the box
✅ **Tool flexibility** - App teams can use Helm, Kustomize, etc.
✅ **Easier app adoption** - Developers don't need to learn Pulumi
✅ **Incremental IaC** - Can adopt IaC for infra first, apps later

### Deployment Workflow

**Infrastructure changes (platform team):**
```bash
cd foundation/provisioning/pulumi
pulumi stack select production
pulumi preview  # Review infrastructure changes
pulumi up       # Apply after team review
```

**Application changes (app team):**
```bash
# Edit YAML
vim foundation/gitops/manual_deploy/prod/deployment.yaml

# Apply manually
kubectl apply -f foundation/gitops/manual_deploy/prod/

# OR with GitOps (ArgoCD syncs automatically)
git commit -m "Update service to v1.2.3"
git push
```

**CI/CD Integration:**
```yaml
# Infrastructure CI/CD
- name: Deploy Infrastructure
  uses: pulumi/actions@v4
  with:
    work-dir: foundation/provisioning/pulumi
    stack-name: production
    command: up

# Application CI/CD
- name: Deploy Applications
  run: |
    aws eks update-kubeconfig --name my-cluster
    kubectl apply -f foundation/gitops/manual_deploy/prod/
```

### When to Use Infrastructure-Layer Pulumi

✅ **Platform team owns infra** - Platform team comfortable with Pulumi
✅ **App teams know YAML** - Developers familiar with Kubernetes YAML
✅ **GitOps for apps** - Want to use ArgoCD/Flux for application deployment
✅ **Separation of tools** - Different tools for different concerns
✅ **Large organizations** - Multiple app teams deploying to shared infrastructure
✅ **Existing YAML** - Already have YAML manifests, don't want to rewrite
✅ **Helm/Kustomize** - App teams want to use these tools

### Why We Don't Use This Approach

In this project, we don't use this approach because:
- We already have Terminus cluster provisioned with Pulumi (infrastructure)
- We wanted to demonstrate Pulumi for applications (Approach 1 for Dusk)
- We wanted to show manual infrastructure + Pulumi apps (Approach 2 for Day)
- We demonstrate traditional YAML approach on manual cluster (Approach 4 for Dawn)

However, **this is a very common and valid approach** in production environments, especially in large organizations where:
- Platform/SRE teams manage infrastructure with Pulumi/Terraform
- Application teams deploy using familiar YAML + GitOps tools

## Approach 4: Traditional Manual + YAML (No Pulumi)

This approach uses **manual infrastructure** and **YAML manifests** for applications. This is what we use for the **Dawn service** on the Trantor cluster.

### Architecture

**Infrastructure:**
```
Location: foundation/provisioning/manual/
Method: eksctl scripts
Manages:
  - Trantor EKS Cluster
  - VPC and Networking (10.0.0.0/16)
  - Managed Node Groups
  - IAM Roles for IRSA
  - ALB Controller (manual installation)
```

**Applications (YAML + kubectl):**
```
Location: foundation/gitops/manual_deploy/dawn/
Structure:
  ├── prod/          # Production manifests
  │   ├── namespace.yaml
  │   ├── configmap.yaml
  │   ├── deployment.yaml
  │   ├── service.yaml
  │   ├── hpa.yaml
  │   └── ingress.yaml
  └── rc/            # RC manifests
      └── ...

Deploy:
  # Apply manually
  kubectl apply -f foundation/gitops/manual_deploy/dawn/prod/
  kubectl apply -f foundation/gitops/manual_deploy/dawn/rc/
```

### Advantages of Traditional Approach

✅ **Standard Kubernetes** - Pure YAML, works with any tool
✅ **Ecosystem compatibility** - Works with Kustomize, Helm, ArgoCD
✅ **Team skills** - Most teams know YAML and kubectl
✅ **GitOps native** - Perfect fit for ArgoCD/Flux
✅ **No additional tools** - Just kubectl and YAML
✅ **Learning friendly** - See exactly what Kubernetes does
✅ **Simple** - No state management, no abstractions

### Deployment Workflow

**Infrastructure (manual scripts):**
```bash
cd foundation/provisioning/manual/
./create-trantor-cluster.sh us-east-1
./install-alb-controller-trantor.sh us-east-1
```

**Application changes:**
```bash
# Edit YAML
vim foundation/gitops/manual_deploy/dawn/prod/deployment.yaml

# Apply manually
kubectl apply -f foundation/gitops/manual_deploy/dawn/prod/
kubectl apply -f foundation/gitops/manual_deploy/dawn/rc/

# OR with GitOps (ArgoCD syncs automatically)
git commit -m "Update dawn to v1.2.3"
git push
```

### When to Use Traditional Approach

✅ **Learning Kubernetes** - Understand fundamentals first
✅ **Simple applications** - Don't need IaC complexity
✅ **GitOps culture** - Already using ArgoCD/Flux
✅ **Team expertise** - Everyone knows YAML and kubectl
✅ **One-off deployments** - Quick experiments or POCs

### Current Status for Dawn

- ✅ Infrastructure: Trantor cluster manually provisioned with eksctl
- ✅ Application: Dawn service deployed with YAML + kubectl

## Current Setup (Your Repository)

We demonstrate **all three approaches** to show different IaC strategies:

### Dawn Service: Traditional Manual + YAML (Approach 3)
```
Cluster: Trantor (manual)
Infrastructure: foundation/provisioning/manual/ (eksctl scripts)
Applications: foundation/gitops/manual_deploy/dawn/prod/*.yaml (kubectl)
Status: ✅ Fully implemented
```

### Day Service: Application-Layer Pulumi (Approach 2)
```
Cluster: Trantor (manual - shared with Dawn)
Infrastructure: foundation/provisioning/manual/ (eksctl scripts)
Applications: foundation/gitops/pulumi_deploy/ (Pulumi stacks: day-production, day-rc)
Status: ✅ Fully implemented
```

### Dusk Service: Two-Tier Pulumi (Approach 1)
```
Cluster: Terminus (Pulumi)
Infrastructure: foundation/provisioning/pulumi/ (Pulumi stack: production)
Applications: foundation/gitops/pulumi_deploy/ (Pulumi stacks: dusk-production, dusk-rc)
Status: ⏳ Infrastructure done, application deployment not yet implemented
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
# foundation/k8s/dawn/prod/deployment.yaml
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
│ - Repository: foundation/provisioning/pulumi/             │
│ - Stack: production                                       │
└────────────────────────────────────────────────────────────┘
                         ↓
┌────────────────────────────────────────────────────────────┐
│ Layer 2: EKS Cluster & Add-ons (Pulumi)                   │
│ - EKS Cluster, Node Groups                                │
│ - ALB Controller, Metrics Server                          │
│ - Managed by: Platform Team                               │
│ - Change Frequency: Weekly                                │
│ - Repository: foundation/provisioning/pulumi/             │
└────────────────────────────────────────────────────────────┘
                         ↓
┌────────────────────────────────────────────────────────────┐
│ Layer 3: Applications (CHOOSE ONE)                        │
│                                                            │
│ Option A: Two-Tier Pulumi (Day Service)                   │
│ - Location: foundation/gitops/pulumi_deploy/              │
│ - Stacks: day-production, day-rc                          │
│ - Manages: Deployment, Service, ConfigMap, HPA, Ingress   │
│                                                            │
│ Option B: GitOps/kubectl (Dawn, Dusk Services)            │
│ - Location: foundation/gitops/manual_deploy/dawn/prod/,   │
│              foundation/gitops/manual_deploy/dusk/prod/   │
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
with open("../../gitops/manual_deploy/day/prod/deployment.yaml") as f:
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
kubectl delete -f foundation/gitops/manual_deploy/day/prod/
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
git add foundation/gitops/manual_deploy/day/
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

### Infrastructure (Two Approaches)
✅ **Trantor**: Manual eksctl scripts (`foundation/provisioning/manual/`)
✅ **Terminus**: Pulumi IaC (`foundation/provisioning/pulumi/`, stack: production)

### Applications (Three Approaches)
✅ **Dawn** (Approach 3): Traditional YAML + kubectl on Trantor (`foundation/gitops/manual_deploy/dawn/`)
✅ **Day** (Approach 2): Application-layer Pulumi on Trantor (`foundation/gitops/pulumi_deploy/`, stacks: day-production, day-rc)
✅ **Dusk** (Approach 1): Two-tier Pulumi on Terminus (`foundation/gitops/pulumi_deploy/`, infrastructure done, application stacks to be created)

**Key Insight:** We demonstrate three different deployment strategies in the same project. Each approach has its place depending on your team's needs, existing infrastructure, and comfort with IaC tools.

## Next Steps

### If Choosing Two-Tier Pulumi (Approach 1 - like Dusk):
1. Set up infrastructure Pulumi stack
2. Set up application Pulumi stack with stack references
3. Configure Kubernetes provider to use infrastructure outputs
4. Parameterize with stack configs
5. Set up CI/CD with Pulumi Actions for both layers

### If Choosing Application-Layer Pulumi (Approach 2 - like Day):
1. Use existing infrastructure (manual or Pulumi)
2. Set up application Pulumi stack
3. Configure kubeconfig connection to existing cluster
4. Parameterize application configs
5. Set up CI/CD with Pulumi Actions for applications
6. Read: [application-as-code.md](../03-application-management/application-as-code.md)

### If Choosing Traditional YAML (Approach 3 - like Dawn):
1. Use existing infrastructure
2. Create YAML manifests for applications
3. Set up ArgoCD for GitOps (optional)
4. Configure CI/CD for kubectl apply or ArgoCD sync
5. Implement namespace strategy

## References

- **Two-tier Pulumi** (Dusk): `foundation/provisioning/pulumi/` + `foundation/gitops/pulumi_deploy/` (to be created)
- **Application-layer Pulumi** (Day): `foundation/gitops/pulumi_deploy/` (existing stacks: day-production, day-rc)
- **Infrastructure Pulumi**: `foundation/provisioning/pulumi/__main__.py`
- **Traditional YAML** (Dawn): `foundation/gitops/manual_deploy/dawn/prod/`
- Application guide: [application-as-code.md](../03-application-management/application-as-code.md)
- Deployment concepts: [deployment-hierarchy.md](../05-kubernetes-deep-dives/deployment-hierarchy.md)
- Pulumi Best Practices: https://www.pulumi.com/docs/using-pulumi/best-practices/
- Stack References: https://www.pulumi.com/learn/building-with-pulumi/stack-references/
