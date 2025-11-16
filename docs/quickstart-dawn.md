# Quick Start: Deploy Dawn Service to EKS with Spot Instances

This guide walks you through deploying just the Dawn service to a single EKS cluster using **spot instances**.

**Note:** Spot instances can be interrupted with 2-minute warning. For learning/dev environments, this is acceptable.

## Prerequisites

```bash
# Verify tools are installed
aws --version      # AWS CLI
eksctl version     # eksctl
kubectl version    # kubectl
helm version       # Helm
docker --version   # Docker

# Configure AWS credentials
aws configure

# Verify AWS access
aws sts get-caller-identity
```

## Deployment Steps

### 1. Create Dawn Cluster (~15-20 minutes)

```bash
cd foundation/scripts

./create-dawn-cluster.sh us-east-1
```

This creates:
- EKS cluster named `dawn-cluster`
- 2× t3.small spot instances (can scale 1-3)
- VPC with public/private subnets
- All necessary IAM roles

**What's happening:**
- eksctl provisions the cluster
- Kubernetes control plane starts
- Spot nodes join the cluster
- You'll see real-time progress

**Verify:**
```bash
kubectl get nodes

# Should show 2 nodes:
# NAME                           STATUS   ROLES    AGE
# ip-192-168-x-x.ec2.internal   Ready    <none>   2m
# ip-192-168-y-y.ec2.internal   Ready    <none>   2m
```

### 2. Install AWS Load Balancer Controller (~5 minutes)

```bash
./install-alb-controller-dawn.sh us-east-1
```

This installs the controller that creates AWS ALBs from Ingress resources.

**Verify:**
```bash
kubectl get deployment -n kube-system aws-load-balancer-controller

# Should show:
# NAME                           READY   UP-TO-DATE   AVAILABLE
# aws-load-balancer-controller   2/2     2            2
```

### 3. Build and Push Docker Images (~5 minutes)

```bash
./build-and-push-dawn.sh us-east-1
```

This:
- Creates ECR repository
- Builds Dawn Docker image
- Pushes `:latest` and `:rc` tags to ECR

**What you'll see:**
```
Step 1/8 : FROM python:3.11-slim
Step 2/8 : WORKDIR /app
...
✓ Pushed dawn:latest
✓ Pushed dawn:rc
```

### 4. Deploy Dawn Services (~5 minutes)

```bash
./deploy-dawn.sh us-east-1
```

This deploys:
- Production tier (dawn-ns namespace) - 2 pods
- RC tier (dawn-rc-ns namespace) - 1 pod
- Services and Ingress resources

**Verify:**
```bash
kubectl get pods -n dawn-ns
kubectl get pods -n dawn-rc-ns

# Should show running pods:
# NAME                    READY   STATUS    RESTARTS   AGE
# dawn-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
# dawn-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
```

### 5. Get Load Balancer URL (~2-3 minutes for ALB to provision)

```bash
# Production ALB
kubectl get ingress dawn-ingress -n dawn-ns

# RC ALB
kubectl get ingress dawn-rc-ingress -n dawn-rc-ns
```

**Note:** It takes 2-3 minutes for AWS to provision the ALB. Initially you'll see:
```
ADDRESS
<pending>
```

Wait a bit, then check again. You'll see:
```
ADDRESS
k8s-dawnclus-dawningr-abc123-123456789.us-east-1.elb.amazonaws.com
```

### 6. Test Your Services

```bash
# Get ALB URL
ALB_URL=$(kubectl get ingress dawn-ingress -n dawn-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test production endpoints
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

## Complete Workflow (Copy-Paste)

```bash
cd foundation/scripts

# 1. Create cluster (~20 min)
./create-dawn-cluster.sh us-east-1

# 2. Install ALB controller (~5 min)
./install-alb-controller-dawn.sh us-east-1

# 3. Build and push images (~5 min)
./build-and-push-dawn.sh us-east-1

# 4. Deploy services (~5 min)
./deploy-dawn.sh us-east-1

# 5. Wait for ALB to be ready (~2-3 min)
watch kubectl get ingress -n dawn-ns

# 6. Test (once ADDRESS is populated)
curl http://$(kubectl get ingress dawn-ingress -n dawn-ns -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/health
```

**Total time:** ~35-40 minutes

## What's Running?

After deployment, you have:

### Dawn Cluster
```
dawn-cluster (EKS)
├── 2× t3.small spot nodes
│
├── dawn-ns namespace (Production)
│   ├── 2 dawn pods (can scale to 5)
│   ├── dawn-service (ClusterIP)
│   └── dawn-ingress (ALB)
│
└── dawn-rc-ns namespace (RC)
    ├── 1 dawn-rc pod (can scale to 3)
    ├── dawn-rc-service (ClusterIP)
    └── dawn-rc-ingress (shares same ALB)
```

### Ingress Routing
Both ingresses share one ALB (via `group.name: dawn-cluster`):
- `dawn.example.com` → dawn-service (prod)
- `dawn-rc.example.com` → dawn-rc-service (RC)

For now, use the ALB URL directly. Later you can point custom domains to the ALB.

## Monitoring

### Check cluster resources
```bash
# Get all pods
kubectl get pods --all-namespaces

# Check node resource usage
kubectl top nodes

# Check pod resource usage
kubectl top pods -n dawn-ns
```

### Check logs
```bash
# Production logs
kubectl logs -n dawn-ns deployment/dawn

# RC logs
kubectl logs -n dawn-rc-ns deployment/dawn-rc

# Follow logs in real-time
kubectl logs -n dawn-ns deployment/dawn -f
```

### Check autoscaling
```bash
# View HPA status
kubectl get hpa -n dawn-ns
kubectl get hpa -n dawn-rc-ns

# Example output:
# NAME        REFERENCE         TARGETS   MINPODS   MAXPODS   REPLICAS
# dawn-hpa    Deployment/dawn   15%/70%   2         5         2
```

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod -n dawn-ns <pod-name>
kubectl logs -n dawn-ns <pod-name>
```

Common issues:
- **ImagePullBackOff:** Image not pushed to ECR or wrong URL
- **CrashLoopBackOff:** Application error, check logs

### Ingress not creating ALB
```bash
kubectl describe ingress dawn-ingress -n dawn-ns
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

Common issues:
- ALB controller not running
- Missing IAM permissions
- Takes 2-3 minutes to provision

### Spot instance interrupted
Spot instances can be terminated with 2-minute warning. When this happens:
1. Kubernetes automatically reschedules pods to other nodes
2. If cluster autoscaler is running, new nodes may be provisioned
3. Your services remain available (if you have multiple pods)

Check for spot interruptions:
```bash
kubectl get events --all-namespaces | grep -i spot
```

## Cleanup

**⚠️ WARNING: This deletes everything!**

```bash
./cleanup-dawn.sh us-east-1
```

This will:
- Delete the EKS cluster
- Delete all nodes
- Delete ECR repository and images
- Delete ALBs
- Remove IAM roles

You'll need to type `DELETE` to confirm.

## Next Steps

- **Add Day and Dusk clusters:** Use the multi-cluster scripts
- **Set up monitoring:** Prometheus + Grafana
- **Add CI/CD:** GitHub Actions to auto-deploy on push
- **Custom domains:** Point your domains to ALB with Route53
- **SSL/TLS:** Add HTTPS with ACM (AWS Certificate Manager)
- **Pulumi:** Automate this with Infrastructure as Code

## Resources

- [eksctl Documentation](https://eksctl.io/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Spot Instance Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
