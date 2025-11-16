# Documentation Index

Welcome to the k8s-exploration documentation! This project is a comprehensive hands-on learning experience for Kubernetes (EKS), Infrastructure as Code with Pulumi, and modern CI/CD practices.

---

## 🚀 Quick Start

**New to this project?** Start here:

1. **[Project Overview](01-getting-started/overview.md)** - Understand what you'll build
2. **[Kubernetes 101](01-getting-started/kubernetes-101.md)** - Learn K8s fundamentals
3. **[Your First Deployment](01-getting-started/first-deployment.md)** - Deploy Dawn service (40 min)

**Total time to first deployment:** ~1 hour

---

## 📚 Documentation Structure

This documentation is organized into **7 progressive sections** that build on each other:

```
📁 01-getting-started/          ← Start here
📁 02-infrastructure-as-code/   ← Automate with Pulumi
📁 03-application-management/   ← Manage apps on K8s
📁 04-cicd-automation/          ← Automate builds & deploys
📁 05-kubernetes-deep-dives/    ← Understand internals
📁 06-troubleshooting/          ← Fix common issues
📁 07-next-steps/               ← Production guidance
```

---

## 01 - Getting Started

**Start your Kubernetes journey here.**

| Document | Description | Time |
|----------|-------------|------|
| **[overview.md](01-getting-started/overview.md)** | Project structure and deployment options | 10 min |
| **[kubernetes-101.md](01-getting-started/kubernetes-101.md)** | Kubernetes architecture and core concepts | 30 min |
| **[first-deployment.md](01-getting-started/first-deployment.md)** | Deploy your first app to EKS (Dawn cluster) | 40 min |

**Learning Objectives:**
- ✅ Understand Kubernetes core resources (Pods, Deployments, Services)
- ✅ Create an EKS cluster with eksctl
- ✅ Deploy a containerized application
- ✅ Expose your app via Application Load Balancer
- ✅ Monitor and troubleshoot your deployment

---

## 02 - Infrastructure as Code

**Automate infrastructure management with Pulumi.**

| Document | Description | Time |
|----------|-------------|------|
| **[why-infrastructure-as-code.md](02-infrastructure-as-code/why-infrastructure-as-code.md)** | Benefits of IaC and why this project uses Pulumi | 15 min |
| **[pulumi-setup.md](02-infrastructure-as-code/pulumi-setup.md)** | Install and configure Pulumi | 20 min |
| **[deploy-with-pulumi.md](02-infrastructure-as-code/deploy-with-pulumi.md)** | Deploy Day cluster with Pulumi | 30 min |
| **[two-tier-architecture.md](02-infrastructure-as-code/two-tier-architecture.md)** | Infrastructure vs application code separation | 20 min |

**Learning Objectives:**
- ✅ Understand Infrastructure as Code principles
- ✅ Deploy EKS clusters with Pulumi (Python)
- ✅ Manage infrastructure state
- ✅ Create reproducible environments

---

## 03 - Application Management

**Manage Kubernetes applications effectively.**

| Document | Description | Time |
|----------|-------------|------|
| **[application-as-code.md](03-application-management/application-as-code.md)** | Manage K8s apps with Pulumi instead of YAML | 30 min |
| **[namespace-strategies.md](03-application-management/namespace-strategies.md)** | Namespace creation and management patterns | 15 min |
| **[health-checks.md](03-application-management/health-checks.md)** | Liveness, readiness, and startup probes | 20 min |

**Learning Objectives:**
- ✅ Deploy applications with Pulumi
- ✅ Understand two-tier Pulumi architecture
- ✅ Configure namespace isolation
- ✅ Implement health checks for reliability

---

## 04 - CI/CD Automation

**Automate builds and deployments with GitHub Actions.**

| Document | Description | Time |
|----------|-------------|------|
| **[github-actions-setup.md](04-cicd-automation/github-actions-setup.md)** | Complete CI/CD setup guide | 60 min |
| **[image-deployment-workflow.md](04-cicd-automation/image-deployment-workflow.md)** | Advanced CI/CD deployment strategies | 20 min |

**Learning Objectives:**
- ✅ Configure GitHub Actions for automated builds
- ✅ Push images to AWS ECR automatically
- ✅ Understand image tagging strategies
- ✅ Deploy applications using CI-built images

---

## 05 - Kubernetes Deep Dives

**Understand how Kubernetes works under the hood.**

| Document | Description | Time |
|----------|-------------|------|
| **[deployment-hierarchy.md](05-kubernetes-deep-dives/deployment-hierarchy.md)** | How Deployments → ReplicaSets → Pods | 30 min |
| **[configmap-relationships.md](05-kubernetes-deep-dives/configmap-relationships.md)** | ConfigMap injection and relationships | 30 min |
| **[rolling-updates.md](05-kubernetes-deep-dives/rolling-updates.md)** | Zero-downtime deployment mechanics | 30 min |

