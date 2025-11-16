# Foundation - EKS Infrastructure Exploration

This project demonstrates deploying Python microservices (Dawn, Day, Dusk) to AWS EKS with production and RC tiers using a **decoupled architecture** where clusters are infrastructure and services are applications.

## Quick Start Options

### Option 1: Single Cluster (Trantor - hosts Dawn and Day) with Spot Instances - **RECOMMENDED**
- **Time:** ~40 minutes
- **Guide:** [first-deployment.md](first-deployment.md)
- **Method:** Manual scripts in `foundation/provisioning/manual/`

### Option 2: Infrastructure as Code with Pulumi (Terminus cluster)
- **Time:** ~30 minutes
- **Guide:** [../../02-infrastructure-as-code/pulumi-setup.md](../02-infrastructure-as-code/pulumi-setup.md)
- **Method:** Declarative Pulumi programs in `foundation/provisioning/pulumi/`

## Architecture

**Decoupled Design: Clusters ≠ Services**

- **2 EKS Clusters:**
  - **Trantor** - Hosts Dawn and Day services (manual provisioning)
  - **Terminus** - Reserved for future services (Pulumi-managed)

- **Multiple Services per Cluster:**
  - Trantor cluster runs both Dawn and Day services
  - Each service has its own namespaces (prod + RC)

- **Namespaces:**
  - dawn-ns, dawn-rc-ns (on Trantor)
  - day-ns, day-rc-ns (on Trantor)
  - Future: additional services on Terminus

Each service deployment includes:
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

# Build and push images to ECR
./build-and-push-dawn.sh us-east-1
./build-and-push-day.sh us-east-1

# Deploy services to Trantor cluster
./deploy-to-trantor.sh us-east-1
```

This:
- Creates ECR repositories for dawn and day
- Builds Docker images
- Deploys both services to trantor cluster with production configuration

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
│   │   └── Pulumi.terminus.yaml  # Terminus cluster config
│   └── manual/              # Manual cluster provisioning scripts (Trantor)
│       ├── create-trantor-cluster.sh
│       └── install-alb-controller-trantor.sh
├── gitops/
│   ├── pulumi_deploy/       # Application deployment (Pulumi) - Terminus
│   │   └── __main__.py      # Deployment, Service, HPA, etc.
│   └── manual_deploy/       # Manual deployment scripts - Trantor
│       ├── build-and-push-dawn.sh
│       ├── build-and-push-day.sh
│       └── deploy-to-trantor.sh
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

**⚠️ WARNING: This deletes the Trantor cluster and all resources!**

```bash
cd foundation/gitops/manual_deploy
./cleanup-trantor.sh us-east-1
```

This will:
- Delete Trantor EKS cluster
- Delete Trantor node group
- Delete ECR repositories (Dawn, Day)
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
