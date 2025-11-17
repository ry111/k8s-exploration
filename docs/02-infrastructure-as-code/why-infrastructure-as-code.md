# Why Infrastructure as Code?

This brief guide explains the benefits of Infrastructure as Code (IaC) and why this project uses Pulumi to manage Kubernetes infrastructure.

## Your Learning Journey

This project demonstrates **two configuration approaches** (YAML vs IaC):

| Service | Configuration Approach | Key Learning |
|---------|------------------------|--------------|
| **Dawn** | YAML (kubectl) | Kubernetes fundamentals |
| **Day** | IaC (Pulumi) | Application & infrastructure as code |
| **Dusk** | TBD | Continuous deployment with ArgoCD (GitOps CD strategy) |

This progression shows YAML configuration (Dawn) versus IaC configuration (Day), both deployed via GitHub Actions. Dusk will demonstrate ArgoCD as a CD strategy. Each approach builds on the previous, showing different benefits and trade-offs.

## What is Infrastructure as Code?

**Infrastructure as Code (IaC)** is the practice of managing and provisioning infrastructure through code instead of manual processes.

**Traditional approach (Manual):**
```bash
# You run commands manually:
$ aws eks create-cluster --name my-cluster ...
$ aws ec2 create-vpc --cidr-block 10.0.0.0/16 ...
$ kubectl apply -f deployment.yaml
```

**IaC approach:**
```python
# You write code that declares what you want:
cluster = eks.Cluster("my-cluster",
    vpc_id=vpc.id,
    subnet_ids=[subnet1.id, subnet2.id],
)
```

The IaC tool handles creating, updating, and deleting resources to match your code.

---

## The Problem with Manual Infrastructure

In this project, you started with manual deployment using shell scripts:

```bash
cd foundation/provisioning/manual
./create-trantor-cluster.sh us-east-1      # Creates cluster manually
./build-and-push-dawn.sh us-east-1      # Builds and pushes image
./deploy-dawn.sh us-east-1               # Deploys application
```

**This works great for learning!** But it has limitations:

### 1. Hard to Reproduce
```bash
# If you want a second environment (staging), you have to:
# - Remember all the steps
# - Update cluster names, VPC CIDRs, namespaces
# - Run commands in the right order
# - Hope nothing changed since last time
```

### 2. No Change Tracking
- What changed between last week and today?
- Who made that VPC change?
- Can we revert to the previous configuration?

### 3. State Drift
- Someone manually edits a security group in AWS Console
- Your scripts no longer reflect reality
- Next deployment might break unexpectedly

### 4. Documentation Gets Outdated
- README says "2 nodes" but cluster has 3
- Scripts reference old subnet IDs
- Comments don't match reality

---

## Benefits of Infrastructure as Code

### 1. Version Control

Your infrastructure is in Git:

```bash
git log foundation/provisioning/pulumi/

# See who changed what and when:
commit abc123
Author: Alice
Date: Mon Nov 15

    Increase node count from 2 to 3

    diff --git a/__main__.py b/__main__.py
    -desired_nodes = 2
    +desired_nodes = 3
```

### 2. Reproducibility

Create identical environments:

```python
# Same code works for dev, staging, production
# Just different config values:

# Pulumi.dev.yaml
config:
  service_name: day
  vpc_cidr: 10.1.0.0/16
  desired_nodes: 2

# Pulumi.prod.yaml
config:
  service_name: day
  vpc_cidr: 10.2.0.0/16
  desired_nodes: 3
```

```bash
# Deploy to dev
pulumi stack select dev
pulumi up

# Deploy to production (same code, different config)
pulumi stack select prod
pulumi up
```

### 3. Preview Changes Before Applying

```bash
$ pulumi preview

Previewing update (dev):
     Type                 Name                Plan
 +   pulumi:pulumi:Stack  infrastructure-dev  create
 +   ├─ aws:ec2:Vpc       day-vpc             create
 +   ├─ aws:ec2:Subnet    day-subnet-1        create
 +   └─ eks:Cluster       terminus         create

Resources:
    + 4 to create
```

You see **exactly** what will change before it happens!

### 4. Automated State Management

Pulumi tracks the current state of your infrastructure:

```bash
# Pulumi knows:
# - What resources exist
# - Their current configuration
# - What needs to change to match your code

$ pulumi up
# Automatically:
# - Creates missing resources
# - Updates modified resources
# - Deletes removed resources
```

### 5. Prevent Configuration Drift

```bash
# Someone manually changes security group in AWS Console
# Next pulumi up detects and reverts the manual change:

$ pulumi up
Updating (dev):
     Type                    Name        Plan       Info
     aws:ec2:SecurityGroup   day-sg      update     [diff: ~ingress]

# Pulumi brings infrastructure back to match your code
```