**Learning Objectives:**
- ✅ Understand Kubernetes resource hierarchy
- ✅ Learn how rolling updates work
- ✅ Master configuration management
- ✅ Use exploration scripts for hands-on learning

---

## 06 - Troubleshooting

**Debug and fix common issues.**

| Document | Description | Use Case |
|----------|-------------|----------|
| **[common-issues.md](06-troubleshooting/common-issues.md)** | Solutions for common problems | When something breaks |
| **[debugging-checklist.md](06-troubleshooting/debugging-checklist.md)** | Systematic debugging approach | Quick reference |

**Covers:**
- ✅ Pulumi stack reference issues
- ✅ EKS authentication problems
- ✅ Pod startup failures
- ✅ Image pull errors
- ✅ Ingress/ALB issues
- ✅ CI/CD failures

---

## 07 - Next Steps

**Bridge from learning to production.**

| Document | Description | Purpose |
|----------|-------------|---------|
| **[learning-vs-production.md](07-next-steps/learning-vs-production.md)** | Production patterns and migration guidance | Understand production differences |
| **[recommended-resources.md](07-next-steps/recommended-resources.md)** | Curated learning materials | Continue your journey |

**Topics Covered:**
- ✅ Why this project uses simplified patterns
- ✅ How production systems differ
- ✅ Security, observability, reliability
- ✅ Books, courses, tools, communities

---

## 🎯 Learning Paths

Choose your path based on your goals:

### Path 1: Complete Beginner (Recommended)

**Goal:** Learn Kubernetes from scratch

1. [kubernetes-101.md](01-getting-started/kubernetes-101.md) - 30 min
2. [overview.md](01-getting-started/overview.md) - 10 min
3. [first-deployment.md](01-getting-started/first-deployment.md) - 40 min
4. **Explore:** Run scripts in `foundation/scripts/explore/`
5. [deployment-hierarchy.md](05-kubernetes-deep-dives/deployment-hierarchy.md) - 30 min
6. [configmap-relationships.md](05-kubernetes-deep-dives/configmap-relationships.md) - 30 min
7. [rolling-updates.md](05-kubernetes-deep-dives/rolling-updates.md) - 30 min

**Total time:** ~3 hours
**Outcome:** Solid Kubernetes fundamentals

### Path 2: Infrastructure as Code Focus

**Goal:** Master Pulumi and IaC

1. [overview.md](01-getting-started/overview.md) - 10 min
2. [why-infrastructure-as-code.md](02-infrastructure-as-code/why-infrastructure-as-code.md) - 15 min
3. [pulumi-setup.md](02-infrastructure-as-code/pulumi-setup.md) - 20 min
4. [deploy-with-pulumi.md](02-infrastructure-as-code/deploy-with-pulumi.md) - 30 min
5. [two-tier-architecture.md](02-infrastructure-as-code/two-tier-architecture.md) - 20 min
6. [application-as-code.md](03-application-management/application-as-code.md) - 30 min

**Total time:** ~2 hours
**Outcome:** Deploy infrastructure as code

### Path 3: CI/CD Automation

**Goal:** Set up automated builds and deployments

1. [overview.md](01-getting-started/overview.md) - 10 min
2. [first-deployment.md](01-getting-started/first-deployment.md) - 40 min (skip if done)
3. [github-actions-setup.md](04-cicd-automation/github-actions-setup.md) - 60 min
4. [image-deployment-workflow.md](04-cicd-automation/image-deployment-workflow.md) - 20 min

**Total time:** ~2.5 hours
**Outcome:** Full CI/CD pipeline

### Path 4: Production-Ready Systems

**Goal:** Understand production patterns

1. Complete Path 1 or 2 first
2. [learning-vs-production.md](07-next-steps/learning-vs-production.md) - 45 min
3. [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/) - External
4. [recommended-resources.md](07-next-steps/recommended-resources.md) - Browse

**Outcome:** Production-ready knowledge

---

## 🔍 Find What You Need

### By Task

**I want to...**
- **Deploy my first cluster** → [first-deployment.md](01-getting-started/first-deployment.md)
- **Use Infrastructure as Code** → [pulumi-setup.md](02-infrastructure-as-code/pulumi-setup.md)
- **Set up CI/CD** → [github-actions-setup.md](04-cicd-automation/github-actions-setup.md)
- **Understand how Deployments work** → [deployment-hierarchy.md](05-kubernetes-deep-dives/deployment-hierarchy.md)
- **Fix a broken deployment** → [common-issues.md](06-troubleshooting/common-issues.md)
- **Learn production patterns** → [learning-vs-production.md](07-next-steps/learning-vs-production.md)

### By Topic

**Kubernetes Basics:**
- [kubernetes-101.md](01-getting-started/kubernetes-101.md)
- [deployment-hierarchy.md](05-kubernetes-deep-dives/deployment-hierarchy.md)
- [rolling-updates.md](05-kubernetes-deep-dives/rolling-updates.md)

