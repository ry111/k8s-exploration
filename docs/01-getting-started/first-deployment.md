# Your First Kubernetes Deployment on EKS

This hands-on guide walks you through deploying your first application to Amazon EKS (Elastic Kubernetes Service). By the end, you'll have a running microservice accessible via the internet, and you'll understand each component involved.

## 🎯 Learning Objectives

By completing this guide, you will:
- ✅ Create an EKS cluster with spot instances
- ✅ Deploy a containerized application to Kubernetes
- ✅ Expose your application via AWS Application Load Balancer
- ✅ Understand Deployments, Services, and Ingress resources
- ✅ Monitor and troubleshoot your deployment
- ✅ Explore Kubernetes objects interactively

**Estimated time:** 35-40 minutes

---

## Prerequisites

Before starting, ensure you have these tools installed:

```bash
# Verify tools are installed
aws --version      # AWS CLI
eksctl version     # eksctl (EKS cluster management tool)
kubectl version    # kubectl (Kubernetes CLI)
helm version       # Helm (Kubernetes package manager)
docker --version   # Docker

# Configure AWS credentials
aws configure

# Verify AWS access
aws sts get-caller-identity
```

> 📚 **Need help installing these tools?**
>
> See our prerequisites guide for installation instructions (coming soon).

---

## Deployment Steps

### Step 1: Create Your EKS Cluster (~15-20 minutes)

```bash
cd foundation/provisioning/manual

./create-trantor-cluster.sh us-east-1
```

This script creates:
- EKS cluster named `trantor`
- 2× t3.small spot instances (can scale 1-3)
- VPC with public/private subnets (10.0.0.0/16)
- All necessary IAM roles

**What's happening:**
- eksctl provisions the EKS control plane (managed by AWS)
- Kubernetes API server, scheduler, and controller manager start
- Spot nodes join the cluster
- You'll see real-time progress in your terminal

> 💡 **Learning Pattern: Spot Instances**
>
> We're using **spot instances** (up to 90% cheaper than on-demand) for this learning project.
> Spot instances can be interrupted with a 2-minute warning, which is acceptable for dev/learning.
>
> **For production:** Use a mix of on-demand and spot instances for better reliability.

**Verify your cluster is ready:**
```bash
kubectl get nodes

# Should show 2 nodes:
# NAME                           STATUS   ROLES    AGE
# ip-192-168-x-x.ec2.internal   Ready    <none>   2m
# ip-192-168-y-y.ec2.internal   Ready    <none>   2m
```

---

### Step 2: Install AWS Load Balancer Controller + Metrics Server (~5 minutes)

```bash
./install-alb-controller-trantor.sh us-east-1
```

This script installs two essential cluster components:

**AWS Load Balancer Controller:**
- Watches for Ingress resources in your cluster
- Provisions AWS ALBs automatically
- Configures routing rules
- Manages target groups pointing to your pods

**Metrics Server:**
- Collects resource metrics (CPU, memory) from nodes and pods
- Required for HorizontalPodAutoscaler (HPA) to function
- Enables `kubectl top nodes` and `kubectl top pods` commands

**Verify both are running:**
```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get deployment -n kube-system metrics-server

# Both should show READY status
```

---

### Step 3: Verify Images in ECR (~2 minutes)

This project uses **GitHub Actions** to automatically build and push Docker images to ECR when code is pushed to the repository. Images are already available if the GitHub Actions workflows have run.

**Check if images exist in ECR:**

```bash
# Get your AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Check for Dawn service images
aws ecr describe-images --repository-name dawn --region us-east-1 2>/dev/null || echo "Repository doesn't exist yet"

# Check for Day service images
aws ecr describe-images --repository-name day --region us-east-1 2>/dev/null || echo "Repository doesn't exist yet"
```

**If images don't exist yet:**

The GitHub Actions workflows will automatically create ECR repositories and build images when you push code changes. You can also trigger a manual build:

1. Go to your GitHub repository
2. Click **Actions** tab
3. Select **Build and Push Dawn Images** workflow
4. Click **Run workflow** → **Run workflow**
5. Wait ~2-3 minutes for the build to complete

**What GitHub Actions does:**
- Creates ECR repository if it doesn't exist
- Builds the Docker image from `foundation/services/dawn/`
- Pushes image with `:latest`, `:rc`, and `:<git-sha>` tags to ECR