---

## Why Pulumi Instead of Other Tools?

This project uses **Pulumi**, but there are several IaC tools:

| Tool | Language | Approach | When to Use |
|------|----------|----------|-------------|
| **Pulumi** | Python, TypeScript, Go, C#, Java | General-purpose programming language | Want to use familiar programming language, complex logic |
| **Terraform** | HCL (HashiCorp Configuration Language) | Declarative DSL | Industry standard, large community, tons of providers |
| **AWS CloudFormation** | YAML/JSON | Declarative, AWS-specific | AWS-only, native AWS integration |
| **AWS CDK** | Python, TypeScript, Java, C#, Go | Programming language, compiles to CloudFormation | AWS-only, want programming language |

### Why This Project Uses Pulumi

**1. Real Programming Language (Python)**

You're already writing Python for the Pulumi code. Same language for infrastructure!

```python
# This is just Python!
# Use loops, conditionals, functions, classes

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

**2. Type Safety and IDE Support**

```python
# Your IDE provides autocomplete and type checking!
cluster = eks.Cluster(
    "my-cluster",
    vpc_id=vpc.id,           # ← IDE knows what properties exist
    subnet_ids=[...],         # ← Type hints show what's expected
)
```

**3. State Management Included**

Pulumi automatically tracks state (what resources exist). No need to manually manage state files like Terraform.

**4. Preview Changes**

```bash
# Always see changes before applying
pulumi preview  # Show what will change
pulumi up       # Apply changes
```

**5. Multiple Backends**

```bash
# Use Pulumi Cloud (free for individuals)
pulumi login

# Or use local filesystem
pulumi login --local

# Or use S3
pulumi login s3://my-pulumi-state-bucket
```

---

## Manual vs IaC in This Project

### Trantor Cluster: Manual (Learning)

**Purpose:** Understand each step explicitly

```bash
# You manually run scripts to:
./foundation/provisioning/manual/create-trantor-cluster.sh us-east-1         # Create EKS cluster
./foundation/provisioning/manual/install-alb-controller-trantor.sh us-east-1 # Install ALB controller
# Then deploy services (see gitops/manual_deploy for deployment scripts)
```

**Best for:**
- Learning what each component does
- Understanding cluster creation process
- Hands-on experimentation

**Limitations:**
- Hard to create multiple environments
- Manual tracking of what exists
- No preview of changes

### Terminus Cluster: Pulumi IaC (Automation)

**Purpose:** Declare what you want, let Pulumi handle it

```python
# Single file describes entire infrastructure:
cluster = eks.Cluster("terminus", ...)
vpc = aws.ec2.Vpc("day-vpc", ...)
alb_controller = k8s.helm.v3.Release("alb-controller", ...)
```

```bash
# One command to create everything:
pulumi up

# One command to tear it down:
pulumi destroy
```

**Best for:**
- Multiple environments (dev, staging, prod)
- Team collaboration
- Auditable changes
- Reproducible infrastructure

---

## When to Use IaC

**Use IaC when:**
- ✅ You need multiple environments (dev, staging, production)
- ✅ Multiple people manage the infrastructure
- ✅ You want to track changes over time
- ✅ You need to reproduce infrastructure reliably
- ✅ Compliance requires audit trail

**Manual is fine when:**
- ✅ Learning and experimenting
- ✅ One-off throwaway environments
- ✅ Very simple, static infrastructure
- ✅ You're the only person managing it

**For this learning project:**
- ✅ Dawn (YAML via kubectl, deployed via GitHub Actions) - Learn Kubernetes fundamentals
- ✅ Day (Pulumi IaC via GitHub Actions) - Learn infrastructure as code
- ✅ Dusk (ArgoCD) - Learn continuous deployment

---

## Next Steps

Ready to try Infrastructure as Code?

1. **[Pulumi Setup](./pulumi-setup.md)** - Install and configure Pulumi
2. **[Deploy with Pulumi](./deploy-with-pulumi.md)** - Deploy the Terminus cluster
3. **[Two-Tier Architecture](./two-tier-architecture.md)** - Understand infrastructure vs application code

**Further Reading:**
- [What is Infrastructure as Code?](https://www.pulumi.com/what-is/what-is-infrastructure-as-code/)
- [Infrastructure as Code on AWS](https://aws.amazon.com/what-is/iac/)
- [Pulumi vs Terraform](https://www.pulumi.com/docs/intro/vs/terraform/)

---

**Key Takeaway:** Infrastructure as Code treats infrastructure like software - version controlled, tested, reviewed, and deployed automatically. It's not required for learning, but it's industry standard for production systems.
