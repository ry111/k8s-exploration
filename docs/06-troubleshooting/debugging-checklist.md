# Kubernetes Debugging Checklist

A quick reference guide for debugging Kubernetes issues. Follow this systematic approach when something goes wrong.

---

## Quick Diagnostic Flow

```
Problem Detected
      ↓
Is the cluster accessible? → No → Check kubeconfig, AWS credentials
      ↓ Yes
Are pods running? → No → Check pod status (Pending, ImagePullBackOff, CrashLoopBackOff)
      ↓ Yes
Is the service accessible internally? → No → Check Service, endpoints
      ↓ Yes
Is the service accessible externally? → No → Check Ingress, ALB
      ↓ Yes
Application not working correctly? → Check logs, events, environment variables
```

---

## Essential kubectl Commands

### Check Overall Status

```bash
# Get all resources in a namespace
kubectl get all -n <namespace>

# Get all resources across all namespaces
kubectl get all --all-namespaces

# Check cluster nodes
kubectl get nodes

# Check node resource usage (requires metrics-server)
kubectl top nodes
```

### Check Pods

```bash
# List pods
kubectl get pods -n <namespace>

# Detailed pod information
kubectl describe pod <pod-name> -n <namespace>

# Get pod logs
kubectl logs <pod-name> -n <namespace>

# Get logs from previous container (if pod restarted)
kubectl logs <pod-name> -n <namespace> --previous

# Follow logs in real-time
kubectl logs <pod-name> -n <namespace> -f

# Get logs from all pods in a deployment
kubectl logs -n <namespace> deployment/<deployment-name> --all-containers=true

# Execute command in pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash
kubectl exec -it <pod-name> -n <namespace> -- sh  # if bash not available

# Check pod resource usage
kubectl top pods -n <namespace>
```

### Check Deployments

```bash
# List deployments
kubectl get deployments -n <namespace>

# Describe deployment
kubectl describe deployment <deployment-name> -n <namespace>

# Check deployment rollout status
kubectl rollout status deployment/<deployment-name> -n <namespace>

# View deployment history
kubectl rollout history deployment/<deployment-name> -n <namespace>

# Get deployment YAML
kubectl get deployment <deployment-name> -n <namespace> -o yaml
```

### Check Services and Networking

```bash
# List services
kubectl get services -n <namespace>

# Describe service
kubectl describe service <service-name> -n <namespace>

# Check service endpoints (actual pods behind the service)
kubectl get endpoints <service-name> -n <namespace>

# List ingresses
kubectl get ingress -n <namespace>

# Describe ingress
kubectl describe ingress <ingress-name> -n <namespace>
```

### Check ConfigMaps and Secrets

```bash
# List ConfigMaps
kubectl get configmap -n <namespace>

# View ConfigMap data
kubectl describe configmap <configmap-name> -n <namespace>
kubectl get configmap <configmap-name> -n <namespace> -o yaml

# List Secrets
kubectl get secrets -n <namespace>

# View Secret (values are base64 encoded)
kubectl get secret <secret-name> -n <namespace> -o yaml
```

### Check Events

```bash
# Get all events in namespace (sorted by time)
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Watch events in real-time
kubectl get events -n <namespace> --watch

# Get events for specific resource
kubectl describe <resource-type> <resource-name> -n <namespace>
```

### Check Auto-Scaling

```bash
# List Horizontal Pod Autoscalers
kubectl get hpa -n <namespace>

# Describe HPA
kubectl describe hpa <hpa-name> -n <namespace>

# Get HPA in watch mode to see live updates
watch kubectl get hpa -n <namespace>
```

---

## Common Pod Status Meanings

| Status | Meaning | Common Causes |
|--------|---------|---------------|
| `Pending` | Pod accepted but not running yet | Not enough resources, scheduling issues |
| `Running` | Pod is running | Normal state |
| `Succeeded` | Pod completed successfully | Job or one-time task finished |
| `Failed` | Pod terminated with error | Application crash, config error |
| `Unknown` | Can't determine pod state | Node communication issue |
| `ImagePullBackOff` | Can't pull container image | Wrong image URL, auth issue, image doesn't exist |
| `CrashLoopBackOff` | Container keeps crashing | Application error, missing dependencies |
| `ContainerCreating` | Container is being created | Normal during startup, or stuck on volume mount |
| `Terminating` | Pod is being deleted | Normal during shutdown, or stuck |

---

## Pod Troubleshooting Workflow

### Step 1: Check Pod Status

```bash
kubectl get pods -n <namespace>

# Look at STATUS column
```

### Step 2: Describe the Pod

```bash
kubectl describe pod <pod-name> -n <namespace>

# Check these sections:
# - Events (at the bottom) - shows what happened
# - Containers - shows container statuses
# - Conditions - shows pod readiness
```

### Step 3: Check Logs

```bash
# Current logs
kubectl logs <pod-name> -n <namespace>

# If pod restarted, check previous logs
kubectl logs <pod-name> -n <namespace> --previous

# If multiple containers in pod
kubectl logs <pod-name> -n <namespace> -c <container-name>
```