> 💡 **Learning Pattern: CI/CD Image Builds**
>
> This project uses **GitHub Actions for automated image builds** instead of local Docker builds.
>
> **Benefits:**
> - No Docker required on your laptop
> - Consistent build environment
> - Automatic builds on every push
> - Images tagged with git SHA for version tracking
>
> **For local development:** If you need to build images locally for testing, you can use:
> ```bash
> cd foundation/services/dawn
> docker build -t dawn:local .
> ```
>
> See [GitHub Actions Setup](../04-cicd-automation/github-actions-setup.md) for details on the CI/CD pipeline.

---

### Step 4: Deploy Services (~5 minutes)

Deploy each service individually by specifying the target cluster:

```bash
# Deploy Dawn service to Trantor cluster
./deploy-dawn.sh trantor us-east-1

# Deploy Day service to Trantor cluster
./deploy-day.sh trantor us-east-1
```

**What gets deployed:**

**Dawn service (dawn-ns namespace):**
- Deployment: 2 pods with rolling updates
- Service (ClusterIP) for internal routing
- Ingress for external access via ALB
- ConfigMap for configuration
- HPA for auto-scaling (2-5 pods based on CPU/memory)

**Day service (day-ns namespace):**
- Deployment: 2 pods with rolling updates
- Service (ClusterIP) for internal routing
- Ingress for external access via ALB
- ConfigMap for configuration
- HPA for auto-scaling (2-5 pods based on CPU/memory)

> 💡 **Deployment Strategy**
>
> These scripts are **cluster-agnostic** - they can deploy to any cluster by name. The first argument explicitly specifies the target cluster, making it clear and safe. This demonstrates the separation between infrastructure (clusters) and applications (services).

**Verify your pods are running:**
```bash
kubectl get pods -n dawn-ns
kubectl get pods -n day-ns

# Should show running pods:
# NAME                    READY   STATUS    RESTARTS   AGE
# dawn-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
# dawn-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
```

---

### Step 5: Get Your Load Balancer URL (~2-3 minutes for ALB provisioning)

```bash
# Check production Ingress
kubectl get ingress dawn-ingress -n dawn-ns

# Check RC Ingress
kubectl get ingress dawn-rc-ingress -n dawn-rc-ns
```

**Note:** AWS takes 2-3 minutes to provision the ALB. Initially you'll see:
```
ADDRESS
<pending>
```

Wait a bit and check again. You'll see:
```
ADDRESS
k8s-dawnclus-dawningr-abc123-123456789.us-east-1.elb.amazonaws.com
```

---

### Step 6: Test Your Service

```bash
# Get the ALB URL
ALB_URL=$(kubectl get ingress dawn-ingress -n dawn-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test the endpoints
curl http://$ALB_URL/
curl http://$ALB_URL/health
curl http://$ALB_URL/info

# Example response:
# {
#   "service": "Dawn",
#   "message": "Welcome to the Dawn service",
#   "version": "1.0.0"
# }
```

🎉 **Congratulations!** You've deployed your first application to Kubernetes!

---

## Complete Workflow (Copy-Paste)

For reference, here's the complete deployment sequence:

```bash
cd foundation/provisioning/manual

# 1. Create cluster (~20 min)
./create-trantor-cluster.sh us-east-1

# 2. Install ALB controller (~5 min)
./install-alb-controller-trantor.sh us-east-1

# 3. Verify images in ECR (~2 min)
# Images are built automatically by GitHub Actions
# Trigger manual build if needed: GitHub repo → Actions → Run workflow
aws ecr describe-images --repository-name dawn --region us-east-1
aws ecr describe-images --repository-name day --region us-east-1

# 4. Deploy services (~5 min)
cd ../../gitops/manual_deploy
./deploy-dawn.sh trantor us-east-1
./deploy-day.sh trantor us-east-1

# 5. Wait for ALB to be ready (~2-3 min)
watch kubectl get ingress -n dawn-ns

# 6. Test (once ADDRESS is populated)
curl http://$(kubectl get ingress dawn-ingress -n dawn-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/health
```

**Total time:** ~35-40 minutes

---

## 🔍 Explore What You Built

Now that your application is running, let's explore the Kubernetes objects that make it work!

### Cluster Architecture

