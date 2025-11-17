# Why Infrastructure as Code?

This guide explains the benefits of Infrastructure as Code (IaC) and why this project uses Pulumi to manage both infrastructure and application resources.

## Two Types of Infrastructure as Code

Before diving deeper, it's important to understand that "Infrastructure as Code" can mean two different things in this project:

### 1. Infrastructure Provisioning (AWS Resources)

Creating the underlying cloud infrastructure: VPC, EKS cluster, load balancers, IAM roles.

**Example:** Creating an EKS cluster with Pulumi
```python
cluster = eks.Cluster("terminus",
    vpc_id=vpc.id,
    subnet_ids=[subnet1.id, subnet2.id],
    desired_capacity=3
)
```

### 2. Application Deployment (Kubernetes Resources)

Deploying your applications: Deployments, Services, Ingress, ConfigMaps.

**Example:** Deploying the Day service with Pulumi
```python
deployment = k8s.apps.v1.Deployment("day",
    spec={
        "replicas": 3,
        "template": {
            "spec": {
                "containers": [{
                    "name": "day",
                    "image": "my-registry/day:v1"
                }]
            }
        }
    }
)
```

**Key Insight:** Pulumi can manage **both layers** with the same tool and language. This is different from the traditional approach of using Terraform/CloudFormation for infrastructure and kubectl/Helm for applications.

## Your Learning Journey

This project demonstrates **different approaches** to managing these two layers:

| Service | Cluster | Infrastructure | Application | Key Learning |
|---------|---------|---------------|-------------|--------------|
| **Dawn** | Trantor | Manual scripts | YAML + kubectl | Kubernetes fundamentals, hands-on learning |
| **Day** | Terminus | Pulumi IaC | Pulumi IaC | Both layers as code, unified tooling |
| **Dusk** | Terminus | Pulumi IaC | _TBD_ | Exploring deployment strategies on IaC infrastructure |

**Why this progression?**
- **Dawn** (on Trantor): Manual foundation - you understand each piece step by step
- **Day** (on Terminus): Full automation - both infrastructure and apps managed as code
- **Dusk** (on Terminus): Reuses the Pulumi-provisioned infrastructure, exploring different deployment approaches

---

## What is Infrastructure as Code?

**Infrastructure as Code (IaC)** is the practice of managing and provisioning infrastructure through code instead of manual processes.

**Traditional approach:**
```bash
# Manual commands, no tracking, hard to reproduce:
$ aws eks create-cluster --name my-cluster ...
$ kubectl apply -f deployment.yaml
$ aws ec2 modify-security-group ...
```

**IaC approach:**
```python
# Declare what you want in code:
cluster = eks.Cluster("my-cluster", ...)
deployment = k8s.apps.v1.Deployment("my-app", ...)
```

The IaC tool handles creating, updating, and deleting resources to match your code.

---

## The Problem with Manual Infrastructure

Your manual deployment (Trantor cluster) uses shell scripts:

```bash
cd foundation/provisioning/manual
./create-trantor-cluster.sh us-east-1
./install-alb-controller-trantor.sh us-east-1

cd ../../gitops/manual_deploy
./deploy-dawn.sh trantor us-east-1
```

**This is great for learning** - you see every step explicitly. But it has limitations:

**1. Hard to Reproduce**
- Want a second environment? Remember all steps, update all names, run in correct order
- Scripts work once, then configuration drifts

**2. No Change Tracking**
- What changed? Who changed it? Can we revert?
- README says "2 nodes" but cluster has 3

**3. Manual State Management**
- What resources exist right now?
- Is that security group from last week still in use?

**4. No Safety Net**
- Changes apply immediately
- No preview before execution
- No easy rollback

---

## Benefits of Infrastructure as Code

### 1. Version Control & Audit Trail

Your infrastructure is in Git with full history:

```bash
$ git log foundation/provisioning/pulumi/

commit abc123
Author: Alice
Date: Mon Nov 15

    Increase node count from 2 to 3

    diff --git a/__main__.py b/__main__.py
    -desired_nodes = 2
    +desired_nodes = 3
```

### 2. Reproducibility

Create identical environments with different configs:

```bash
# Same code, different config values
pulumi stack select dev
pulumi up      # Creates dev environment

pulumi stack select production
pulumi up      # Creates production environment (different VPC CIDR, more nodes)
```

### 3. Preview Before Apply

See **exactly** what will change before it happens:

```bash
$ pulumi preview

Previewing update (dev):
     Type                 Name                Plan
 +   pulumi:pulumi:Stack  infrastructure-dev  create
 +   ├─ aws:ec2:Vpc       day-vpc             create
 +   ├─ eks:Cluster       terminus            create
 +   └─ k8s:apps:Deployment day               create

Resources:
    + 4 to create
```

