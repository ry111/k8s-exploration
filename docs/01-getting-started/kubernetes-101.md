# Kubernetes Fundamentals: Architecture and Core Concepts

A comprehensive guide to understanding Kubernetes architecture, from containers to cloud providers.

## Table of Contents
- [What is Kubernetes?](#what-is-kubernetes)
- [Core Concepts](#core-concepts)
- [Cluster Architecture](#cluster-architecture)
- [Control Plane Components](#control-plane-components)
- [Node Components](#node-components)
- [Layered Architecture](#layered-architecture)
- [Cloud Provider Integration](#cloud-provider-integration)
- [EKS: Managed Kubernetes on AWS](#eks-managed-kubernetes-on-aws)
- [How It All Works Together](#how-it-all-works-together)
- [Real-World Example from This Project](#real-world-example-from-this-project)

---

## What is Kubernetes?

**Kubernetes (K8s)** is an open-source container orchestration platform that automates deployment, scaling, and management of containerized applications.

### The Problem Kubernetes Solves

**Without Kubernetes:**
```
Developer → Manual deployment on servers
           → Manual scaling when traffic increases
           → Manual recovery when containers crash
           → Manual load balancing
           → Manual updates (downtime required)
```

**With Kubernetes:**
```
Developer → Declare desired state (YAML)
           → K8s automatically deploys containers
           → K8s automatically scales based on load
           → K8s automatically restarts failed containers
           → K8s automatically load balances traffic
           → K8s performs rolling updates (zero downtime)
```

### Key Philosophy

Kubernetes uses a **declarative model**:
- **You declare** what you want (desired state)
- **Kubernetes ensures** that's what you get (actual state)
- **Control loops** constantly reconcile desired vs actual

```
Desired State (YAML) → K8s Controllers → Actual State (Running Pods)
         ↑                                        ↓
         └────────── Reconciliation Loop ────────┘
```

---

## Core Concepts

### 1. Containers

**What:** Lightweight, standalone packages containing application code and dependencies.

**Example:**
```dockerfile
# Docker container for our Day service
FROM python:3.11-slim
COPY app.py /app/
RUN pip install flask
CMD ["python", "/app/app.py"]
```

**Kubernetes manages containers, but doesn't run them directly.**

### 2. Pods

**The smallest deployable unit in Kubernetes.** A Pod wraps one or more containers.

```
┌─────────────────────────────┐
│ Pod: day-7d4f9c8b5f-abc12   │
│                             │
│  ┌───────────────────────┐  │
│  │ Container: day        │  │
│  │ Image: day:v1.2.3     │  │
│  │ Port: 8001            │  │
│  └───────────────────────┘  │
│                             │
│  IP: 10.0.1.45              │
│  Status: Running            │
└─────────────────────────────┘
```

**Why Pods, not just containers?**
- Pods share network namespace (localhost communication)
- Pods share storage volumes
- Pods are scheduled together on same node
- Pods are the unit of scaling

**Common pattern:** 1 Pod = 1 main container (+ optional sidecar containers)

### 3. Deployments

**Manages the lifecycle of Pods.** Handles scaling, updates, and rollbacks.

```
Deployment: day-service (desired: 3 replicas)
    ↓ creates
ReplicaSet: day-7d4f9c8b5f (actual: 3 replicas)
    ↓ creates
Pods:
    - day-7d4f9c8b5f-abc12 (Running)
    - day-7d4f9c8b5f-def34 (Running)
    - day-7d4f9c8b5f-ghi56 (Running)
```

**What Deployments provide:**
- ✅ Declarative updates (change image → rolling update)
- ✅ Scaling (change replicas: 3 → 10)
- ✅ Rollback (revert to previous version)
- ✅ Self-healing (pod crashes → automatically replaced)

See [deployment-hierarchy.md](deployment-hierarchy.md) for deep dive.

### 4. Services

**Stable network endpoint** for accessing Pods.

**Problem:** Pods have dynamic IPs that change when they're recreated.

**Solution:** Services provide a stable IP/DNS name.

```
┌──────────────────────────────────┐
│ Service: day-service             │
│ Type: ClusterIP                  │
│ IP: 10.100.200.50 (stable!)      │
│ DNS: day-service.production.svc  │
└─────────────┬────────────────────┘
              │ routes traffic to
              ↓
    ┌─────────┴─────────┐
    ↓                   ↓
Pod: 10.0.1.45      Pod: 10.0.1.67
(day-abc12)         (day-def34)
```

**Service types:**
- **ClusterIP** - Internal-only (default)
- **NodePort** - Exposes on each node's IP
- **LoadBalancer** - Cloud load balancer (AWS ALB/NLB)

### 5. Namespaces

**Virtual clusters** within a physical cluster.

```
Cluster: day-cluster
├── Namespace: production
│   ├── Deployment: day-service
│   ├── Service: day-service
│   └── ConfigMap: day-config
├── Namespace: dev
│   ├── Deployment: day-service (different version)
│   ├── Service: day-service
│   └── ConfigMap: day-config (different settings)
└── Namespace: kube-system
    ├── CoreDNS
    ├── ALB Controller
    └── Metrics Server
```

**Why namespaces?**
- Resource isolation
- Access control (RBAC per namespace)
- Resource quotas
- Logical separation (teams, environments)

### 6. ConfigMaps and Secrets

**ConfigMaps** - Store non-sensitive configuration
**Secrets** - Store sensitive data (base64 encoded)

```yaml
# ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: day-config
data:
  LOG_LEVEL: "info"
  PORT: "8001"
---
# Secret
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque
data:
  username: YWRtaW4=  # base64 encoded
  password: cGFzc3dvcmQ=
```

**How Pods use them:**
- Environment variables
- Mounted as files

See [configmap-relationships.md](configmap-relationships.md) for details.

### 7. Ingress

**HTTP/HTTPS routing** to Services.

```
                   Internet
                      ↓
              ┌───────────────┐
              │ AWS ALB       │ ← Created by Ingress Controller
              └───────┬───────┘
                      ↓
              ┌───────────────┐
              │ Ingress       │ ← Kubernetes resource
              │ Rules:        │
              │ - /api → api  │
              │ - /web → web  │
              └───────┬───────┘
                      ↓
         ┌────────────┴────────────┐
         ↓                         ↓
    Service: api             Service: web
         ↓                         ↓
    Pods: api-*             Pods: web-*
```

**Ingress Controller** (runs in cluster) reads Ingress resources and configures load balancer.

### 8. Volumes

**Persistent storage** that survives Pod restarts.

```
PersistentVolumeClaim (PVC)
    ↓ binds to
PersistentVolume (PV)
    ↓ backed by
AWS EBS Volume / EFS / S3
```

**Volume types:**
- **emptyDir** - Temporary, deleted with Pod
- **configMap/secret** - Mount config as files
- **persistentVolumeClaim** - Persistent storage
- **hostPath** - Node's filesystem (testing only)

---

## Cluster Architecture

Kubernetes cluster = **Control Plane** + **Worker Nodes**

```
┌─────────────────────────────────────────────────────────────┐
│                    KUBERNETES CLUSTER                       │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         CONTROL PLANE (Master Nodes)                │   │
│  │                                                     │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐         │   │
│  │  │ API      │  │Scheduler │  │Controller│         │   │
│  │  │ Server   │  │          │  │ Manager  │         │   │
│  │  └──────────┘  └──────────┘  └──────────┘         │   │
│  │                                                     │   │
│  │  ┌─────────────────────────────────────┐           │   │
│  │  │         etcd (cluster store)        │           │   │
│  │  └─────────────────────────────────────┘           │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│                          │ manages                          │
│                          ↓                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              WORKER NODES (Data Plane)              │   │
│  │                                                     │   │
│  │  ┌─────────────────┐  ┌─────────────────┐         │   │
│  │  │ Node 1          │  │ Node 2          │         │   │
│  │  │                 │  │                 │         │   │
│  │  │ ┌─────┐ ┌─────┐ │  │ ┌─────┐ ┌─────┐ │         │   │
│  │  │ │Pod 1│ │Pod 2│ │  │ │Pod 3│ │Pod 4│ │   ...   │   │
│  │  │ └─────┘ └─────┘ │  │ └─────┘ └─────┘ │         │   │
│  │  │                 │  │                 │         │   │
│  │  │ kubelet         │  │ kubelet         │         │   │
│  │  │ kube-proxy      │  │ kube-proxy      │         │   │
│  │  │ Container       │  │ Container       │         │   │
│  │  │ Runtime         │  │ Runtime         │         │   │
│  │  └─────────────────┘  └─────────────────┘         │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Control Plane vs Data Plane

**Control Plane (Brain)**
- Makes decisions
- Stores cluster state
- Schedules workloads
- Responds to events

**Data Plane (Muscle)**
- Runs application containers
- Executes control plane decisions
- Reports status back

**In managed services (EKS):** AWS manages control plane, you manage nodes.

---

## Control Plane Components

### 1. API Server (kube-apiserver)

**The front door to Kubernetes.** All communication goes through here.

```
kubectl → API Server → etcd
Scheduler → API Server → etcd
Kubelet → API Server → etcd
Controllers → API Server → etcd
```

**What it does:**
- ✅ Validates and processes API requests
- ✅ Authenticates users and service accounts
- ✅ Authorizes actions (RBAC)
- ✅ Persists state to etcd
- ✅ Serves API (REST)

**Example interaction:**
```bash
kubectl apply -f deployment.yaml
    ↓
1. kubectl sends HTTP POST to API Server
2. API Server validates YAML syntax
3. API Server checks authentication (who are you?)
4. API Server checks authorization (can you create Deployments?)
5. API Server validates resource schema
6. API Server writes to etcd
7. API Server returns success to kubectl
```

**In EKS:** AWS manages API Server, you access it via endpoint.

### 2. etcd

**Distributed key-value store** - the database of Kubernetes.

```
etcd stores:
├── All cluster configuration
├── All resource definitions (Deployments, Services, Pods)
├── All resource status (what's running where)
├── Secrets and ConfigMaps
└── Everything!
```

**Properties:**
- Strongly consistent (Raft consensus)
- Distributed (3-5 replicas for HA)
- Watch API (controllers watch for changes)
- Highly available

**Example data:**
```
Key: /registry/pods/production/day-7d4f9c8b5f-abc12
Value: {
  "metadata": {...},
  "spec": {...},
  "status": {
    "phase": "Running",
    "podIP": "10.0.1.45"
  }
}
```

**In EKS:** AWS fully manages etcd, automatic backups.

### 3. Scheduler (kube-scheduler)

**Assigns Pods to Nodes.**

```
1. Watch for new Pods with no node assignment
2. Filter nodes (which nodes can run this Pod?)
   - Has enough CPU/memory?
   - Matches node selectors?
   - Tolerates node taints?
3. Score nodes (which node is best?)
   - Resource utilization
   - Pod spreading
   - Affinity rules
4. Assign Pod to highest-scoring node
5. Update Pod spec with nodeName
```

**Example:**
```
New Pod created: day-7d4f9c8b5f-abc12
  Requires: 200m CPU, 256Mi memory

Node 1: 1000m CPU available, 2Gi memory → Score: 80
Node 2: 500m CPU available, 1Gi memory → Score: 60
Node 3: 100m CPU available, 512Mi memory → Score: 20

Scheduler assigns to Node 1 (highest score)
```

**Factors considered:**
- Resource requests/limits
- Node affinity/anti-affinity
- Pod affinity/anti-affinity
- Taints and tolerations
- Topology spread constraints

### 4. Controller Manager (kube-controller-manager)

**Runs multiple controllers** that reconcile desired state with actual state.

```
Controller Manager contains:
├── Deployment Controller (manages ReplicaSets)
├── ReplicaSet Controller (manages Pods)
├── Node Controller (monitors node health)
├── Service Account Controller (creates default accounts)
├── Endpoint Controller (populates Service endpoints)
├── Namespace Controller (cleans up deleted namespaces)
└── ... many more
```

**How controllers work:**
```
Loop forever:
1. Watch for changes (via API Server)
2. Compare desired state vs actual state
3. Take action to reconcile
4. Wait for next change
```

**Example - Deployment Controller:**
```
Event: Deployment updated (replicas: 2 → 5)
    ↓
1. Deployment Controller sees change
2. Checks current ReplicaSet (2 pods)
3. Needs 5 pods → creates 3 more
4. ReplicaSet Controller sees change
5. Creates 3 new Pods
6. Scheduler assigns to nodes
7. Kubelets start containers
```

See [deployment-hierarchy.md](deployment-hierarchy.md) for details.

### 5. Cloud Controller Manager (cloud-controller-manager)

**Interfaces with cloud provider APIs** (AWS, GCP, Azure).

```
Cloud Controller Manager contains:
├── Node Controller (registers EC2 instances as nodes)
├── Route Controller (sets up networking routes)
├── Service Controller (creates LoadBalancers)
└── Volume Controller (provisions EBS volumes)
```

**AWS-specific examples:**
- Creates AWS ALB when you create LoadBalancer Service
- Provisions EBS volumes for PersistentVolumeClaims
- Adds EC2 instance metadata to Nodes
- Configures VPC routing

More details in [Cloud Provider Integration](#cloud-provider-integration) section.

---

## Node Components

Worker nodes run the actual application containers.

### 1. Kubelet

**The node agent.** Runs on every node and manages Pods.

```
┌──────────────────────────────────┐
│         Worker Node              │
│                                  │
│  ┌────────────────────────────┐  │
│  │       Kubelet              │  │
│  │                            │  │
│  │  1. Watch API Server       │  │
│  │     for Pods assigned      │  │
│  │     to this node           │  │
│  │                            │  │
│  │  2. Tell Container Runtime │  │
│  │     to start/stop          │  │
│  │     containers             │  │
│  │                            │  │
│  │  3. Monitor container      │  │
│  │     health (probes)        │  │
│  │                            │  │
│  │  4. Report status to       │  │
│  │     API Server             │  │
│  └────────────────────────────┘  │
│              ↓                   │
│  ┌────────────────────────────┐  │
│  │   Container Runtime        │  │
│  │   (containerd/Docker)      │  │
│  │                            │  │
│  │   ┌──────┐  ┌──────┐      │  │
│  │   │Pod 1 │  │Pod 2 │      │  │
│  │   └──────┘  └──────┘      │  │
│  └────────────────────────────┘  │
└──────────────────────────────────┘
```

**Kubelet responsibilities:**
- ✅ Pull container images
- ✅ Start/stop containers
- ✅ Run liveness/readiness probes
- ✅ Mount volumes
- ✅ Report node/pod status
- ✅ Execute container commands (kubectl exec)
- ✅ Stream logs (kubectl logs)

**Example flow:**
```
1. API Server: "Pod abc12 scheduled to node-1"
2. Kubelet on node-1: "I see new Pod assigned to me"
3. Kubelet: "Pull image: day:v1.2.3"
4. Kubelet → Container Runtime: "Start container"
5. Container Runtime: "Container started"
6. Kubelet: "Wait 10 seconds (initialDelaySeconds)"
7. Kubelet: "Run readiness probe: HTTP GET /health"
8. Kubelet: "Probe succeeded, Pod is Ready"
9. Kubelet → API Server: "Pod abc12 status: Running, Ready"
```

### 2. Container Runtime

**Runs containers.** Kubelet talks to runtime via CRI (Container Runtime Interface).

**Common runtimes:**
- **containerd** (most common, default in EKS)
- **Docker** (via dockershim, deprecated)
- **CRI-O**

```
Kubelet (CRI client)
    ↓ CRI gRPC
Container Runtime (CRI server)
    ↓
Low-level container management
    ↓
Linux kernel (namespaces, cgroups)
    ↓
Running containers
```

**What runtime does:**
- Pull images from registry (ECR, Docker Hub)
- Create container filesystem
- Set up namespaces (network, PID, mount)
- Apply resource limits (cgroups)
- Start container processes
- Monitor container lifecycle

### 3. kube-proxy

**Manages network rules** for Service load balancing.

**Problem:** Services have virtual IPs that don't exist on network.

**Solution:** kube-proxy sets up iptables/ipvs rules to route traffic.

```
Pod tries to connect to: day-service:8001
    ↓
DNS resolves to: 10.100.200.50 (ClusterIP)
    ↓
Packet sent to: 10.100.200.50:8001
    ↓
iptables rule (created by kube-proxy):
  If destination = 10.100.200.50:8001
  Then randomly forward to:
    - 10.0.1.45:8001 (Pod 1)
    - 10.0.1.67:8001 (Pod 2)
    - 10.0.2.12:8001 (Pod 3)
    ↓
Packet arrives at actual Pod IP
```

**kube-proxy modes:**
- **iptables** (default) - Uses Linux iptables rules
- **ipvs** - Uses Linux IPVS (better performance, more modes)
- **userspace** (legacy) - Proxies traffic in userspace

**In EKS:** Uses iptables mode by default.

---

## Layered Architecture

Kubernetes architecture can be understood as layers of abstraction.

### Layer 1: Infrastructure Layer

```
┌──────────────────────────────────────────┐
│   Infrastructure (Cloud/Bare Metal)      │
│                                          │
│   AWS: EC2, VPC, EBS, IAM               │
│   GCP: Compute Engine, VPC, Disks       │
│   On-prem: Physical servers, storage    │
└──────────────────────────────────────────┘
```

**Managed by:** Cloud provider or ops team
**Kubernetes sees:** Compute, network, storage primitives

### Layer 2: Cluster Layer

```
┌──────────────────────────────────────────┐
│      Kubernetes Cluster                  │
│                                          │
│   Control Plane + Worker Nodes          │
│   Networking (CNI)                       │
│   Storage (CSI)                          │
└──────────────────────────────────────────┘
```

**Managed by:** Platform team (or AWS in EKS)
**Provides:** Container orchestration, scheduling, networking

### Layer 3: Platform Layer

```
┌──────────────────────────────────────────┐
│   Platform Services (Add-ons)            │
│                                          │
│   Ingress Controller (ALB/NGINX)        │
│   Monitoring (Prometheus)                │
│   Logging (Fluentd)                      │
│   Service Mesh (Istio) - optional        │
└──────────────────────────────────────────┘
```

**Managed by:** Platform team
**Provides:** Shared services for applications

### Layer 4: Application Layer

```
┌──────────────────────────────────────────┐
│        Applications                      │
│                                          │
│   Deployments, Services, ConfigMaps     │
│   Your microservices                     │
└──────────────────────────────────────────┘
```

**Managed by:** Application teams
**Provides:** Business logic, user-facing services

### Layer Interaction

```
Application → Platform → Cluster → Infrastructure

Example: Create LoadBalancer Service
    ↓
1. Application Layer: kubectl apply service.yaml
2. Cluster Layer: API Server stores Service
3. Cluster Layer: Service Controller sees new Service
4. Cluster Layer: Cloud Controller Manager called
5. Infrastructure Layer: AWS API creates ALB
6. Infrastructure Layer: ALB configured with targets
7. Platform Layer: Ingress Controller updates rules
8. Application Layer: Traffic flows to Pods
```

---

## Cloud Provider Integration

Kubernetes interfaces with cloud providers through **Cloud Controller Manager** and **CSI/CNI plugins**.

### Integration Points

```
┌───────────────────────────────────────────────────────────┐
│                    KUBERNETES CLUSTER                     │
│                                                           │
│  ┌─────────────────────────────────────────────────┐     │
│  │   Cloud Controller Manager                      │     │
│  │                                                 │     │
│  │   ┌───────────┐  ┌────────────┐  ┌──────────┐ │     │
│  │   │   Node    │  │  Service   │  │  Route   │ │     │
│  │   │Controller │  │ Controller │  │Controller│ │     │
│  │   └─────┬─────┘  └──────┬─────┘  └────┬─────┘ │     │
│  └─────────┼────────────────┼─────────────┼───────┘     │
│            │                │             │             │
│            ↓                ↓             ↓             │
│  ┌─────────────────────────────────────────────────┐    │
│  │        Cloud Provider APIs (AWS)                │    │
│  └─────────────────────────────────────────────────┘    │
└───────────────────────────────────────────────────────────┘
         │              │              │
         ↓              ↓              ↓
    ┌────────┐     ┌────────┐    ┌────────┐
    │  EC2   │     │  ALB   │    │  VPC   │
    └────────┘     └────────┘    └────────┘
```

### 1. Node Integration

**Kubernetes discovers and registers cloud instances as nodes.**

**AWS Example:**
```
1. EC2 instance starts with kubelet
2. Kubelet registers with API Server
3. Cloud Controller Manager:
   - Queries EC2 API for instance metadata
   - Adds labels: instance-type, availability-zone, region
   - Adds annotations: instance-id, public-ip
   - Monitors instance status
4. Node appears in kubectl get nodes
```

**Node labels from AWS:**
```yaml
metadata:
  labels:
    node.kubernetes.io/instance-type: t3.small
    topology.kubernetes.io/region: us-east-1
    topology.kubernetes.io/zone: us-east-1a
    eks.amazonaws.com/nodegroup: day-nodes
```

### 2. Load Balancer Integration

**Kubernetes Services create cloud load balancers.**

**AWS Example - LoadBalancer Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: day-service
spec:
  type: LoadBalancer  # ← Triggers AWS integration
  selector:
    app: day
  ports:
  - port: 80
    targetPort: 8001
```

**What happens:**
```
1. Service created in Kubernetes
2. Service Controller sees type: LoadBalancer
3. Cloud Controller Manager:
   - Calls AWS API: CreateLoadBalancer
   - Creates Classic ELB or NLB
   - Configures health checks
   - Registers node IPs as targets
   - Waits for LB to become active
4. Updates Service with external IP
5. kubectl get svc shows EXTERNAL-IP: abc.us-east-1.elb.amazonaws.com
```

**AWS Ingress (ALB) via Ingress Controller:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: day-ingress
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
spec:
  ingressClassName: alb
  rules:
  - host: day.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: day-service
            port:
              number: 80
```

**AWS Load Balancer Controller:**
```
1. Watches for Ingress resources
2. Calls AWS API:
   - CreateLoadBalancer (ALB)
   - CreateTargetGroup
   - CreateListener
   - RegisterTargets (Pod IPs directly!)
3. Configures routing rules
4. Manages ALB lifecycle
```

### 3. Storage Integration (CSI)

**Container Storage Interface** - standard for storage plugins.

**AWS EBS CSI Driver:**
```
Kubernetes StorageClass
    ↓
PersistentVolumeClaim created
    ↓
CSI Controller:
  - Calls AWS API: CreateVolume (EBS)
  - Waits for volume creation
  - Creates PersistentVolume in K8s
    ↓
Pod scheduled to node
    ↓
CSI Node Plugin:
  - Calls AWS API: AttachVolume
  - Mounts volume to node
  - Mounts into container
    ↓
Container has persistent storage
```

**Example:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ebs-claim
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: gp3  # ← AWS EBS gp3 type
```

**Behind the scenes:**
```bash
# AWS creates:
aws ec2 create-volume --size 10 --volume-type gp3

# Attaches to node:
aws ec2 attach-volume --volume-id vol-xxx --instance-id i-yyy

# Kubelet mounts:
mount /dev/xvdf /var/lib/kubelet/pods/.../volumes/ebs-claim
```

### 4. Networking Integration (CNI)

**Container Network Interface** - standard for network plugins.

**AWS VPC CNI:**
```
Pod created
    ↓
CNI Plugin:
  - Allocates ENI (Elastic Network Interface) to node
  - Assigns secondary IPs to ENI
  - Gives Pod an IP from VPC subnet
  - Pod has real VPC IP (routable!)
    ↓
Pod can communicate:
  - With other Pods (direct VPC routing)
  - With AWS services (S3, RDS, etc.)
  - With on-prem (via VPN/DirectConnect)
```

**Benefit:** Pods are first-class VPC citizens.

### 5. Identity Integration (IRSA)

**IAM Roles for Service Accounts** - gives Pods AWS permissions.

```
┌────────────────────────────────────┐
│  Pod: day-service                  │
│                                    │
│  ServiceAccount: day-sa            │
│  Annotation:                       │
│    eks.amazonaws.com/role-arn:     │
│      arn:aws:iam::xxx:role/DayRole │
└────────────────────────────────────┘
              ↓
    Pod makes AWS API call
              ↓
┌────────────────────────────────────┐
│  AWS STS AssumeRoleWithWebIdentity │
│  - Validates OIDC token from EKS   │
│  - Returns temporary credentials   │
└────────────────────────────────────┘
              ↓
    Pod has AWS permissions!
```

**Example use case:**
```python
# Pod can access S3 without hardcoded credentials
import boto3

s3 = boto3.client('s3')  # Automatically uses IRSA credentials
s3.list_buckets()        # Works if IAM role has s3:ListBuckets
```

---

## EKS: Managed Kubernetes on AWS

**Amazon Elastic Kubernetes Service (EKS)** is AWS's managed Kubernetes offering.

### What AWS Manages vs What You Manage

```
┌─────────────────────────────────────────────────┐
│        AWS MANAGES (Control Plane)              │
├─────────────────────────────────────────────────┤
│  ✅ API Server (multi-AZ, auto-scaling)         │
│  ✅ etcd (encrypted, backed up)                 │
│  ✅ Scheduler                                   │
│  ✅ Controller Manager                          │
│  ✅ Cloud Controller Manager                    │
│  ✅ Control plane upgrades                      │
│  ✅ Control plane security patches              │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│        YOU MANAGE (Data Plane)                  │
├─────────────────────────────────────────────────┤
│  ⚙️  Worker Nodes (EC2 instances)               │
│  ⚙️  Node Groups / Auto Scaling Groups          │
│  ⚙️  Node security patches                      │
│  ⚙️  Node upgrades                              │
│  ⚙️  Add-ons (ALB Controller, CSI drivers)      │
│  ⚙️  Applications and workloads                 │
└─────────────────────────────────────────────────┘
```

### EKS Architecture

```
┌───────────────────────────────────────────────────────┐
│                    AWS ACCOUNT                        │
│                                                       │
│  ┌─────────────────────────────────────────────┐     │
│  │  EKS Control Plane (AWS-managed VPC)        │     │
│  │                                             │     │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  │     │
│  │  │ API      │  │Scheduler │  │   etcd   │  │     │
│  │  │ Server   │  │          │  │          │  │     │
│  │  └──────────┘  └──────────┘  └──────────┘  │     │
│  │                                             │     │
│  │  Multi-AZ, Auto-scaled, Highly Available    │     │
│  └─────────────────┬───────────────────────────┘     │
│                    │                                 │
│                    │ Secured endpoint                │
│                    │ (public or private)             │
│                    ↓                                 │
│  ┌─────────────────────────────────────────────┐    │
│  │     Your VPC (10.1.0.0/16)                  │    │
│  │                                             │    │
│  │  ┌─────────────┐  ┌─────────────┐          │    │
│  │  │  Subnet 1   │  │  Subnet 2   │          │    │
│  │  │  us-east-1a │  │  us-east-1b │          │    │
│  │  │             │  │             │          │    │
│  │  │ ┌─────────┐ │  │ ┌─────────┐ │          │    │
│  │  │ │ Node 1  │ │  │ │ Node 2  │ │          │    │
│  │  │ │ (EC2)   │ │  │ │ (EC2)   │ │          │    │
│  │  │ │         │ │  │ │         │ │          │    │
│  │  │ │ Pods    │ │  │ │ Pods    │ │          │    │
│  │  │ └─────────┘ │  │ └─────────┘ │          │    │
│  │  └─────────────┘  └─────────────┘          │    │
│  └─────────────────────────────────────────────┘    │
└───────────────────────────────────────────────────────┘
```

### How EKS Relates to Kubernetes

**EKS IS Kubernetes** - just with AWS managing the control plane.

**Compatibility:**
- ✅ 100% upstream Kubernetes (certified conformant)
- ✅ Standard kubectl works
- ✅ Standard Kubernetes APIs
- ✅ Standard YAML manifests
- ✅ Portable to other Kubernetes (GKE, AKS, self-managed)

**AWS-specific integrations:**
- VPC CNI (Pods get VPC IPs)
- AWS Load Balancer Controller (ALB/NLB creation)
- EBS CSI Driver (EBS volume provisioning)
- EFS CSI Driver (EFS filesystem mounting)
- IRSA (IAM roles for Pods)

### EKS Cluster Creation Flow

```
1. Create EKS Cluster (via AWS Console, CLI, or Pulumi)
   - AWS creates control plane in AWS-managed VPC
   - Creates API endpoint (public and/or private)
   - Sets up OIDC provider for IRSA
   - Takes ~10-15 minutes

2. Create Node Group (Managed or Self-managed)
   - AWS launches EC2 instances
   - Instances join cluster (via bootstrap script)
   - Kubelet registers with API Server
   - Nodes appear in kubectl get nodes

3. Install Add-ons
   - VPC CNI (networking) - pre-installed
   - kube-proxy - pre-installed
   - CoreDNS - pre-installed
   - AWS Load Balancer Controller - install yourself
   - EBS CSI Driver - install yourself
   - Metrics Server - install yourself

4. Deploy Applications
   - kubectl apply or Helm or ArgoCD
   - Pods scheduled to nodes
   - Services create load balancers
   - Applications running!
```

### Accessing EKS Cluster

**Authentication:**
```bash
# Update kubeconfig with EKS cluster info
aws eks update-kubeconfig --name day-cluster --region us-east-1

# This creates ~/.kube/config entry:
# - Cluster API endpoint
# - Certificate authority data
# - Auth command: aws eks get-token

# When you run kubectl:
kubectl get pods
    ↓
1. kubectl reads ~/.kube/config
2. Runs: aws eks get-token --cluster-name day-cluster
3. AWS returns temporary token (via STS)
4. kubectl sends token to EKS API Server
5. EKS validates token with AWS IAM
6. EKS checks IAM permissions (RBAC)
7. Request processed if authorized
```

**IAM to Kubernetes mapping:**
```
AWS IAM User/Role
    ↓ mapped via aws-auth ConfigMap
Kubernetes User/Group
    ↓ bound via RoleBinding
Kubernetes Role
    ↓ defines
Permissions (verbs on resources)
```

### EKS Networking Deep Dive

**VPC CNI Plugin:**
```
┌──────────────────────────────────────┐
│  Node (EC2 instance)                 │
│                                      │
│  Primary ENI (eth0)                  │
│  - Primary IP: 10.1.1.50            │
│  - Secondary IPs:                    │
│    - 10.1.1.51 → Pod 1              │
│    - 10.1.1.52 → Pod 2              │
│    - 10.1.1.53 → Pod 3              │
│    - 10.1.1.54 → Pod 4              │
│                                      │
│  Secondary ENI (eth1) if needed      │
│  - Primary IP: 10.1.1.60            │
│  - Secondary IPs:                    │
│    - 10.1.1.61 → Pod 5              │
│    - ...                             │
└──────────────────────────────────────┘
```

**Max Pods per node:**
```
Formula: (ENIs × IPs per ENI) - 1
Example for t3.small:
  - Max ENIs: 3
  - IPs per ENI: 4
  - Max Pods: (3 × 4) - 1 = 11
```

**Benefits of VPC CNI:**
- Pods are VPC citizens (Security Groups apply)
- Direct Pod-to-Pod routing (no overlay)
- Pod IPs routable from on-prem
- Simpler network debugging

**Trade-off:** Uses VPC IP addresses (plan subnet size accordingly!)

---

## How It All Works Together

Let's trace a complete flow: deploying an application to EKS.

### Scenario: Deploy Day Service

**1. Developer creates Deployment:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: day-service
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: day
  template:
    metadata:
      labels:
        app: day
    spec:
      containers:
      - name: day
        image: 123456789.dkr.ecr.us-east-1.amazonaws.com/day:v1.2.3
        ports:
        - containerPort: 8001
        env:
        - name: LOG_LEVEL
          value: "info"
```

**2. Apply to cluster:**
```bash
kubectl apply -f deployment.yaml
```

**3. API Server processing:**
```
kubectl → HTTPS POST → EKS API Server (AWS-managed)
    ↓
1. API Server authenticates (AWS IAM token)
2. API Server authorizes (RBAC check)
3. API Server validates YAML schema
4. API Server writes to etcd
5. API Server returns: "deployment.apps/day-service created"
```

**4. Deployment Controller processing:**
```
Deployment Controller (in AWS-managed control plane):
1. Watch detects new Deployment
2. Reads: replicas=3, no ReplicaSets exist
3. Creates ReplicaSet: day-service-7d4f9c8b5f
4. Sets replicas=3 on ReplicaSet
5. Writes ReplicaSet to API Server → etcd
```

**5. ReplicaSet Controller processing:**
```
ReplicaSet Controller:
1. Watch detects new ReplicaSet
2. Reads: replicas=3, no Pods exist
3. Creates 3 Pods:
   - day-service-7d4f9c8b5f-abc12
   - day-service-7d4f9c8b5f-def34
   - day-service-7d4f9c8b5f-ghi56
4. Writes Pods to API Server → etcd
```

**6. Scheduler processing:**
```
Scheduler:
1. Watch detects 3 new Pods (nodeName: empty)
2. For each Pod:
   a. Filter nodes (CPU/memory available?)
   b. Score nodes (best fit?)
   c. Select best node
   d. Update Pod: nodeName=ip-10-1-1-50
3. Writes updates to API Server → etcd
```

**7. Kubelet processing (on each node):**
```
Kubelet on ip-10-1-1-50 (EC2 instance):
1. Watch detects Pod assigned to this node
2. Calls CNI plugin:
   - Allocates IP from VPC subnet: 10.1.1.101
   - Sets up network namespace
3. Calls Container Runtime (containerd):
   - Pulls image from ECR (AWS authentication)
   - Creates container from image
   - Mounts volumes (if any)
   - Applies resource limits
   - Starts container
4. Runs health probes (if defined)
5. Reports status to API Server:
   - Phase: Running
   - Ready: true
   - IP: 10.1.1.101
```

**8. Service creation (expose app):**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: day-service
  namespace: production
spec:
  type: ClusterIP
  selector:
    app: day
  ports:
  - port: 80
    targetPort: 8001
```

**9. Service Controller & kube-proxy:**
```
Service Controller:
1. Detects new Service
2. Allocates ClusterIP: 10.100.200.50
3. Creates Endpoints:
   - 10.1.1.101:8001 (Pod 1)
   - 10.1.1.102:8001 (Pod 2)
   - 10.1.1.103:8001 (Pod 3)

kube-proxy (on every node):
1. Detects new Service
2. Creates iptables rules:
   DNAT: 10.100.200.50:80 → random(10.1.1.101:8001, 10.1.1.102:8001, 10.1.1.103:8001)
```

**10. Ingress creation (external access):**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: day-ingress
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
spec:
  ingressClassName: alb
  rules:
  - host: day.example.com
    http:
      paths:
      - path: /
        backend:
          service:
            name: day-service
            port:
              number: 80
```

**11. AWS Load Balancer Controller:**
```
ALB Controller (running as Pod in cluster):
1. Detects new Ingress
2. Calls AWS APIs:
   - CreateLoadBalancer (ALB)
   - CreateTargetGroup (pod IPs directly!)
   - RegisterTargets:
     - 10.1.1.101:8001
     - 10.1.1.102:8001
     - 10.1.1.103:8001
   - CreateListener (port 80)
   - CreateRule (host: day.example.com → target group)
3. Waits for ALB to become active
4. Updates Ingress status:
   loadBalancer.ingress[0].hostname: k8s-production-dayingre-xxx.us-east-1.elb.amazonaws.com
```

**12. Traffic flow (user request):**
```
User: curl http://day.example.com/health
    ↓
DNS: day.example.com → k8s-production-dayingre-xxx.us-east-1.elb.amazonaws.com
    ↓
AWS ALB: k8s-production-dayingre-xxx.us-east-1.elb.amazonaws.com
    ↓ ALB chooses target (Pod IP directly - no kube-proxy!)
Pod: 10.1.1.102:8001
    ↓
Container: day:v1.2.3
    ↓
Flask app: return {"status": "healthy"}
    ↓
User receives: {"status": "healthy"}
```

---

## Real-World Example from This Project

Our Day cluster demonstrates all these concepts:

### Infrastructure Stack (Pulumi)
```python
# foundation/provisioning/pulumi/__main__.py

# 1. VPC (infrastructure layer)
vpc = aws.ec2.Vpc("day-vpc", cidr_block="10.1.0.0/16")

# 2. EKS Cluster (cluster layer)
cluster = eks.Cluster(
    "day-cluster",
    vpc_id=vpc.id,
    subnet_ids=[subnet.id for subnet in subnets],
)

# 3. Node Group (compute)
node_group = aws.eks.NodeGroup(
    "day-nodes",
    cluster_name=cluster.eks_cluster.name,
    instance_types=["t3.small"],
    scaling_config={
        "desired_size": 2,
        "min_size": 1,
        "max_size": 3,
    },
    capacity_type="SPOT",  # Using spot instances
)

# 4. ALB Controller (platform layer)
alb_controller = k8s.helm.v3.Release(
    "aws-load-balancer-controller",
    chart="aws-load-balancer-controller",
    repository_opts={"repo": "https://aws.github.io/eks-charts"},
)
```

### Application Stack (Pulumi or YAML)
```python
# foundation/gitops/pulumi_deploy/__main__.py

# Reference infrastructure stack
infra = pulumi.StackReference("organization/infrastructure/day")
kubeconfig = infra.get_output("kubeconfig")

# Create Kubernetes resources
deployment = k8s.apps.v1.Deployment(...)
service = k8s.core.v1.Service(...)
configmap = k8s.core.v1.ConfigMap(...)
hpa = k8s.autoscaling.v2.HorizontalPodAutoscaler(...)
ingress = k8s.networking.v1.Ingress(...)
```

### What Happens When We Deploy

```
1. Pulumi infrastructure stack:
   - Creates VPC in AWS
   - Creates EKS cluster (AWS manages control plane)
   - Creates node group (EC2 instances join cluster)
   - Installs ALB controller (Helm chart → Kubernetes Deployment)

2. Pulumi application stack:
   - Connects to EKS via kubeconfig
   - Creates Deployment → ReplicaSet → Pods
   - Scheduler assigns Pods to nodes
   - Kubelet starts containers
   - Creates Service (ClusterIP)
   - kube-proxy configures iptables
   - Creates Ingress
   - ALB Controller creates AWS ALB
   - Traffic flows: Internet → ALB → Pods

3. Autoscaling:
   - HPA watches CPU/memory metrics
   - Scales replicas: 2 → 5 (if high load)
   - Cluster Autoscaler adds nodes if needed
   - AWS Auto Scaling Group launches EC2 instances

4. Updates:
   - Change image: day:v1.2.3 → day:v1.2.4
   - Deployment Controller creates new ReplicaSet
   - Rolling update: old pods → new pods
   - Zero downtime!
```

---

## Summary

### Core Concepts
- **Pods** - Smallest deployable unit (wraps containers)
- **Deployments** - Manage Pods, handle updates/scaling
- **Services** - Stable network endpoint for Pods
- **ConfigMaps/Secrets** - Configuration management
- **Ingress** - HTTP routing to Services

### Architecture
- **Control Plane** - Brain (API Server, etcd, Scheduler, Controllers)
- **Data Plane** - Muscle (Nodes, Kubelet, Container Runtime)
- **Declarative** - Desired state → Controllers reconcile

### Cloud Integration
- **Cloud Controller Manager** - Interfaces with cloud APIs
- **LoadBalancer Services** - Create cloud load balancers
- **CSI** - Provision cloud storage (EBS, EFS)
- **CNI** - Cloud networking (VPC integration)
- **IRSA** - Cloud identity (IAM roles for Pods)

### EKS Specifics
- **AWS manages** - Control plane, etcd, upgrades
- **You manage** - Nodes, applications, add-ons
- **Fully compatible** - Standard Kubernetes APIs
- **AWS integrated** - VPC CNI, ALB Controller, EBS CSI

### The Flow
```
Developer → kubectl → API Server → etcd
                         ↓
            Controllers watch → Reconcile
                         ↓
                   Scheduler → Assign Pods
                         ↓
                   Kubelet → Start Containers
                         ↓
                 Cloud APIs → Provision Resources
                         ↓
                  Running Application!
```

## Next Steps

**Explore deeper:**
- [deployment-hierarchy.md](../05-kubernetes-deep-dives/deployment-hierarchy.md) - How Deployments work
- [configmap-relationships.md](../05-kubernetes-deep-dives/configmap-relationships.md) - Configuration management
- [rolling-updates.md](../05-kubernetes-deep-dives/rolling-updates.md) - Zero-downtime updates
- [two-tier-architecture.md](../02-infrastructure-as-code/two-tier-architecture.md) - Infrastructure as Code

**Try it yourself:**
- [first-deployment.md](first-deployment.md) - Deploy your first cluster
- [deploy-with-pulumi.md](../02-infrastructure-as-code/deploy-with-pulumi.md) - Pulumi-managed cluster
- Exploration scripts: `foundation/gitops/manual_deploy/explore/`

**Official documentation:**
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)

---

You now understand how Kubernetes works from containers to cloud! 🚀
