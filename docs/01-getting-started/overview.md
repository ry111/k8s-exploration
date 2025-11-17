# Foundation - EKS Infrastructure Exploration

This project demonstrates deploying Python microservices (Dawn, Day, Dusk) to AWS EKS with production and RC tiers using a **decoupled architecture** where clusters are infrastructure and services are applications.

## Quick Start Options

### Option 1: Manual Cluster (Trantor) with Spot Instances - **RECOMMENDED**
- **Time:** ~40 minutes
- **Guide:** [first-deployment.md](first-deployment.md)
- **Method:** Manual scripts in `foundation/provisioning/manual/`

### Option 2: Infrastructure as Code with Pulumi (Terminus cluster)
- **Time:** ~30 minutes
- **Guide:** [../../02-infrastructure-as-code/pulumi-setup.md](../02-infrastructure-as-code/pulumi-setup.md)
- **Method:** Declarative Pulumi programs in `foundation/provisioning/pulumi/`

## Architecture

**Decoupled Design: Clusters ≠ Services**

### Clusters (Infrastructure Layer)

| Cluster | Provisioning | VPC CIDR | Purpose |
|---------|--------------|----------|---------|
| **Trantor** | Manual (eksctl) | 10.0.0.0/16 | Learn manual cluster creation |
| **Terminus** | IaC (Pulumi) | 10.2.0.0/16 | Learn declarative infrastructure |

### Services (Application Layer)

This project demonstrates **two configuration approaches** (YAML vs IaC) and different CD strategies:

| Service | Cluster | CI/CD | Configuration Approach | Learning Goal |
|---------|---------|-------|------------------------|---------------|
| **Dawn** | Trantor | GitHub Actions | kubectl + YAML | Understand Kubernetes fundamentals |
| **Day** | Trantor | GitHub Actions | IaC (Pulumi) | Learn application-as-code |
| **Dusk** | Terminus | GitHub Actions (CI) + ArgoCD (CD) | TBD | Master continuous deployment with GitOps |

**Key Learning:** All three services are automated via CI/CD. Dawn and Day show two configuration approaches (YAML vs IaC), both deployed via GitHub Actions (push-based). Dusk demonstrates ArgoCD (pull-based GitOps) as a CD strategy. Each service demonstrates a different pattern while using the same underlying Kubernetes concepts.

### Service Isolation

- Each service has its own namespaces (prod + RC)
- Production deployment (2-5 replicas)
- RC deployment (1-3 replicas)
- Multiple services share cluster infrastructure via namespace isolation

## Prerequisites

### Required Tools

```bash
# AWS CLI
aws --version

# eksctl
eksctl version

# kubectl
kubectl version --client

# Helm
helm version

# Docker
docker --version
```

### Installation

```bash
# macOS
brew install awscli eksctl kubectl helm docker

# Linux
# Follow official installation guides for each tool
```

### AWS Configuration

```bash
# Configure AWS credentials
aws configure

# Verify access
aws sts get-caller-identity
```

## Deployment Steps (Trantor Cluster - Manual)

For detailed step-by-step instructions, see [first-deployment.md](first-deployment.md).

### 1. Create Trantor EKS Cluster (~15-20 minutes)

```bash
cd foundation/provisioning/manual

# Make scripts executable
chmod +x *.sh

# Create Trantor cluster
./create-trantor-cluster.sh us-east-1
```

This creates:
- `trantor` cluster with 2 t3.small nodes (spot instances)
- OIDC provider for IAM roles
- Managed node group with autoscaling

### 2. Install AWS Load Balancer Controller (~5 minutes)

```bash
./install-alb-controller-trantor.sh us-east-1
```

This installs the ALB Ingress Controller on Trantor cluster to enable Ingress resources.

### 3. Build and Deploy Services (~10 minutes)

```bash
cd ../../gitops/manual_deploy

# Verify images exist in ECR (built by GitHub Actions)
aws ecr describe-images --repository-name dawn --region us-east-1
aws ecr describe-images --repository-name day --region us-east-1

# Deploy Dawn service to Trantor cluster (kubectl + YAML)
./deploy-dawn.sh trantor us-east-1

# Day service is deployed via Pulumi (see docs/03-application-management/application-as-code.md)
```

This:
- Verifies container images exist in ECR (built automatically by GitHub Actions)
- Deploys each service independently to the specified cluster
- Services can be deployed to any cluster by name

## Verification

### Check Cluster Status

```bash
# List all clusters
eksctl get cluster --region us-east-1

# Get nodes for Trantor cluster
kubectl get nodes --context trantor
```

### Check Deployments