**AWS & EKS:**
- [first-deployment.md](01-getting-started/first-deployment.md)
- [kubernetes-101.md](01-getting-started/kubernetes-101.md) (EKS section)
- [common-issues.md](06-troubleshooting/common-issues.md) (EKS auth)

**Infrastructure as Code:**
- [why-infrastructure-as-code.md](02-infrastructure-as-code/why-infrastructure-as-code.md)
- [pulumi-setup.md](02-infrastructure-as-code/pulumi-setup.md)
- [two-tier-architecture.md](02-infrastructure-as-code/two-tier-architecture.md)

**Application Management:**
- [application-as-code.md](03-application-management/application-as-code.md)
- [namespace-strategies.md](03-application-management/namespace-strategies.md)
- [health-checks.md](03-application-management/health-checks.md)

**CI/CD:**
- [github-actions-setup.md](04-cicd-automation/github-actions-setup.md)
- [image-deployment-workflow.md](04-cicd-automation/image-deployment-workflow.md)

---

## 🏗️ Project Code Structure

Documentation explains the code. Here's where to find it:

```
k8s-exploration/
├── docs/                            # 👈 You are here
├── foundation/
│   ├── infrastructure/pulumi/       # Infrastructure as Code (EKS, VPC, nodes)
│   ├── applications/day-service/pulumi/  # Application resources (Deployments, Services)
│   ├── services/                    # Source code (dawn, day, dusk Flask apps)
│   ├── k8s/                         # Kubernetes YAML manifests
│   └── scripts/                     # Deployment automation
│       ├── explore/                 # 👈 Interactive learning scripts
│       ├── create-dawn-cluster.sh
│       └── deploy-dawn.sh
└── .github/workflows/               # CI/CD pipelines
```

**Exploration Scripts** (hands-on learning):
```bash
cd foundation/scripts/explore

./explore-deployment-hierarchy.sh       # See Deployment → ReplicaSet → Pod
./explore-configmap-relationships.sh    # Understand ConfigMap usage
./explore-rolling-updates.sh            # Watch rolling updates
```

---

## 💡 Key Concepts

### Learning Patterns vs Production

This project uses **simplified patterns for learning**. Key examples:

| Learning (This Project) | Production | Why Different |
|------------------------|------------|---------------|
| One cluster per service | Namespaces in shared cluster | Cost, resource efficiency |
| `:latest` image tags | Immutable SHA/semver tags | Reproducibility, rollback |
| "RC" terminology | Staging/canary | Industry standards |

**These patterns are intentional!** They make learning easier.
See [learning-vs-production.md](07-next-steps/learning-vs-production.md) for migration guidance.

### Two-Tier Pulumi Architecture

**Infrastructure tier:** EKS cluster, VPC, nodes (changes monthly)
**Application tier:** Deployments, Services, ConfigMaps (changes daily)

See [two-tier-architecture.md](02-infrastructure-as-code/two-tier-architecture.md)

---

## 🆘 Getting Help

### When Something Goes Wrong

1. **Check [common-issues.md](06-troubleshooting/common-issues.md)** - Most problems are covered
2. **Use [debugging-checklist.md](06-troubleshooting/debugging-checklist.md)** - Systematic approach
3. **Check logs** - `kubectl logs`, `kubectl describe`, `kubectl get events`
4. **Search the error** - Google the exact error message

### When You're Stuck Learning

1. **Re-read the doc** - Details are easy to miss the first time
2. **Try the exploration scripts** - Hands-on learning helps
3. **Read the code** - Documentation explains the working code
4. **Check [recommended-resources.md](07-next-steps/recommended-resources.md)** - External resources

---

## 📊 Documentation Statistics

- **33 total documents** (including reorganization plans)
- **7 themed sections** for structured learning
- **~12,000 lines** of comprehensive guides
- **3 interactive scripts** for hands-on learning
- **Multiple learning paths** for different goals

---

## 🎓 What You'll Learn

By completing this project, you will:

**Kubernetes:**
- ✅ Deploy and manage containerized applications
- ✅ Understand Pods, Deployments, Services, Ingress
- ✅ Configure auto-scaling and health checks
- ✅ Implement rolling updates
- ✅ Debug common issues

**AWS EKS:**
- ✅ Create and manage EKS clusters
- ✅ Integrate with AWS services (ALB, ECR, IAM)
- ✅ Configure VPC networking
- ✅ Use spot instances for cost savings

**Infrastructure as Code:**
- ✅ Manage infrastructure with Pulumi
- ✅ Version control infrastructure
- ✅ Create reproducible environments
- ✅ Implement two-tier architecture

**CI/CD:**
- ✅ Automate builds with GitHub Actions
- ✅ Push images to container registry
- ✅ Deploy automatically on code changes
- ✅ Implement image tagging strategies

**Production Awareness:**
- ✅ Understand learning vs production patterns
- ✅ Know what security, observability, reliability require
- ✅ Have a roadmap for production-ready systems

---

**Ready to start?** Head to [Getting Started](01-getting-started/) and begin your Kubernetes journey! 🚀
