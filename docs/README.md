# Documentation Index

Welcome to the k8s-exploration documentation. This directory contains all guides and documentation for this Kubernetes and EKS learning project.

## 📚 Quick Start Guides

### Getting Started (Start Here!)
- **[foundation-overview.md](foundation-overview.md)** - Overview of the foundation experiment and deployment options
- **[quickstart-dawn.md](quickstart-dawn.md)** - Quick start guide for deploying the Dawn cluster (recommended for beginners)
- **[quickstart-dawn-ci.md](quickstart-dawn-ci.md)** - Setting up CI/CD for the Dawn cluster

## 🏗️ Infrastructure as Code (Pulumi)

### Setup & Deployment
- **[pulumi-setup.md](pulumi-setup.md)** - Complete Pulumi setup guide for EKS infrastructure
- **[deploy-day-cluster.md](deploy-day-cluster.md)** - Step-by-step guide for deploying the Day cluster with Pulumi

### Strategy & Best Practices
- **[pulumi-resource-strategy.md](pulumi-resource-strategy.md)** - What to manage with Pulumi vs GitOps
- **[application-as-code-guide.md](application-as-code-guide.md)** - Managing Kubernetes applications using Pulumi (instead of YAML)
- **[namespace-management-strategy.md](namespace-management-strategy.md)** - Namespace creation and management patterns

## 🔧 CI/CD & Automation

- **[ci-setup.md](ci-setup.md)** - GitHub Actions setup for automated image builds
- **[cicd-image-deployment.md](cicd-image-deployment.md)** - CI/CD image deployment workflows
- **[health-checks.md](health-checks.md)** - Health check configuration and monitoring

## 📖 Kubernetes Deep Dives

### Fundamentals
- **[kubernetes-fundamentals.md](kubernetes-fundamentals.md)** - Complete guide to Kubernetes architecture, concepts, and cloud integration

### Core Concepts
- **[deployment-hierarchy.md](deployment-hierarchy.md)** - How Deployments → ReplicaSets → Pods work
- **[configmap-relationships.md](configmap-relationships.md)** - ConfigMap relationships with Deployments and Pods
- **[rolling-update-mechanism.md](rolling-update-mechanism.md)** - Deep dive into Kubernetes rolling updates

## 🔧 Troubleshooting & Fixes

- **[eks-github-actions-auth-fix.md](eks-github-actions-auth-fix.md)** - Fixing EKS authentication in GitHub Actions
- **[stack-reference-fix.md](stack-reference-fix.md)** - Pulumi stack reference configuration fixes

## 🗂️ Documentation Organization

```
docs/
├── README.md (this file)           # Documentation index
│
├── Quick Start
│   ├── foundation-overview.md      # Project overview
│   ├── quickstart-dawn.md          # Deploy first cluster
│   └── quickstart-dawn-ci.md       # CI/CD setup
│
├── Pulumi & Infrastructure
│   ├── pulumi-setup.md             # Pulumi installation & setup
│   ├── deploy-day-cluster.md       # Day cluster deployment
│   ├── pulumi-resource-strategy.md # What to manage where
│   ├── application-as-code-guide.md # Apps with Pulumi
│   └── namespace-management-strategy.md # Namespace patterns
│
├── CI/CD & Automation
│   ├── ci-setup.md                 # GitHub Actions configuration
│   ├── cicd-image-deployment.md    # Image deployment workflows
│   └── health-checks.md            # Health check best practices
│
├── Kubernetes Deep Dives
│   ├── kubernetes-fundamentals.md  # K8s architecture overview
│   ├── deployment-hierarchy.md     # Deployment → RS → Pod
│   ├── configmap-relationships.md  # ConfigMap usage
│   └── rolling-update-mechanism.md # Rolling update details
│
├── Troubleshooting
│   ├── eks-github-actions-auth-fix.md # EKS auth fixes
│   └── stack-reference-fix.md      # Pulumi stack references
│
└── archive/                        # Historical conversation logs
    ├── partial-conversation-history-1.md
    └── partial-conversation-history-2.md
```

## 🏗️ Project Structure