```bash
# Set context to Trantor cluster
aws eks update-kubeconfig --name trantor --region us-east-1

# View Dawn service resources
kubectl get all -n dawn-ns
kubectl get all -n dawn-rc-ns

# View Day service resources
kubectl get all -n day-ns
kubectl get all -n day-rc-ns
```

### Get Application Load Balancer URLs

```bash
# Get ALB hostname for production
kubectl get ingress dawn-ingress -n dawn-ns

# Get ALB hostname for RC
kubectl get ingress dawn-rc-ingress -n dawn-rc-ns
```

### Test Services

```bash
# Get ALB URL
ALB_URL=$(kubectl get ingress dawn-ingress -n dawn-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test production endpoint
curl http://$ALB_URL/
curl http://$ALB_URL/health
curl http://$ALB_URL/info

# Get RC ALB URL
RC_ALB_URL=$(kubectl get ingress dawn-rc-ingress -n dawn-rc-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test RC endpoint
curl http://$RC_ALB_URL/health
```

## Project Structure

```
foundation/
├── provisioning/
│   ├── pulumi/              # Infrastructure as Code (Pulumi)
│   │   ├── __main__.py      # EKS cluster, VPC, nodes
│   │   └── Pulumi.prod.yaml  # Terminus cluster config
│   └── manual/              # Manual cluster provisioning scripts (Trantor)
│       ├── create-trantor-cluster.sh
│       └── install-alb-controller-trantor.sh
├── gitops/
│   ├── pulumi_deploy/       # Application deployment (Pulumi IaC)
│   │   └── __main__.py      # Deployment, Service, HPA, etc.
│   └── manual_deploy/       # kubectl + YAML deployments + manifests
│       ├── deploy-dawn.sh           # Deploy Dawn to specified cluster
│       ├── delete-service-images.sh # Delete ECR images for a service
│       ├── dawn/            # Dawn Kubernetes manifests
│       │   ├── prod/        # Production manifests
│       │   └── rc/          # RC manifests
│       ├── day/             # Day Kubernetes manifests
│       │   ├── prod/
│       │   └── rc/
│       └── dusk/            # Dusk Kubernetes manifests
│           ├── prod/
│           └── rc/
├── services/         # Python Flask applications
│   ├── dawn/
│   ├── day/
│   └── dusk/
└── scripts/          # Interactive learning scripts
    └── explore/
        ├── explore-deployment-hierarchy.sh
        ├── explore-configmap-relationships.sh
        └── explore-rolling-updates.sh
```

## Resource Configuration

### Production Tier
- **Replicas:** 2 initial (HPA: 2-5)
- **CPU:** 50m request, 200m limit
- **Memory:** 64Mi request, 256Mi limit
- **Environment:** production
- **Log Level:** info

### RC Tier
- **Replicas:** 1 initial (HPA: 1-3)
- **CPU:** 50m request, 200m limit
- **Memory:** 64Mi request, 256Mi limit
- **Environment:** rc
- **Log Level:** debug

## Cleanup

**⚠️ WARNING: This deletes the cluster and resources!**

Cleanup follows separation of concerns - delete infrastructure and applications separately:

```bash
# Delete application images (optional)
cd foundation/gitops/manual_deploy
./delete-service-images.sh dawn us-east-1
./delete-service-images.sh day us-east-1

# Delete infrastructure
cd ../../provisioning/manual
./delete-cluster.sh trantor us-east-1
```

This approach:
- **Application cleanup**: Deletes ECR repositories (dawn, day)
- **Infrastructure cleanup**: Deletes EKS cluster and associated AWS resources
- Each deletion requires typing `DELETE` to confirm

## Troubleshooting

### Pods not starting

```bash
# Check pod status
kubectl get pods -n dawn-ns

# View pod logs
kubectl logs -n dawn-ns <pod-name>

# Describe pod for events
kubectl describe pod -n dawn-ns <pod-name>
```

### Ingress not creating ALB

```bash
# Check ALB controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Check ingress events
kubectl describe ingress dawn-ingress -n dawn-ns
```

### Image pull errors

```bash
# Verify ECR repository exists
aws ecr describe-repositories --region us-east-1

# Check if nodes have ECR access (should be automatic with eksctl)
kubectl describe node | grep -A 5 "iam.amazonaws.com"
```

## Next Steps

- Add monitoring with Prometheus/Grafana
- Set up logging with Fluentd/CloudWatch
- Configure DNS with Route53
- Add SSL/TLS with ACM
- Implement CI/CD with GitHub Actions
- Add Pulumi for Infrastructure as Code

## Resources

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [eksctl Documentation](https://eksctl.io/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
