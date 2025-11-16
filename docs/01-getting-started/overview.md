# Foundation - EKS Infrastructure Exploration

This project demonstrates deploying Python microservices (Dawn, Day, Dusk) to AWS EKS with production and RC tiers.

## Quick Start Options

### Option 1: Single Cluster (Dawn only) with Spot Instances - **RECOMMENDED FOR LEARNING**
- **Time:** ~40 minutes
- **Guide:** [first-deployment.md](first-deployment.md)

### Option 2: All Three Clusters with On-Demand Instances
- **Time:** ~90 minutes
- **Guide:** See "Deployment Steps" below

## Architecture

- **3 EKS Clusters** (one per service)
- **6 Namespaces** (prod + RC per cluster)
- **6 Deployments** (2 per cluster)
- **3 Application Load Balancers** (one per cluster, shared via IngressGroup)

Each cluster runs:
- Production deployment (2-5 replicas)
- RC deployment (1-3 replicas)

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

## Deployment Steps

### 1. Create EKS Clusters (~45-60 minutes)

```bash
cd foundation/scripts

# Make scripts executable
chmod +x *.sh

# Create all 3 clusters
./1-create-clusters.sh us-east-1
```

This creates:
- `dawn-cluster` with 2 t3.small nodes
- `day-cluster` with 2 t3.small nodes
- `dusk-cluster` with 2 t3.small nodes

### 2. Install AWS Load Balancer Controller (~15 minutes)

```bash
./2-install-alb-controller.sh us-east-1
```

This installs the ALB Ingress Controller on all clusters to enable Ingress resources.

### 3. Build and Push Docker Images (~10 minutes)

```bash
./3-build-and-push-images.sh us-east-1
```

This:
- Creates ECR repositories for dawn, day, dusk
- Builds Docker images for each service
- Pushes `:latest` and `:rc` tags to ECR

### 4. Update Deployment Manifests

```bash
./4-update-deployment-images.sh us-east-1
```

This updates K8s deployment files to use ECR image URLs instead of local images.

### 5. Deploy Services (~10 minutes)

```bash
./5-deploy-to-clusters.sh us-east-1
```

This deploys both production and RC tiers to each cluster.

## Verification

### Check Cluster Status

```bash
# List all clusters
eksctl get cluster --region us-east-1

# Get nodes for each cluster
kubectl get nodes --context dawn-cluster
kubectl get nodes --context day-cluster
kubectl get nodes --context dusk-cluster
```

### Check Deployments

```bash
# Set context to a cluster
aws eks update-kubeconfig --name dawn-cluster --region us-east-1

# View all resources in production namespace
kubectl get all -n dawn-ns

# View all resources in RC namespace
kubectl get all -n dawn-rc-ns
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
├── infrastructure/
│   └── pulumi/       # Infrastructure as Code (Pulumi)
│       ├── __main__.py      # EKS cluster, VPC, nodes
│       ├── Pulumi.day.yaml  # Day cluster config
│       └── Pulumi.dusk.yaml # Dusk cluster config
├── gitops/
│   └── day/          # Application resources (Pulumi)
│       └── __main__.py  # Deployment, Service, HPA, etc.
├── services/         # Python Flask applications
│   ├── dawn/
│   ├── day/
│   └── dusk/
├── k8s/              # Kubernetes manifests
│   ├── dawn/         # Production manifests
│   ├── dawn-rc/      # RC manifests
│   ├── day/
│   ├── day-rc/
│   ├── dusk/
│   └── dusk-rc/
└── scripts/          # Deployment automation
    ├── explore/      # Interactive learning scripts
    │   ├── explore-deployment-hierarchy.sh
    │   ├── explore-configmap-relationships.sh
    │   └── explore-rolling-updates.sh
    ├── Dawn-only (Spot Instances):
    │   ├── create-dawn-cluster.sh
    │   ├── install-alb-controller-dawn.sh
    │   ├── build-and-push-dawn.sh
    │   ├── deploy-dawn.sh
    │   └── cleanup-dawn.sh
    └── All 3 Clusters (On-Demand):
        ├── 1-create-clusters.sh
        ├── 2-install-alb-controller.sh
        ├── 3-build-and-push-images.sh
        ├── 4-update-deployment-images.sh
        ├── 5-deploy-to-clusters.sh
        └── cleanup.sh
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

**⚠️ WARNING: This deletes everything!**

```bash
./cleanup.sh us-east-1
```

This will:
- Delete all 3 EKS clusters
- Delete all node groups
- Delete ECR repositories
- Clean up associated AWS resources

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