After deployment, here's what's running:

```
trantor (EKS Cluster)
├── Control Plane (Managed by AWS)
│   ├── API Server
│   ├── etcd (cluster state)
│   ├── Scheduler
│   └── Controller Manager
│
├── Worker Nodes
│   ├── Node 1: ip-192-168-x-x.ec2.internal (t3.small spot)
│   └── Node 2: ip-192-168-y-y.ec2.internal (t3.small spot)
│
├── dawn-ns namespace (Production)
│   ├── Deployment: dawn (manages ReplicaSet)
│   │   └── ReplicaSet: dawn-xxxxxxxxx (manages Pods)
│   │       ├── Pod: dawn-xxxxxxxxxx-xxxxx
│   │       └── Pod: dawn-xxxxxxxxxx-xxxxx
│   ├── Service: dawn-service (ClusterIP - internal routing)
│   ├── Ingress: dawn-ingress (creates ALB for external access)
│   ├── ConfigMap: dawn-config (environment variables)
│   └── HPA: dawn-hpa (auto-scaling 2-5 pods)
│
└── dawn-rc-ns namespace (RC)
    ├── Deployment: dawn-rc
    │   └── ReplicaSet: dawn-rc-xxxxxxxxx
    │       └── Pod: dawn-rc-xxxxxxxxxx-xxxxx
    ├── Service: dawn-rc-service
    ├── Ingress: dawn-rc-ingress (shares same ALB)
    ├── ConfigMap: dawn-rc-config
    └── HPA: dawn-rc-hpa (auto-scaling 1-3 pods)
```

> 💡 **Learning Pattern: One Cluster Per Service**
>
> This project creates **separate clusters** for each service (dawn, day, dusk).
>
> **Why we do this for learning:**
> - Clear isolation helps understand cluster boundaries
> - Easier to experiment and clean up
> - See the full cluster creation process
>
> **Production pattern:** Run multiple services in one cluster using **namespaces**:
> ```
> shared-prod-cluster
> ├── dawn-ns (namespace)
> ├── day-ns (namespace)
> └── dusk-ns (namespace)
> ```
> This is more cost-effective (fewer control planes) and better resource utilization.
>
> See `07-next-steps/learning-vs-production.md` for migration guidance.

### Interactive Exploration Scripts

This project includes scripts to help you visualize and understand Kubernetes internals:

```bash
cd foundation/scripts/explore

# See how Deployments → ReplicaSets → Pods work
./explore-deployment-hierarchy.sh

# Understand ConfigMap to Pod relationships
./explore-configmap-relationships.sh

# Watch rolling updates in action
./explore-rolling-updates.sh
```

These scripts show you exactly how Kubernetes manages your application!

---

## Monitoring Your Deployment

### Check Cluster Resources

```bash
# Get all pods across all namespaces
kubectl get pods --all-namespaces

# Check node resource usage
kubectl top nodes

# Check pod resource usage
kubectl top pods -n dawn-ns
```

### View Logs

```bash
# Production logs
kubectl logs -n dawn-ns deployment/dawn

# RC logs
kubectl logs -n dawn-rc-ns deployment/dawn-rc

# Follow logs in real-time
kubectl logs -n dawn-ns deployment/dawn -f

# View logs from a specific pod
kubectl logs -n dawn-ns <pod-name>
```

### Check Auto-Scaling

```bash
# View HPA status
kubectl get hpa -n dawn-ns
kubectl get hpa -n dawn-rc-ns

# Example output:
# NAME        REFERENCE         TARGETS   MINPODS   MAXPODS   REPLICAS
# dawn-hpa    Deployment/dawn   15%/70%   2         5         2
```

The HPA (HorizontalPodAutoscaler) automatically scales pods based on CPU/memory usage.

---

## Troubleshooting

### Pods Not Starting

```bash
# Describe the pod to see events
kubectl describe pod -n dawn-ns <pod-name>

# Check pod logs
kubectl logs -n dawn-ns <pod-name>
```

**Common issues:**
- **ImagePullBackOff:** Image not pushed to ECR or wrong URL
- **CrashLoopBackOff:** Application error, check logs
- **Pending:** Not enough resources on nodes

### Ingress Not Creating ALB

