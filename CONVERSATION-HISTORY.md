# Conversation History: Pulumi Infrastructure Setup

**Date:** November 16, 2025
**Branch:** `claude/infrastructure-management-tools-01FzXt6XWcSBXTotEMTtsxAR`
**Session:** Infrastructure Management Tools - Pulumi Integration

---

## Table of Contents

1. [Overview](#overview)
2. [Pulumi Preview Validation](#pulumi-preview-validation)
3. [Pulumi CI/CD Integration](#pulumi-cicd-integration)
4. [Decision: Use Pulumi for Day Cluster](#decision-use-pulumi-for-day-cluster)
5. [Removed Dawn from Pulumi Management](#removed-dawn-from-pulumi-management)
6. [Fixed Spot Instance Configuration](#fixed-spot-instance-configuration)
7. [Pulumi CLI Behavior](#pulumi-cli-behavior)
8. [Understanding Pulumi Resources](#understanding-pulumi-resources)
9. [Kubernetes Resources in Pulumi](#kubernetes-resources-in-pulumi)
10. [HPA and ArgoCD Discussion](#hpa-and-argocd-discussion)
11. [Kubernetes Pod Creation](#kubernetes-pod-creation)
12. [Final State](#final-state)

---

## Overview

This session focused on integrating Pulumi Infrastructure as Code for managing the Day and Dusk EKS clusters, while keeping the manually-created Dawn cluster separate. Key accomplishments:

- ✅ Created generic Pulumi infrastructure code for multiple services
- ✅ Configured separate stacks for Day and Dusk clusters
- ✅ Fixed spot instance configuration issues
- ✅ Removed Dawn from Pulumi management
- ✅ Explored Pulumi resource model and Kubernetes integration

---

## Pulumi Preview Validation

### Question: Does `pulumi preview` validate that changes don't break dependencies?

**Answer:** `pulumi preview` provides **limited validation**:

#### What it DOES validate:
1. **Syntax & Type Checking** - Code compiles correctly
2. **Provider Validation** - Cloud provider APIs validate basic constraints
3. **Required Properties** - Missing required fields are caught
4. **Dependency Graph** - Shows resource dependencies and order
5. **State Drift** - Detects if actual infrastructure differs from Pulumi state

#### What it DOES NOT validate:
1. **Runtime Compatibility** - Won't catch if new security group rules block your app
2. **IAM/Permission Issues** - Won't verify if IAM policies actually grant needed permissions
3. **Network Connectivity** - Won't validate if resources can actually communicate
4. **Resource Limits** - Won't catch quota/limit violations until apply
5. **Cross-Resource Logic** - Won't verify if configuration changes break dependencies

#### Example Scenarios:

**❌ Preview WON'T catch:**
```python
# Change security group to block all traffic
security_group = aws.ec2.SecurityGroup("sg",
    ingress=[]  # Preview shows change but won't know it breaks your app
)
```

**✅ Preview WILL catch:**
```python
# Invalid instance type
instance = aws.ec2.Instance("web",
    instance_type="t99.mega"  # AWS API validation fails during preview
)
```

#### Production Best Practices:

1. **Pulumi Preview** - First line of defense
2. **Policy as Code** - Use **Pulumi CrossGuard** to enforce policies
3. **Staging Environment** - Test changes in non-prod first
4. **Integration Tests** - Post-deployment tests to verify functionality
5. **Gradual Rollouts** - Blue-green or canary deployments
6. **Monitoring & Alerts** - Catch runtime issues quickly

**Bottom line:** `pulumi preview` is like a "dry run" that shows the plan but doesn't guarantee success. Real validation requires layering multiple strategies.

---

## Pulumi CI/CD Integration

### Question: How do I integrate Pulumi with CI/CD?

**Answer:** Pulumi integrates through **Pulumi Automation API** or **Pulumi CLI in pipelines**.

### Option 1: Pulumi CLI in GitHub Actions (Most Common)

Created two workflows:

#### Preview on Pull Request:
```yaml
# .github/workflows/pulumi-preview.yml
name: Pulumi Preview
on:
  pull_request:
    branches: [main, claude/**]
    paths:
      - 'foundation/pulumi/**'

jobs:
  preview:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: pulumi/actions@v4
        with:
          command: preview
          stack-name: day
          comment-on-pr: true  # Posts preview to PR comments
        env:
          PULUMI_ACCESS_TOKEN: ${{ secrets.PULUMI_ACCESS_TOKEN }}
```

#### Deploy on Merge:
```yaml
# .github/workflows/pulumi-up.yml
name: Pulumi Deploy
on:
  push:
    branches: [main]
    paths:
      - 'foundation/pulumi/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: pulumi/actions@v4
        with:
          command: up
          stack-name: day
```

### Common CI/CD Patterns:

#### 1. Pull Request Workflow (GitOps)
```
PR opened → pulumi preview → Comment results on PR → Manual approval → Merge → pulumi up
```

#### 2. Multi-Environment Promotion
```
Commit → Deploy to Dev → Tests pass → Deploy to Staging → Tests pass → Deploy to Prod
```

#### 3. Separate Infrastructure & Application Pipelines

**Infrastructure Pipeline** (changes to Pulumi code):
- Runs when `foundation/pulumi/**` changes
- Creates/updates EKS clusters, ALBs, IAM roles
- Slow cadence (weekly/monthly)

**Application Pipeline** (changes to service code):
- Runs when `foundation/services/**` changes
- Builds Docker images, updates K8s manifests
- Fast cadence (many times per day)

### State Management Options:

1. **Pulumi Cloud** (Easiest - Free tier available)
   ```bash
   pulumi login
   ```

2. **AWS S3 Backend** (Self-managed)
   ```bash
   pulumi login s3://my-pulumi-state-bucket
   ```

### Integration with Current Setup:

```
1. Change Pulumi code (EKS cluster config)
   ↓
2. GitHub Actions runs `pulumi preview` on PR
   ↓
3. Review preview output in PR comment
   ↓
4. Merge PR → `pulumi up` runs automatically
   ↓
5. EKS cluster updated
   ↓
6. Application CI pipeline triggers (builds Day image)
   ↓
7. ArgoCD detects new image → Deploys to updated cluster
```

---

## Decision: Use Pulumi for Day Cluster

### Question: What should we do next?

Based on the roadmap (EKS → CI → Pulumi → CD), we decided to implement **Phase 4: Pulumi Integration**.

### What Was Created:

#### 1. Pulumi Program (`foundation/pulumi/__main__.py`)
A complete infrastructure definition that creates:
- **VPC** with public subnets across 2 availability zones
- **EKS cluster** with OIDC provider enabled
- **Spot instance node group** (t3.small, 2-5 nodes)
- **IAM roles** for ALB controller using IRSA
- **ALB controller** installed via Helm
- All resources properly tagged for cost tracking

#### 2. GitHub Actions Workflows
- **pulumi-preview.yml** - Runs on PRs, posts infrastructure preview to PR comments
- **pulumi-up.yml** - Automatically deploys infrastructure changes on merge to main

#### 3. Documentation
- **PULUMI-SETUP.md** - Comprehensive setup guide with both Pulumi Cloud and S3 backend options
- **pulumi/README.md** - Comparison between manual and Pulumi approaches
- **DEPLOY-DAY-CLUSTER.md** - Complete deployment guide for Day cluster

#### 4. Configuration
- **Pulumi.day.yaml** - Day environment stack configuration (VPC: 10.1.0.0/16)
- **Pulumi.dusk.yaml** - Dusk environment stack configuration (VPC: 10.2.0.0/16)
- **requirements.txt** - Python dependencies
- **.gitignore** - Excludes Pulumi state files

### Key Benefits Over Manual Scripts:

| Feature | Manual (eksctl) | Pulumi |
|---------|----------------|--------|
| **Change Preview** | ❌ None | ✅ `pulumi preview` |
| **State Tracking** | ❌ None | ✅ Full state management |
| **Updates** | ❌ Delete/recreate | ✅ In-place updates |
| **CI/CD** | ❌ Manual runs | ✅ Automated |
| **Multi-env** | ❌ Hard to replicate | ✅ Separate stacks |
| **Drift Detection** | ❌ None | ✅ `pulumi refresh` |

---

## Removed Dawn from Pulumi Management

### Question: Do not include dawn in pulumi, remove relevant config and code for dawn.

**Reasoning:** The Dawn cluster was created manually using eksctl scripts and should remain managed that way. Pulumi will only manage Day and Dusk clusters.

### Changes Made:

1. **Deleted** `Pulumi.dev.yaml` (Dawn dev stack configuration)

2. **Updated** `Pulumi.yaml`:
   ```yaml
   name: service-infrastructure
   description: EKS infrastructure for microservices (Day/Dusk) with spot instances
   config:
     service-infrastructure:service_name:
       description: Service name (day or dusk)  # Removed "dawn"
   ```

3. **Updated** `__main__.py`:
   ```python
   """
   Supports Day and Dusk services via stack configuration.
   Note: Dawn cluster is managed manually via eksctl scripts.
   """
   ```

4. **Updated** `foundation/pulumi/README.md`:
   - Clarified Pulumi manages Day/Dusk only, not Dawn
   - Updated table to show Dawn as "Manual (eksctl)"
   - Removed Dawn deployment steps from Quick Start

5. **Updated** `foundation/PULUMI-SETUP.md`:
   - Changed from "Dawn EKS cluster" to "Day and Dusk EKS clusters"
   - Stack initialization uses `pulumi stack init day` instead of `dev`
   - Added "Dawn Cluster Note" explaining it remains manual

### Current Architecture:

| Service | VPC CIDR | Cluster Name | Management | Status |
|---------|----------|--------------|------------|--------|
| **Dawn** | 10.0.0.0/16 | dawn-cluster | Manual (eksctl) | Running ✅ |
| **Day** | 10.1.0.0/16 | day-cluster | Pulumi | Ready to deploy |
| **Dusk** | 10.2.0.0/16 | dusk-cluster | Pulumi | Ready to deploy |

---

## Fixed Spot Instance Configuration

### Error Encountered:

```
TypeError: Cluster._internal_init() got an unexpected keyword argument 'spot_price'
```

### Root Cause:

The original code tried to pass `spot_price` to `eks.Cluster()`:
```python
cluster_args["spot_price"] = "0.0104"  # ❌ Not supported
```

This parameter doesn't exist in the pulumi-eks package.

### The Fix:

Changed to use **AWS EKS Managed Node Groups** with proper spot configuration:

#### Before:
```python
cluster = eks.Cluster(
    f"{service_name}-cluster",
    spot_price="0.0104",  # ❌ Invalid parameter
    **cluster_args,
)
```

#### After:
```python
# Create cluster without default node group
cluster = eks.Cluster(
    f"{service_name}-cluster",
    vpc_id=vpc.id,
    public_subnet_ids=[public_subnet_1.id, public_subnet_2.id],
    skip_default_node_group=True,  # We'll create managed node group separately
    create_oidc_provider=True,
    tags={**common_tags, "Name": cluster_name},
)

# Create separate managed node group with spot instances
node_group = aws.eks.NodeGroup(
    f"{service_name}-node-group",
    cluster_name=cluster.eks_cluster.name,
    node_role_arn=cluster.instance_roles[0].arn,
    subnet_ids=[public_subnet_1.id, public_subnet_2.id],
    capacity_type="SPOT" if use_spot else "ON_DEMAND",  # ✅ Proper way
    instance_types=[instance_type],
    scaling_config=aws.eks.NodeGroupScalingConfigArgs(
        desired_size=desired_nodes,
        min_size=min_nodes,
        max_size=max_nodes,
    ),
    tags={**common_tags, "Name": f"{service_name}-node-group"},
)
```

This uses AWS's native **capacity_type** parameter for managed node groups, which is the proper way to configure spot instances in EKS.

---

## Pulumi CLI Behavior

### Question: Does `pulumi up` CLI return immediately or after convergence?

**Answer:** `pulumi up` **waits for convergence** - it's a **synchronous** operation that only returns after all resources are fully created/updated.

### Behavior:

1. **Shows preview** - Displays what will change
2. **Asks for confirmation** - Type "yes" to proceed (unless using `--yes` flag)
3. **Creates resources in order** - Respects dependencies
4. **Waits for each resource** - Shows real-time progress
5. **Returns only when complete** - All resources created or error occurred

### Example Timeline for Day Cluster:

```bash
$ pulumi up

Previewing update (day)
...
Do you want to perform this update? yes

Updating (day)
+ aws:ec2:Vpc creating (0s)
+ aws:ec2:Vpc created (2s)
+ aws:ec2:InternetGateway creating (0s)
+ aws:ec2:InternetGateway created (1s)
...
+ eks:Cluster creating (0s)
+ eks:Cluster still creating... (5m0s)
+ eks:Cluster still creating... (10m0s)
+ eks:Cluster created (12m34s)
...
+ kubernetes:helm.sh/v3:Release creating (0s)
+ kubernetes:helm.sh/v3:Release created (45s)

Resources:
    + 20 created

Duration: 14m22s
```

**Total time**: ~10-15 minutes (CLI blocks until done)

### If You Need Async Behavior:

```bash
# Run in background
pulumi up --yes > pulumi.log 2>&1 &

# Non-interactive (CI/CD)
pulumi up --yes
```

**Benefits of synchronous behavior:**
- ✅ Know exactly when infrastructure is ready
- ✅ See errors immediately
- ✅ Can chain commands: `pulumi up && kubectl apply -f ...`
- ✅ Exit codes indicate success/failure

---

## Understanding Pulumi Resources

### Question: What does a Pulumi "resource" contain exactly?

A Pulumi **resource** is a data structure that contains everything needed to create, manage, and track an infrastructure component.

### Core Components:

#### 1. URN (Uniform Resource Name)
```
urn:pulumi:day::service-infrastructure::aws:ec2/vpc:Vpc::day-vpc
     │     │              │                  │              │
     │     └─ stack       └─ project         │              └─ logical name
     └─ namespace                             └─ resource type
```

#### 2. Type
```
aws:ec2/vpc:Vpc
 │   │   │   │
 │   │   │   └─ Resource name
 │   │   └───── Module
 │   └───────── Service
 └───────────── Provider
```

#### 3. Inputs - Properties You Define

```python
vpc = aws.ec2.Vpc(
    f"{service_name}-vpc",
    cidr_block=vpc_cidr,              # ← Input
    enable_dns_hostnames=True,        # ← Input
    enable_dns_support=True,          # ← Input
    tags={...},                       # ← Input
)
```

**Inputs structure:**
```json
{
  "cidrBlock": "10.1.0.0/16",
  "enableDnsHostnames": true,
  "enableDnsSupport": true,
  "tags": {
    "ManagedBy": "Pulumi",
    "Name": "day-vpc-day"
  }
}
```

#### 4. Outputs - Properties Returned by Provider

```json
{
  "id": "vpc-0abc123def456",
  "arn": "arn:aws:ec2:us-east-1:...:vpc/...",
  "cidrBlock": "10.1.0.0/16",
  "defaultNetworkAclId": "acl-...",
  "defaultRouteTableId": "rtb-...",
  "defaultSecurityGroupId": "sg-...",
  "ownerId": "612974049499"
}
```

#### 5. Dependencies - Resource Graph

```python
igw = aws.ec2.InternetGateway(
    f"{service_name}-igw",
    vpc_id=vpc.id,  # ← References VPC output
)
```

**Dependency graph:**
```
VPC
 ├─→ Internet Gateway (depends on VPC)
 ├─→ Subnet 1 (depends on VPC)
 ├─→ Subnet 2 (depends on VPC)
 └─→ Route Table (depends on VPC, IGW)
```

#### 6. Provider - Which Provider Manages It

```python
# AWS provider (implicit)
vpc = aws.ec2.Vpc(...)

# Kubernetes provider (explicit)
alb_service_account = k8s.core.v1.ServiceAccount(
    ...,
    opts=pulumi.ResourceOptions(
        provider=k8s_provider,  # ← Explicit provider
    ),
)
```

#### 7. Metadata & Options

```python
opts=pulumi.ResourceOptions(
    provider=k8s_provider,
    depends_on=[cluster],
    protect=False,
    delete_before_replace=False,
)
```

#### 8. State - Stored in Backend

All this information is stored in Pulumi state (Pulumi Cloud or S3).

### Complete Example: Node Group Resource

```json
{
  "urn": "urn:pulumi:day::service-infrastructure::aws:eks/nodeGroup:NodeGroup::day-node-group",
  "type": "aws:eks/nodeGroup:NodeGroup",
  "name": "day-node-group",

  "inputs": {
    "clusterName": "day-cluster-abc123",
    "nodeRoleArn": "arn:aws:iam::612974049499:role/...",
    "subnetIds": ["subnet-111", "subnet-222"],
    "capacityType": "SPOT",
    "instanceTypes": ["t3.small"],
    "scalingConfig": {
      "desiredSize": 2,
      "minSize": 1,
      "maxSize": 3
    }
  },

  "outputs": {
    "id": "day-cluster:day-node-group-20251115",
    "arn": "arn:aws:eks:us-east-1:612974049499:nodegroup/...",
    "status": "ACTIVE",
    "capacityType": "SPOT"
  },

  "dependencies": [
    "urn:pulumi:day::...::eks:index:Cluster::day-cluster"
  ]
}
```

### Viewing Resource Details:

```bash
# See all resources
pulumi stack export | jq '.deployment.resources[]'

# See specific resource
pulumi stack export | jq '.deployment.resources[] | select(.type == "aws:eks/nodeGroup:NodeGroup")'
```

---

## Kubernetes Resources in Pulumi

### Kubernetes Resource Anatomy

Using the ALB controller ServiceAccount as an example:

```python
alb_service_account = k8s.core.v1.ServiceAccount(
    "aws-load-balancer-controller",
    metadata=k8s.meta.v1.ObjectMetaArgs(
        name="aws-load-balancer-controller",
        namespace="kube-system",
        annotations={
            "eks.amazonaws.com/role-arn": alb_role.arn,
        },
    ),
    opts=pulumi.ResourceOptions(
        provider=k8s_provider,
        depends_on=[cluster],
    ),
)
```

### URN for Kubernetes Resource:

```
urn:pulumi:day::service-infrastructure::kubernetes:core/v1:ServiceAccount::aws-load-balancer-controller
     │     │              │                        │                               │
     │     └─ stack       └─ project               │                               └─ logical name
     └─ namespace                                   └─ resource type (K8s API group/version/kind)
```

### Type - Kubernetes API Resource:

```
kubernetes:core/v1:ServiceAccount
    │       │   │        │
    │       │   │        └─ Kind (ServiceAccount)
    │       │   └────────── API version (v1)
    │       └────────────── API group (core)
    └────────────────────── Provider (kubernetes)
```

### Inputs:

```json
{
  "metadata": {
    "name": "aws-load-balancer-controller",
    "namespace": "kube-system",
    "annotations": {
      "eks.amazonaws.com/role-arn": "arn:aws:iam::612974049499:role/day-alb-controller-role"
    }
  }
}
```

### Outputs (from Kubernetes API):

```json
{
  "apiVersion": "v1",
  "kind": "ServiceAccount",
  "metadata": {
    "uid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "resourceVersion": "12345",
    "creationTimestamp": "2025-11-15T12:34:56Z",
    "annotations": {...}
  },
  "secrets": [
    {
      "name": "aws-load-balancer-controller-token-abc12"
    }
  ]
}
```

### Helm Release Example:

The ALB controller Helm release creates multiple K8s resources:

```json
{
  "type": "kubernetes:helm.sh/v3:Release",
  "outputs": {
    "name": "aws-load-balancer-controller",
    "status": "deployed",
    "resources": [
      "v1/ServiceAccount::kube-system/aws-load-balancer-controller",
      "apps/v1/Deployment::kube-system/aws-load-balancer-controller",
      "v1/Service::kube-system/aws-load-balancer-webhook-service",
      "rbac.authorization.k8s.io/v1/ClusterRole::aws-load-balancer-controller-role",
      "rbac.authorization.k8s.io/v1/ClusterRoleBinding::aws-load-balancer-controller-rolebinding"
    ]
  }
}
```

### Kubernetes Resources Created by Pulumi:

| Resource Type | Name | Namespace | Created By |
|--------------|------|-----------|------------|
| **ServiceAccount** | aws-load-balancer-controller | kube-system | Pulumi (explicit) |
| **Helm Release** | aws-load-balancer-controller | kube-system | Pulumi (explicit) |
| **Deployment** | aws-load-balancer-controller | kube-system | Helm chart |
| **Service** | aws-load-balancer-webhook-service | kube-system | Helm chart |
| **ClusterRole** | aws-load-balancer-controller-role | cluster-wide | Helm chart |
| **ClusterRoleBinding** | aws-load-balancer-controller-rolebinding | cluster-wide | Helm chart |
| **IngressClass** | alb | cluster-wide | Helm chart |

### What's NOT Provisioned by Pulumi:

These Day service application resources are managed separately via kubectl:

- ❌ Namespace - `day-ns`
- ❌ ConfigMap - Day configuration
- ❌ Deployment - Day application pods
- ❌ Service - Day ClusterIP service
- ❌ HPA - Day autoscaling
- ❌ Ingress - Day ALB ingress

---

## HPA and ArgoCD Discussion

### Question: Why is HorizontalPodAutoscaler not part of Pulumi-generated resources?

**Answer:** This is about **separation of concerns** between infrastructure and application layers.

### Current Separation:

**Pulumi manages (Infrastructure layer):**
- ✅ VPC, subnets, routing
- ✅ EKS cluster control plane
- ✅ Node groups (EC2 instances)
- ✅ IAM roles
- ✅ ALB controller (infrastructure component)

**Kubernetes manifests manage (Application layer):**
- ❌ Deployments (Day/Dusk services)
- ❌ Services (ClusterIP)
- ❌ HorizontalPodAutoscaler
- ❌ Ingress resources
- ❌ ConfigMaps
- ❌ Namespaces

### Why This Separation?

1. **Different Lifecycles**
   - Infrastructure changes: Monthly/quarterly
   - Application changes: Daily/hourly

2. **Different Ownership**
   - Platform team → Pulumi (cluster infrastructure)
   - Application team → kubectl/ArgoCD (services, HPAs)

3. **Tool Optimization**
   - Pulumi excels at AWS resources
   - GitOps tools (ArgoCD) excel at K8s application deployment

### How ArgoCD Manages HPA:

ArgoCD manages HPA through **GitOps** - Git becomes the single source of truth.

#### Workflow:

```
1. Developer changes HPA in Git
   vim foundation/k8s/day/hpa.yaml
   maxReplicas: 5 → 10
   git push
   ↓
2. ArgoCD detects change (polls every 3 minutes or webhook)
   ↓
3. ArgoCD syncs HPA to cluster
   kubectl apply -f hpa.yaml
   ↓
4. HPA scales deployment based on new limits
   ↓
5. ArgoCD UI shows sync status: ✅ Healthy
```

#### Self-Healing Example:

```bash
# Someone manually changes HPA
kubectl edit hpa day-hpa -n day-ns
# Changes maxReplicas from 5 to 10

# ArgoCD detects drift within seconds
# ArgoCD reverts back to 5 (from Git)
# ArgoCD sends alert: "Manual change detected and reverted"
```

#### HPA + ArgoCD Special Consideration:

ArgoCD is smart enough to **ignore** HPA-managed fields:

```yaml
# Remove replicas from Deployment when using HPA
apiVersion: apps/v1
kind: Deployment
spec:
  # replicas: 2  ← Remove this (HPA manages it)
  selector:
    matchLabels:
      app: day
```

Or configure ArgoCD to ignore:

```yaml
spec:
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas  # Ignore replica count (managed by HPA)
```

### ArgoCD Benefits for HPA:

1. **Audit Trail** - Git history shows who changed HPA and when
2. **Rollback** - `git revert` to undo HPA changes
3. **Multi-Environment** - Different HPA configs for dev/staging/prod branches
4. **No kubectl Access** - Developers don't need cluster credentials
5. **Drift Prevention** - Manual changes are auto-reverted

---

## Kubernetes Pod Creation

### Question: When I create a Deployment resource, are K8s "Pod" resources created as well? If so, how?

**Answer:** **Yes, Pod resources ARE automatically created**, but through a **cascade of controllers**.

### The Controller Chain:

```
You create:
    Deployment (YAML)
         ↓
    [Deployment Controller watches and creates]
         ↓
    ReplicaSet (automatically created)
         ↓
    [ReplicaSet Controller watches and creates]
         ↓
    Pods (automatically created)
```

### Step-by-Step Process:

#### 1. You Create a Deployment

```bash
kubectl apply -f deployment.yaml
```

This creates **one resource** in etcd:
- ✅ Deployment object stored

**No Pods created yet!**

#### 2. Deployment Controller Creates ReplicaSet

The **Deployment Controller** continuously watches for Deployment objects:

```
Deployment Controller:
  1. Sees new Deployment "day-deployment"
  2. Reads spec.replicas = 2
  3. Reads spec.template (Pod template)
  4. Creates a ReplicaSet with that template
```

Now **two resources** exist:
- ✅ Deployment object
- ✅ ReplicaSet object (automatically created)

**Still no Pods created yet!**

#### 3. ReplicaSet Controller Creates Pods

The **ReplicaSet Controller** watches for ReplicaSet objects:

```
ReplicaSet Controller:
  1. Sees new ReplicaSet
  2. Reads spec.replicas = 2
  3. Checks current Pods (finds 0)
  4. Creates 2 Pod objects from template
```

Now **four resources** exist:
- ✅ Deployment object
- ✅ ReplicaSet object
- ✅ Pod object 1 (automatically created)
- ✅ Pod object 2 (automatically created)

#### 4. Kubelet Creates Containers

The **Kubelet** (runs on worker nodes) watches for Pod objects:

```
Kubelet:
  1. Sees Pod assigned to it
  2. Pulls image
  3. Creates container using Docker/containerd
  4. Reports status back
```

**Now the actual containers are running!**

### Ownership Chain:

```
Deployment (you created)
   owns ↓
ReplicaSet (Deployment controller created)
   owns ↓
Pod 1 (ReplicaSet controller created)
Pod 2 (ReplicaSet controller created)
   runs on ↓
Containers (Kubelet created)
```

### Seeing It In Action:

```bash
# Watch resources being created
watch -n 1 "kubectl get deployment,rs,pod -n day-ns"

# Apply Deployment
kubectl apply -f foundation/k8s/day/deployment.yaml
```

**Timeline:**
```
Second 0:
deployment.apps/day-deployment  0/2     0            0           0s

Second 1:
deployment.apps/day-deployment  0/2     2            0           1s
replicaset.apps/day-deployment-7d4c8bf5c9  2  0  0  0s  ← ReplicaSet created!

Second 2:
pod/day-deployment-7d4c8bf5c9-abc12   0/1   ContainerCreating   0  0s  ← Pods created!
pod/day-deployment-7d4c8bf5c9-xyz89   0/1   ContainerCreating   0  0s

Second 5:
pod/day-deployment-7d4c8bf5c9-abc12   1/1   Running   0  3s  ← Containers running!
pod/day-deployment-7d4c8bf5c9-xyz89   1/1   Running   0  3s
deployment.apps/day-deployment  2/2  2  2  5s  ← Deployment ready!
```

### What Happens When You Delete?

**Cascade deletion** - deleting the Deployment deletes everything:

```bash
kubectl delete deployment day-deployment -n day-ns

# Kubernetes automatically:
# 1. Deletes Deployment
# 2. Deletes ReplicaSet (due to ownerReference)
# 3. Deletes Pods (due to ownerReference)
# 4. Kubelet stops containers
```

### Rolling Update Example:

```bash
# Update image
kubectl set image deployment/day-deployment day=day:v2 -n day-ns

# Deployment controller creates NEW ReplicaSet
kubectl get rs -n day-ns
# NAME                        DESIRED   CURRENT   READY
# day-deployment-7d4c8bf5c9   1         1         1     ← Old RS scaling down
# day-deployment-9f8a7bc6d1   1         1         1     ← New RS created!

# Eventually
# NAME                        DESIRED   CURRENT   READY
# day-deployment-7d4c8bf5c9   0         0         0     ← Old RS kept (for rollback)
# day-deployment-9f8a7bc6d1   2         2         2     ← New RS active
```

### Summary:

| You Create | What Gets Created | Who Creates It |
|------------|-------------------|----------------|
| **Deployment YAML** | Deployment object | kubectl/Pulumi → K8s API |
| - | ReplicaSet object | Deployment controller |
| - | Pod objects (2x) | ReplicaSet controller |
| - | Containers | Kubelet on nodes |

**Yes, Pods ARE created**, but through a **controller cascade**. This is the Kubernetes **declarative model** - you declare desired state (Deployment with 2 replicas), controllers make it happen.

---

## Final State

### Repository Structure:

```
k8s-exploration/
├── .github/workflows/
│   ├── pulumi-preview.yml     # New: Preview on PRs
│   ├── pulumi-up.yml          # New: Deploy on merge
│   ├── build-dawn.yml
│   ├── build-day.yml
│   └── build-dusk.yml
├── foundation/
│   ├── pulumi/
│   │   ├── __main__.py        # Modified: Generic for Day/Dusk, fixed spot instances
│   │   ├── Pulumi.yaml        # Modified: Updated description
│   │   ├── Pulumi.day.yaml    # New: Day cluster config
│   │   ├── Pulumi.dusk.yaml   # New: Dusk cluster config
│   │   ├── requirements.txt   # New: Python dependencies
│   │   ├── .gitignore         # New: Pulumi state files
│   │   └── README.md          # New: Multi-service README
│   ├── PULUMI-SETUP.md        # New: Setup guide
│   ├── DEPLOY-DAY-CLUSTER.md  # New: Day deployment guide
│   ├── services/
│   ├── k8s/
│   └── scripts/
└── CONVERSATION-HISTORY.md    # New: This file
```

### Commits Made:

1. **47dff59** - "Add Pulumi infrastructure as code for Dawn EKS cluster"
2. **55fe28f** - "Make Pulumi infrastructure generic for multi-service deployment"
3. **4fb3704** - "Remove Dawn from Pulumi management - keep only Day/Dusk"
4. **b855fcd** - "Fix spot instance configuration in Pulumi"

### Current Status:

- ✅ All code pushed to `claude/infrastructure-management-tools-01FzXt6XWcSBXTotEMTtsxAR`
- ✅ Working tree clean
- ✅ Ready to deploy Day cluster with Pulumi

### Next Steps:

1. Deploy Day cluster: `pulumi up` with day stack
2. Deploy Day application: `kubectl apply -f foundation/k8s/day/`
3. Set up ArgoCD for GitOps (Phase 5)
4. Deploy Dusk cluster (optional)

### Architecture Summary:

| Service | VPC CIDR | Cluster Name | Management | Status |
|---------|----------|--------------|------------|--------|
| **Dawn** | 10.0.0.0/16 | dawn-cluster | Manual (eksctl) | Running ✅ |
| **Day** | 10.1.0.0/16 | day-cluster | Pulumi | Ready to deploy |
| **Dusk** | 10.2.0.0/16 | dusk-cluster | Pulumi | Ready to deploy |

---

## Key Learnings

1. **Pulumi Preview** is useful but not a complete validation tool
2. **Pulumi CLI** is synchronous - waits for full convergence
3. **Pulumi Resources** contain URN, type, inputs, outputs, dependencies, provider, metadata, and state
4. **Kubernetes Resources** follow K8s API schema and are managed through Pulumi's K8s provider
5. **Pod Creation** happens through a controller cascade: Deployment → ReplicaSet → Pods
6. **ArgoCD** manages application resources (including HPA) through GitOps
7. **Spot Instances** in EKS require managed node groups with `capacity_type="SPOT"`
8. **Separation of Concerns** - Pulumi for infrastructure, ArgoCD for applications

---

**End of Conversation History**
