# Documentation Index

Welcome to the k8s-exploration documentation. This directory contains all guides and documentation for this Kubernetes and EKS learning project.

## 📚 Quick Start Guides

### Getting Started
- **[foundation-overview.md](foundation-overview.md)** - Overview of the foundation experiment and deployment options
- **[quickstart-dawn.md](quickstart-dawn.md)** - Quick start guide for deploying the Dawn cluster (recommended for beginners)
- **[quickstart-dawn-ci.md](quickstart-dawn-ci.md)** - Setting up CI/CD for the Dawn cluster

### Pulumi Infrastructure as Code
- **[pulumi-setup.md](pulumi-setup.md)** - Complete Pulumi setup guide for EKS infrastructure
- **[deploy-day-cluster.md](deploy-day-cluster.md)** - Step-by-step guide for deploying the Day cluster with Pulumi
- **[pulumi-resource-strategy.md](pulumi-resource-strategy.md)** - Best practices for deciding what resources to manage with Pulumi vs GitOps

### Application Management
- **[application-as-code-guide.md](application-as-code-guide.md)** - Guide for managing Kubernetes applications using Pulumi (instead of YAML)

## 🔧 Configuration & Setup

- **[ci-setup.md](ci-setup.md)** - Detailed CI/CD configuration guide
- **[health-checks.md](health-checks.md)** - Health check configuration and best practices

## 📖 Deep Dive Guides

### Kubernetes Concepts
- **[deployment-hierarchy.md](deployment-hierarchy.md)** - Understanding how Deployments create and manage Pods
- **[configmap-relationships.md](configmap-relationships.md)** - How ConfigMaps relate to Deployments and Pods
- **[rolling-update-mechanism.md](rolling-update-mechanism.md)** - Deep dive into Kubernetes rolling update strategy

## 🗂️ Documentation Organization

```
docs/
├── README.md (this file)
│
├── Quick Start
│   ├── foundation-overview.md
│   ├── quickstart-dawn.md
│   └── quickstart-dawn-ci.md
│
├── Pulumi & Infrastructure
│   ├── pulumi-setup.md
│   ├── deploy-day-cluster.md
│   ├── pulumi-resource-strategy.md
│   └── application-as-code-guide.md
│
├── Configuration
│   ├── ci-setup.md
│   └── health-checks.md
│
└── Deep Dives
    ├── deployment-hierarchy.md
    ├── configmap-relationships.md
    └── rolling-update-mechanism.md
```

## 🏗️ Project Structure

For code and implementation details, see:
- **Infrastructure Pulumi:** `foundation/infrastructure/pulumi/`
- **Application Pulumi:** `foundation/applications/day-service/pulumi/`
- **Application Source Code:** `foundation/services/` (Dawn, Day, Dusk)
- **Kubernetes Manifests:** `foundation/k8s/`
- **Deployment Scripts:** `foundation/scripts/`
- **Exploration Scripts:** `foundation/scripts/explore/`

## 🚀 Recommended Learning Path

1. Start with **[foundation-overview.md](foundation-overview.md)** to understand the project structure
2. Follow **[quickstart-dawn.md](quickstart-dawn.md)** to deploy your first cluster
3. Read **[deployment-hierarchy.md](deployment-hierarchy.md)** to understand Kubernetes fundamentals
4. Explore **[pulumi-setup.md](pulumi-setup.md)** to learn Infrastructure as Code
5. Master **[application-as-code-guide.md](application-as-code-guide.md)** for managing applications with Pulumi
6. Deep dive into **[rolling-update-mechanism.md](rolling-update-mechanism.md)** for production deployments

## 💡 Need Help?

- Check the specific guide related to your task
- Each guide includes troubleshooting sections
- Explore the interactive scripts in `foundation/scripts/explore/`
