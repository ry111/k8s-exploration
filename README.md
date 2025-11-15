# K8s Exploration

A comprehensive hands-on learning project for Kubernetes (EKS) and Infrastructure as Code using Pulumi.

## 📚 Documentation

All documentation has been moved to the **[docs/](docs/)** directory for better organization.

**Start here:** [docs/README.md](docs/README.md) - Complete documentation index

### Quick Links

- **Getting Started:** [docs/foundation-overview.md](docs/foundation-overview.md)
- **First Deployment:** [docs/quickstart-dawn.md](docs/quickstart-dawn.md)
- **Pulumi Setup:** [docs/pulumi-setup.md](docs/pulumi-setup.md)
- **Application as Code:** [docs/application-as-code-guide.md](docs/application-as-code-guide.md)

## 🏗️ Project Structure

```
k8s-exploration/
├── docs/                           # All documentation
│   ├── README.md                   # Documentation index
│   ├── foundation-overview.md      # Project overview
│   ├── quickstart-dawn.md          # Quick start guide
│   ├── pulumi-setup.md             # Pulumi IaC setup
│   ├── application-as-code-guide.md # Managing apps with Pulumi
│   └── ...                         # More guides
│
├── foundation/                     # Main experiment directory
│   ├── infrastructure/
│   │   └── pulumi/                 # Infrastructure as Code (EKS, VPC, nodes)
│   ├── applications/
│   │   └── day-service/
│   │       └── pulumi/             # Application resources (Deployments, Services)
│   └── k8s/                        # Kubernetes manifests
│
├── explore-*.sh                    # Interactive exploration scripts
└── .github/workflows/              # CI/CD pipelines
```

## 🚀 Quick Start

### Option 1: Single Cluster (Recommended for Learning)
```bash
# See docs/quickstart-dawn.md for full guide
cd foundation
./scripts/create-dawn-cluster.sh
./scripts/deploy-dawn.sh
```

### Option 2: Infrastructure as Code with Pulumi
```bash
# See docs/pulumi-setup.md for full guide
cd foundation/infrastructure/pulumi
pulumi up
```

## 🎯 What You'll Learn

- ✅ **Kubernetes Fundamentals** - Deployments, Services, ConfigMaps, HPA
- ✅ **AWS EKS** - Managed Kubernetes on AWS
- ✅ **Infrastructure as Code** - Pulumi for declarative infrastructure
- ✅ **Application Management** - Managing K8s apps with code (not YAML)
- ✅ **CI/CD** - GitHub Actions for automated deployments
- ✅ **Cost Optimization** - Using spot instances effectively

## 📖 Key Concepts Explored

### Kubernetes Deep Dives
- [Deployment Hierarchy](docs/deployment-hierarchy.md) - How Deployments → ReplicaSets → Pods
- [ConfigMap Relationships](docs/configmap-relationships.md) - Managing configuration
- [Rolling Updates](docs/rolling-update-mechanism.md) - Zero-downtime deployments

### Infrastructure as Code
- [Pulumi Resource Strategy](docs/pulumi-resource-strategy.md) - What to manage where
- [Application as Code](docs/application-as-code-guide.md) - Python instead of YAML

## 🛠️ Interactive Scripts

Explore Kubernetes concepts hands-on:
```bash
./explore-deployment-hierarchy.sh      # Visualize Deployment → Pod relationship
./explore-configmap-relationships.sh   # See ConfigMap to Pod connections
./explore-rolling-updates.sh           # Watch rolling updates in action
```

## 💰 Cost Estimate

**Single Cluster (Spot Instances):** ~$111-121/month
- EKS Control Plane: ~$73/month
- 2× t3.small spot nodes: ~$18/month
- ALB: ~$21-26/month

See [docs/foundation-overview.md](docs/foundation-overview.md) for detailed breakdown.

## 📦 What's Included

### Three Example Services
- **Dawn** - Manual deployment (eksctl)
- **Day** - Pulumi-managed infrastructure and application
- **Dusk** - Pulumi-managed infrastructure

### Infrastructure
- VPC with public/private subnets
- EKS clusters with OIDC
- Managed node groups (spot instances)
- AWS ALB Ingress Controller
- HPA with metrics server

### CI/CD
- GitHub Actions workflows
- Automated builds and deployments
- Pulumi preview on PRs

## 🎓 Learning Path

1. **Start:** [Foundation Overview](docs/foundation-overview.md)
2. **Deploy:** [Quick Start Dawn](docs/quickstart-dawn.md)
3. **Learn:** [Deployment Hierarchy](docs/deployment-hierarchy.md)
4. **Automate:** [Pulumi Setup](docs/pulumi-setup.md)
5. **Scale:** [Application as Code](docs/application-as-code-guide.md)
6. **Master:** [Rolling Updates](docs/rolling-update-mechanism.md)

## 🤝 Contributing

This is a personal learning project. Feel free to fork and adapt for your own learning journey!

## 📝 License

This project is for educational purposes.

---

**Ready to start?** Head to [docs/README.md](docs/README.md) for the complete documentation index.