### 4. Automated State Management

The tool tracks what exists and what needs to change:

```bash
$ pulumi up
# Automatically:
# - Creates missing resources
# - Updates modified resources
# - Deletes removed resources
# - Detects and corrects manual changes (drift)
```

### 5. Consistency & Standards

Enforce organizational standards through code:

```python
# Every cluster gets the same security settings
def create_cluster(name):
    return eks.Cluster(name,
        enabled_cluster_log_types=["api", "audit"],  # Required logging
        encryption_config=[...],                      # Required encryption
        tags={"ManagedBy": "Pulumi"}                  # Required tags
    )
```

---

## Why Pulumi Instead of Other Tools?

There are several IaC tools available:

| Tool | Language | Scope | Best For |
|------|----------|-------|----------|
| **Pulumi** | Python, TypeScript, Go, etc. | Multi-cloud | Using real programming languages, both infra + apps |
| **Terraform** | HCL (custom DSL) | Multi-cloud | Industry standard, huge ecosystem, infra focus |
| **AWS CDK** | TypeScript, Python, etc. | AWS only | AWS-native, compiles to CloudFormation |
| **kubectl/Helm** | YAML | Kubernetes only | Application deployment only (not infrastructure) |

### Why This Project Uses Pulumi

**1. Real Programming Language**

Use Python (or TypeScript, Go, etc.) - not a custom DSL:

```python
# Use loops, functions, conditionals - it's just Python
subnets = []
for i, az in enumerate(availability_zones):
    subnet = aws.ec2.Subnet(
        f"{service_name}-subnet-{i}",
        vpc_id=vpc.id,
        availability_zone=az,
        cidr_block=f"{vpc_cidr_base}.{i}.0/24",
    )
    subnets.append(subnet)
```

**2. Unified Tooling for Both Layers**

Manage **infrastructure** (AWS) and **applications** (Kubernetes) with the same tool:

```python
# Infrastructure layer
cluster = eks.Cluster("terminus", ...)
vpc = aws.ec2.Vpc("day-vpc", ...)

# Application layer (same file, same language!)
deployment = k8s.apps.v1.Deployment("day", ...)
service = k8s.core.v1.Service("day-service", ...)
```

**3. Type Safety & IDE Support**

Full autocomplete, type checking, and inline documentation:

```python
cluster = eks.Cluster(
    "my-cluster",
    vpc_id=vpc.id,        # IDE shows available properties
    subnet_ids=[...],      # Type hints show expected types
)
```

**4. Preview Every Change**

Always see what will happen before it happens:

```bash
pulumi preview  # Show planned changes
pulumi up       # Apply changes (with confirmation)
```

**5. Flexible State Backends**

Choose where to store state:

```bash
pulumi login                              # Pulumi Cloud (free)
pulumi login --local                      # Local filesystem
pulumi login s3://my-state-bucket         # S3
```

---

## When to Use IaC

**Use IaC when you need:**
- ✅ Multiple environments (dev, staging, production)
- ✅ Team collaboration with audit trail
- ✅ Reproducible infrastructure
- ✅ Change previews before applying
- ✅ Automated drift detection

**Manual is fine for:**
- ✅ Learning and experimentation
- ✅ One-off throwaway environments
- ✅ Solo projects with simple, static infrastructure

**For this project:**
- **Dawn** (Trantor): Manual infrastructure + YAML applications = Learn the fundamentals
- **Day** (Terminus): Pulumi for both layers = Learn full automation
- **Dusk** (Terminus): Pulumi infrastructure + TBD deployment = Explore deployment strategies

---

## Next Steps

Ready to try Infrastructure as Code?

1. **[Pulumi Setup](./pulumi-setup.md)** - Install and configure Pulumi
2. **[Two-Tier Architecture](./two-tier-architecture.md)** - Deep dive into infrastructure vs application layers
3. **[Deploy with Pulumi](./deploy-with-pulumi.md)** - Deploy the Terminus cluster

**Further Reading:**
- [What is Infrastructure as Code?](https://www.pulumi.com/what-is/what-is-infrastructure-as-code/)
- [Infrastructure as Code on AWS](https://aws.amazon.com/what-is/iac/)
- [Pulumi vs Terraform](https://www.pulumi.com/docs/intro/vs/terraform/)

---

**Key Takeaway:** Infrastructure as Code treats your infrastructure like software - version controlled, reviewed, tested, and deployed automatically. In this project, you'll see how Pulumi manages **both** infrastructure provisioning and application deployment as code.