For code and implementation details, see:
- **Infrastructure Pulumi:** [`foundation/infrastructure/pulumi/`](../foundation/infrastructure/pulumi/) - EKS clusters, VPC, nodes
- **Application Pulumi:** [`foundation/applications/day-service/pulumi/`](../foundation/applications/day-service/pulumi/) - Day service Kubernetes resources
- **Application Source Code:** [`foundation/services/`](../foundation/services/) - Dawn, Day, Dusk Flask apps
- **Kubernetes Manifests:** [`foundation/k8s/`](../foundation/k8s/) - YAML manifests for all services
- **Deployment Scripts:** [`foundation/scripts/`](../foundation/scripts/) - Bash automation scripts
- **Exploration Scripts:** [`foundation/scripts/explore/`](../foundation/scripts/explore/) - Interactive learning tools

## 🚀 Recommended Learning Path

**For Complete Beginners:**
1. **[kubernetes-fundamentals.md](kubernetes-fundamentals.md)** - Learn Kubernetes architecture and core concepts
2. **[foundation-overview.md](foundation-overview.md)** - Understand the project structure
3. **[quickstart-dawn.md](quickstart-dawn.md)** - Deploy your first cluster (takes ~40 min)
4. **[deployment-hierarchy.md](deployment-hierarchy.md)** - Learn how Kubernetes creates Pods
5. Run exploration scripts in `foundation/scripts/explore/` - Hands-on learning
6. **[rolling-update-mechanism.md](rolling-update-mechanism.md)** - Zero-downtime deployments

**For Infrastructure as Code:**
1. **[pulumi-setup.md](pulumi-setup.md)** - Install and configure Pulumi
2. **[deploy-day-cluster.md](deploy-day-cluster.md)** - Deploy Day cluster with IaC
3. **[pulumi-resource-strategy.md](pulumi-resource-strategy.md)** - Best practices
4. **[application-as-code-guide.md](application-as-code-guide.md)** - Manage apps with code
5. **[namespace-management-strategy.md](namespace-management-strategy.md)** - Advanced patterns

**For CI/CD Setup:**
1. **[ci-setup.md](ci-setup.md)** - Configure GitHub Actions for image builds
2. **[quickstart-dawn-ci.md](quickstart-dawn-ci.md)** - Deploy with CI/CD
3. **[cicd-image-deployment.md](cicd-image-deployment.md)** - Advanced workflows
4. **[health-checks.md](health-checks.md)** - Production-ready monitoring

## 🎯 Quick Reference by Task

**I want to...**
- **Learn Kubernetes from scratch** → [kubernetes-fundamentals.md](kubernetes-fundamentals.md)
- **Deploy my first cluster** → [quickstart-dawn.md](quickstart-dawn.md)
- **Use Infrastructure as Code** → [pulumi-setup.md](pulumi-setup.md)
- **Set up CI/CD** → [ci-setup.md](ci-setup.md)
- **Understand how Deployments work** → [deployment-hierarchy.md](deployment-hierarchy.md)
- **Manage configurations** → [configmap-relationships.md](configmap-relationships.md)
- **Do zero-downtime updates** → [rolling-update-mechanism.md](rolling-update-mechanism.md)
- **Understand EKS and cloud integration** → [kubernetes-fundamentals.md](kubernetes-fundamentals.md#eks-managed-kubernetes-on-aws)
- **Fix EKS auth issues** → [eks-github-actions-auth-fix.md](eks-github-actions-auth-fix.md)
- **Choose Pulumi vs GitOps** → [pulumi-resource-strategy.md](pulumi-resource-strategy.md)

## 💡 Need Help?

- **Troubleshooting?** Check the [Troubleshooting](#-troubleshooting--fixes) section above
- **Each guide has** detailed troubleshooting sections at the end
- **Interactive learning** - Run scripts in `foundation/scripts/explore/`
- **Hands-on examples** - All docs include practical examples from this repo

## 📊 Documentation Statistics

- **22 markdown files** across the repository (including new Kubernetes fundamentals guide)
- **~1,200 lines** of comprehensive guides
- **3 interactive exploration scripts** for hands-on learning
- **Multiple deployment paths** (manual, Pulumi, CI/CD)

---

**Ready to start?** Choose your path above and dive in! 🚀