### Step 4: Check Resource Allocation

```bash
# See if pod has enough resources
kubectl top pod <pod-name> -n <namespace>

# Check node resources
kubectl describe node <node-name>
```

---

## Service Troubleshooting Workflow

### Step 1: Check Service Exists

```bash
kubectl get service <service-name> -n <namespace>
```

### Step 2: Check Service Endpoints

```bash
# Endpoints should list pod IPs
kubectl get endpoints <service-name> -n <namespace>

# If empty, no pods match the service selector
```

### Step 3: Verify Selector Matches Pods

```bash
# Get service selector
kubectl get service <service-name> -n <namespace> -o jsonpath='{.spec.selector}'

# Check if pods have matching labels
kubectl get pods -n <namespace> --show-labels
```

### Step 4: Test Service Internally

```bash
# Create a test pod
kubectl run test-pod --image=busybox:1.28 --rm -it --restart=Never -- sh

# From inside the pod, test the service
wget -qO- http://<service-name>.<namespace>.svc.cluster.local
```

---

## Ingress/ALB Troubleshooting Workflow

### Step 1: Check Ingress Status

```bash
kubectl get ingress -n <namespace>

# Look for ADDRESS - should show ALB hostname (not <pending>)
```

### Step 2: Describe Ingress

```bash
kubectl describe ingress <ingress-name> -n <namespace>

# Check Events for errors
```

### Step 3: Check ALB Controller

```bash
# Verify controller is running
kubectl get deployment -n kube-system aws-load-balancer-controller

# Check controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

### Step 4: Check AWS

```bash
# List load balancers
aws elbv2 describe-load-balancers --region us-east-1

# Check target groups
aws elbv2 describe-target-groups --region us-east-1

# Check target health
aws elbv2 describe-target-health --target-group-arn <arn> --region us-east-1
```

---

## Common Fixes

### Restart a Deployment

```bash
kubectl rollout restart deployment/<deployment-name> -n <namespace>
```

### Force Pod Deletion

```bash
# If pod stuck in Terminating
kubectl delete pod <pod-name> -n <namespace> --grace-period=0 --force
```

### Update Image

```bash
kubectl set image deployment/<deployment-name> <container-name>=<new-image> -n <namespace>
```

### Scale Deployment

```bash
# Scale to specific number
kubectl scale deployment/<deployment-name> --replicas=3 -n <namespace>

# Scale to zero (stop all pods)
kubectl scale deployment/<deployment-name> --replicas=0 -n <namespace>
```

### Edit Resource

```bash
# Edit in your default editor
kubectl edit deployment/<deployment-name> -n <namespace>
```

### Apply Updated YAML

```bash
kubectl apply -f deployment.yaml
```

---

## AWS/EKS Specific Commands

### Update Kubeconfig

```bash
aws eks update-kubeconfig --name <cluster-name> --region us-east-1
```

### Verify AWS Credentials

```bash
aws sts get-caller-identity
```

### Check EKS Cluster

```bash
# Describe cluster
aws eks describe-cluster --name <cluster-name> --region us-east-1

# List clusters
aws eks list-clusters --region us-east-1
```

### Check ECR Images

```bash
# List images in repository
aws ecr list-images --repository-name <repo-name> --region us-east-1

# Describe images
aws ecr describe-images --repository-name <repo-name> --region us-east-1
```

---

## Useful Shortcuts and Aliases

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
# kubectl aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get services'
alias kgd='kubectl get deployments'
alias kgi='kubectl get ingress'
alias kdp='kubectl describe pod'
alias kl='kubectl logs'
alias kex='kubectl exec -it'

# Namespace shortcuts
alias kn='kubectl config set-context --current --namespace'

# Watch commands
alias watchpods='watch kubectl get pods'
alias watchnodes='watch kubectl get nodes'
```

---

## Debugging Tools to Install

### In Your Cluster

```bash
# Deploy a debug pod
kubectl run debug --image=busybox:1.28 --rm -it --restart=Never -- sh

# Or deploy a more feature-rich debug pod
kubectl run debug --image=nicolaka/netshoot --rm -it --restart=Never -- bash
```

### On Your Local Machine

```bash
# k9s - Terminal UI for Kubernetes
brew install k9s  # macOS
# Then run: k9s

# kubectx - Switch between clusters
brew install kubectx

# kubens - Switch between namespaces
brew install kubens

# stern - Tail logs from multiple pods
brew install stern
stern <pod-name-pattern> -n <namespace>
```

---

## When All Else Fails

1. **Check the logs** - 90% of issues are in the logs
2. **Describe everything** - Events often have clues
3. **Simplify** - Remove features until it works, then add back
4. **Compare with working example** - What's different?
5. **Start fresh** - Delete and recreate
6. **Search the error** - Google the exact error message
7. **Ask for help** - Provide logs, describe what you tried

---

## Additional Resources

- **Detailed Troubleshooting:** [common-issues.md](./common-issues.md)
- **Kubernetes Docs:** [Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/)
- **AWS EKS:** [Troubleshooting Guide](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