```bash
# Check Ingress details
kubectl describe ingress dawn-ingress -n dawn-ns

# Check ALB controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

**Common issues:**
- ALB controller not running
- Missing IAM permissions
- Takes 2-3 minutes to provision (be patient!)

### Spot Instance Interruptions

Spot instances can be terminated with a 2-minute warning. When this happens:
1. Kubernetes automatically reschedules pods to other nodes
2. If you have multiple replicas, your service remains available
3. New nodes may be provisioned if needed

Check for spot interruptions:
```bash
kubectl get events --all-namespaces | grep -i spot
```

> 📚 **More help needed?**
>
> See `06-troubleshooting/common-issues.md` for detailed troubleshooting guides.

---

## Cleanup

When you're done experimenting, clean up all resources:

**⚠️ WARNING: This deletes everything!**

Cleanup follows the separation of concerns - infrastructure and applications are deleted separately:

**Step 1: Delete application images (optional)**
```bash
cd foundation/gitops/manual_deploy

# Delete Dawn service images
./delete-service-images.sh dawn us-east-1

# Delete Day service images
./delete-service-images.sh day us-east-1
```

**Step 2: Delete infrastructure**
```bash
cd ../../provisioning/manual

# Delete the Trantor cluster
./delete-cluster.sh trantor us-east-1
```

This approach:
- **Application cleanup** (delete-service-images.sh): Deletes ECR repositories and container images
- **Infrastructure cleanup** (delete-cluster.sh): Deletes EKS cluster, nodes, ALBs, and IAM roles
- Each script requires typing `DELETE` to confirm

You can delete the cluster without deleting ECR images (to redeploy later) or vice versa.

---

## ✅ What You Learned

Congratulations! You've successfully:

- [x] Created an EKS cluster with eksctl
- [x] Deployed a containerized application using kubectl
- [x] Exposed your application via Ingress and ALB
- [x] Understood Kubernetes core resources:
  - **Deployments** - Declare desired state for your application
  - **ReplicaSets** - Ensure the right number of pods are running
  - **Pods** - The smallest deployable units (containers)
  - **Services** - Internal networking and load balancing
  - **Ingress** - External access via load balancers
  - **ConfigMaps** - Configuration management
  - **HPA** - Automatic scaling based on metrics
- [x] Monitored your deployment with kubectl
- [x] Explored Kubernetes architecture hands-on

**Key concepts mastered:**
- EKS managed Kubernetes control plane
- Spot instances for cost savings
- Container image management with ECR
- Declarative infrastructure (YAML manifests)
- Zero-downtime deployments with rolling updates
- Health checks and auto-healing

---

## 🚀 Next Steps

### Deepen Your Understanding

1. **Learn Kubernetes Internals**
   - [Deployment Hierarchy](../05-kubernetes-deep-dives/deployment-hierarchy.md) - How Deployments create Pods
   - [ConfigMap Relationships](../05-kubernetes-deep-dives/configmap-relationships.md) - Configuration management patterns
   - [Rolling Updates](../05-kubernetes-deep-dives/rolling-updates.md) - Zero-downtime deployment mechanics

2. **Automate with Infrastructure as Code**
   - [Why Infrastructure as Code?](../02-infrastructure-as-code/why-infrastructure-as-code.md)
   - [Pulumi Setup](../02-infrastructure-as-code/pulumi-setup.md) - Manage infrastructure with Python
   - [Deploy with Pulumi](../02-infrastructure-as-code/deploy-with-pulumi.md) - The Day cluster example

3. **Add CI/CD**
   - [GitHub Actions Setup](../04-cicd-automation/github-actions-setup.md) - Automate builds and deployments

### Explore Further

- **Kubernetes Fundamentals:** [kubernetes-101.md](./kubernetes-101.md) - Deep dive into K8s architecture
- **Project Overview:** [overview.md](./overview.md) - Understand the full project structure
- **Production Patterns:** [learning-vs-production.md](../07-next-steps/learning-vs-production.md) - What changes for production

---

## Resources

- [eksctl Documentation](https://eksctl.io/) - EKS cluster management tool
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/) - Production guidance
- [Spot Instance Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Kubernetes Documentation](https://kubernetes.io/docs/) - Official K8s docs

---

**Questions or issues?** Check our [troubleshooting guide](../06-troubleshooting/common-issues.md) or explore the [deep dive docs](../05-kubernetes-deep-dives/).
