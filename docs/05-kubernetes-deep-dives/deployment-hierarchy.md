# How Deployments Create Pods in Kubernetes

## Table of Contents
- [Quick Answer](#quick-answer)
- [The Controller Pattern](#the-controller-pattern)
- [The Three-Layer Hierarchy](#the-three-layer-hierarchy)
- [Step-by-Step: What Happens When You Create a Deployment](#step-by-step-what-happens-when-you-create-a-deployment)
- [Understanding Each Resource Type](#understanding-each-resource-type)
- [The Naming Convention](#the-naming-convention)
- [Ownership and Garbage Collection](#ownership-and-garbage-collection)
- [Self-Healing in Action](#self-healing-in-action)
- [Rolling Updates: Creating New ReplicaSets](#rolling-updates-creating-new-replicasets)
- [The Controller Reconciliation Loop](#the-controller-reconciliation-loop)
- [Hands-On Examples](#hands-on-examples)
- [Common Patterns and Best Practices](#common-patterns-and-best-practices)
- [Troubleshooting](#troubleshooting)

---

## Quick Answer

**Yes, Pods are automatically created when you create a Deployment.**

You never create Pods directly. Instead:
1. You create a **Deployment** (declarative: "I want 2 replicas")
2. Kubernetes automatically creates a **ReplicaSet**
3. The ReplicaSet automatically creates **Pods**

```
Deployment (what you create)
    ↓ creates
ReplicaSet (automatically created)
    ↓ creates
Pods (automatically created)
```

---

## The Controller Pattern

Kubernetes uses a **control loop pattern** where specialized controllers continuously work to make the actual state match your desired state.

### How Controllers Work

```
┌─────────────────────────────────────────────┐
│         KUBERNETES CONTROL PLANE            │
│                                             │
│  ┌──────────────────────────────────┐       │
│  │   Deployment Controller          │       │
│  │   - Watches: Deployments         │       │
│  │   - Creates: ReplicaSets         │       │
│  └──────────────────────────────────┘       │
│                                             │
│  ┌──────────────────────────────────┐       │
│  │   ReplicaSet Controller          │       │
│  │   - Watches: ReplicaSets         │       │
│  │   - Creates: Pods                │       │
│  └──────────────────────────────────┘       │
│                                             │
│  ┌──────────────────────────────────┐       │
│  │   Scheduler                      │       │
│  │   - Watches: Unscheduled Pods    │       │
│  │   - Assigns: Pods to Nodes       │       │
│  └──────────────────────────────────┘       │
└─────────────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────┐
│           WORKER NODES                      │
│                                             │
│  ┌──────────────────────────────────┐       │
│  │   Kubelet                        │       │
│  │   - Watches: Pods assigned to me │       │
│  │   - Starts: Containers           │       │
│  └──────────────────────────────────┘       │
└─────────────────────────────────────────────┘
```

Each controller runs an infinite loop:

```python
while True:
    desired_state = read_from_api_server()
    actual_state = observe_cluster()

    if actual_state != desired_state:
        reconcile(actual_state, desired_state)

    sleep(interval)
```

---

## The Three-Layer Hierarchy

### Why Three Layers?

Each layer has a specific responsibility:

```
┌─────────────────────────────────────────────────────────┐
│ LAYER 1: Deployment                                     │
│ Responsibility: Declarative updates & rollbacks         │
│ - Manages which version is running                      │
│ - Controls rollout strategy (rolling, recreate)         │
│ - Maintains rollback history                            │
└────────────────────┬────────────────────────────────────┘
                     │ manages
                     ↓
┌─────────────────────────────────────────────────────────┐
│ LAYER 2: ReplicaSet                                     │
│ Responsibility: Maintain exact replica count            │
│ - Ensures desired number of pods are running            │
│ - Replaces failed pods                                  │
│ - Scales up/down based on Deployment spec               │
└────────────────────┬────────────────────────────────────┘
                     │ creates & monitors
                     ↓
┌─────────────────────────────────────────────────────────┐
│ LAYER 3: Pod                                            │
│ Responsibility: Run your container(s)                   │
│ - Smallest deployable unit                              │
│ - Ephemeral (can be deleted/recreated anytime)          │
│ - Runs on a single node                                 │
└─────────────────────────────────────────────────────────┘
```

### Separation of Concerns

| What | Who Manages It | Why Separate |
|------|----------------|--------------|
| **Version updates** | Deployment | Allows rolling updates without touching replica management |
| **Replica count** | ReplicaSet | Can scale without recreating pods |
| **Container execution** | Pod | Can be replaced without changing higher-level configs |

---

## Step-by-Step: What Happens When You Create a Deployment

Let's trace through the entire process using an example from this repository.

### Step 1: You Define and Apply a Deployment

```bash
kubectl apply -f foundation/gitops/manual_deploy/day/prod/deployment.yaml
```

**deployment.yaml:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: day
  namespace: day-ns
spec:
  replicas: 2
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
        image: day:latest
        ports:
        - containerPort: 8001
```

### Step 2: API Server Stores the Deployment

```
You → kubectl → API Server → etcd (stores Deployment object)
```

The Deployment object is now persisted in the cluster's database (etcd).

### Step 3: Deployment Controller Creates ReplicaSet

The **Deployment Controller** (running in kube-controller-manager) notices the new Deployment:

```
Deployment Controller:
  - "I see a new Deployment 'day' with replicas=2"
  - "Does a ReplicaSet exist for this pod template? No."
  - "Creating ReplicaSet..."
```

**Auto-generated ReplicaSet:**
```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: day-7d4f9c8b5f  # ← Deployment name + hash of pod template
  namespace: day-ns
  ownerReferences:
  - apiVersion: apps/v1
    kind: Deployment
    name: day  # ← Points back to parent Deployment
    uid: <deployment-uid>
    controller: true
    blockOwnerDeletion: true
spec:
  replicas: 2
  selector:
    matchLabels:
      app: day
      pod-template-hash: 7d4f9c8b5f  # ← Extra label added
  template:
    metadata:
      labels:
        app: day
        pod-template-hash: 7d4f9c8b5f
    spec:
      containers:
      - name: day
        image: day:latest
        ports:
        - containerPort: 8001
```

**Key additions:**
- `pod-template-hash` label (computed from pod template)
- `ownerReferences` linking back to Deployment

### Step 4: ReplicaSet Controller Creates Pods

The **ReplicaSet Controller** notices the new ReplicaSet:

```
ReplicaSet Controller:
  - "I see ReplicaSet 'day-7d4f9c8b5f' wants 2 replicas"
  - "How many pods with matching labels exist? 0"
  - "Need to create 2 pods"
  - "Creating pod 1..."
  - "Creating pod 2..."
```

**Auto-generated Pod 1:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: day-7d4f9c8b5f-abc12  # ← ReplicaSet name + random suffix
  namespace: day-ns
  labels:
    app: day
    pod-template-hash: 7d4f9c8b5f
  ownerReferences:
  - apiVersion: apps/v1
    kind: ReplicaSet
    name: day-7d4f9c8b5f  # ← Points back to ReplicaSet
    uid: <replicaset-uid>
    controller: true
    blockOwnerDeletion: true
spec:
  containers:
  - name: day
    image: day:latest
    ports:
    - containerPort: 8001
  # ... all other specs from template
```

**Auto-generated Pod 2:**
```yaml
metadata:
  name: day-7d4f9c8b5f-def34  # ← Different random suffix
  # ... same as Pod 1
```

### Step 5: Scheduler Assigns Pods to Nodes

The **Scheduler** notices unscheduled pods:

```
Scheduler:
  - "Pod 'day-7d4f9c8b5f-abc12' has no node assigned"
  - "Checking available nodes..."
  - "Node 'ip-10-0-1-123' has enough CPU/memory"
  - "Assigning pod to this node"
```

Updates Pod spec:
```yaml
spec:
  nodeName: ip-10-0-1-123  # ← Added by scheduler
```

### Step 6: Kubelet Starts Containers

The **Kubelet** on node `ip-10-0-1-123` notices a pod assigned to it:

```
Kubelet:
  - "I see pod 'day-7d4f9c8b5f-abc12' assigned to me"
  - "Pulling image 'day:latest'..."
  - "Creating container..."
  - "Starting container..."
  - "Container running! Reporting status to API server"
```

### Step 7: Status Propagates Up

```
Pod status: Running
    ↓ updates
ReplicaSet status: 2/2 replicas ready
    ↓ updates
Deployment status: 2/2 replicas available
```

### Final State

```bash
$ kubectl get deployment,replicaset,pod -n day-ns

NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/day   2/2     2            2           1m

NAME                             DESIRED   CURRENT   READY   AGE
replicaset.apps/day-7d4f9c8b5f   2         2         2       1m

NAME                       READY   STATUS    RESTARTS   AGE
pod/day-7d4f9c8b5f-abc12   1/1     Running   0          1m
pod/day-7d4f9c8b5f-def34   1/1     Running   0          1m
```

---

## Understanding Each Resource Type

### Deployment

**Purpose:** Declarative updates for Pods and ReplicaSets

**What it manages:**
- Which version/image should be running
- How many replicas
- Update strategy (RollingUpdate, Recreate)
- Rollout history (keeps old ReplicaSets for rollback)

**Key fields:**
```yaml
spec:
  replicas: 2                    # How many pods
  strategy:
    type: RollingUpdate          # How to update
    rollingUpdate:
      maxSurge: 1                # Extra pods during update
      maxUnavailable: 0          # Min available during update
  selector:
    matchLabels:                 # How to find managed ReplicaSets
      app: day
  template:                      # Pod template (passed to ReplicaSet)
    metadata:
      labels:
        app: day
    spec:
      containers:
      - name: day
        image: day:latest
```

**When to use:**
- Almost always! This is the standard way to deploy applications
- Any stateless application
- Apps that need rolling updates

**When NOT to use:**
- StatefulSets (for stateful apps like databases)
- DaemonSets (one pod per node, like log collectors)
- Jobs (run-to-completion tasks)

### ReplicaSet

**Purpose:** Maintain a stable set of replica Pods

**What it manages:**
- Ensures the exact number of pods are running
- Creates new pods when needed
- Deletes excess pods

**Key fields:**
```yaml
spec:
  replicas: 2                    # Target number of pods
  selector:
    matchLabels:                 # How to find managed Pods
      app: day
      pod-template-hash: 7d4f9c8b5f
  template:                      # Pod template
    # ... pod spec
```

**When to use:**
- You don't directly create ReplicaSets!
- Let Deployments manage them
- Exception: Direct use in advanced scenarios (rare)

**Reconciliation logic:**
```python
def reconcile_replicaset(rs):
    desired = rs.spec.replicas
    pods = get_pods_matching_selector(rs.spec.selector)
    current = count_ready_pods(pods)

    if current < desired:
        for i in range(desired - current):
            create_pod_from_template(rs.spec.template)
    elif current > desired:
        pods_to_delete = current - desired
        delete_oldest_pods(pods, pods_to_delete)
```

### Pod

**Purpose:** Run one or more containers

**What it contains:**
- One or more containers (usually one)
- Shared network namespace (containers share localhost)
- Shared storage volumes
- Specification for how to run containers

**Key fields:**
```yaml
spec:
  containers:
  - name: day
    image: day:latest
    ports:
    - containerPort: 8001
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 200m
        memory: 256Mi
    livenessProbe:              # Restart if this fails
      httpGet:
        path: /health
        port: 8001
    readinessProbe:             # Remove from service if this fails
      httpGet:
        path: /health
        port: 8001
```

**Lifecycle:**
- Pods are ephemeral (temporary)
- Each pod gets a unique IP (lost when pod is deleted)
- Pods are never moved between nodes (deleted and recreated instead)
- Pod names are immutable

---

## The Naming Convention

Understanding the naming pattern helps you trace the hierarchy:

```
Deployment name:  day
                   ↓
ReplicaSet name:  day-7d4f9c8b5f
                   ↑   ↑
                   │   └── Hash of pod template (changes when template changes)
                   └────── Deployment name

Pod name:         day-7d4f9c8b5f-abc12
                   ↑              ↑
                   │              └── Random suffix (unique per pod)
                   └──────────────── ReplicaSet name
```

### Pod Template Hash

The hash is computed from the pod template:

```python
# Simplified version
def compute_pod_template_hash(template):
    # Serialize pod spec to JSON
    json_str = json.dumps(template.spec, sort_keys=True)
    # Hash it
    hash_value = hashlib.sha256(json_str.encode()).hexdigest()
    # Take first 10 characters
    return hash_value[:10]
```

**Why use a hash?**
- When you update the deployment (change image, env vars, etc.), the template changes
- New hash → New ReplicaSet → Gradual rollout
- Old hash → Old ReplicaSet → Kept for rollback

### Example: Tracing a Pod

```bash
$ kubectl get pod day-7d4f9c8b5f-abc12 -n day-ns

# From the name, you can tell:
# - Deployment name: "day"
# - ReplicaSet: "day-7d4f9c8b5f"
# - This specific pod: "abc12"

# Verify ownership:
$ kubectl get pod day-7d4f9c8b5f-abc12 -n day-ns -o yaml | grep -A 5 ownerReferences

ownerReferences:
- apiVersion: apps/v1
  kind: ReplicaSet
  name: day-7d4f9c8b5f    # ← Confirms parent
```

---

## Ownership and Garbage Collection

Kubernetes uses **ownerReferences** to track resource relationships.

### Owner References

Every managed resource has an `ownerReferences` field:

```yaml
ownerReferences:
- apiVersion: apps/v1
  kind: ReplicaSet
  name: day-7d4f9c8b5f
  uid: a1b2c3d4-e5f6-7890-abcd-1234567890ab
  controller: true              # ← This owner is the controller
  blockOwnerDeletion: true      # ← Can't delete owner while this exists
```

### The Ownership Chain

```
Deployment (no owner)
    ↓ owns
ReplicaSet (owned by Deployment)
    ↓ owns
Pods (owned by ReplicaSet)
```

### Garbage Collection

When you delete the Deployment:

```bash
kubectl delete deployment day -n day-ns
```

**What happens:**
1. Deployment is marked for deletion
2. Garbage collector finds all ReplicaSets owned by this Deployment
3. ReplicaSets are deleted
4. Garbage collector finds all Pods owned by those ReplicaSets
5. Pods are deleted
6. Kubelet stops containers

**Cascade options:**

```bash
# Default: Delete everything (cascade)
kubectl delete deployment day -n day-ns

# Keep ReplicaSets and Pods (orphan them)
kubectl delete deployment day -n day-ns --cascade=orphan

# Delete in background (async)
kubectl delete deployment day -n day-ns --cascade=background

# Delete in foreground (wait for children to delete)
kubectl delete deployment day -n day-ns --cascade=foreground
```

---

## Self-Healing in Action

The ReplicaSet controller provides automatic recovery.

### Scenario 1: Pod Crashes

```bash
# Simulate pod crash
kubectl delete pod day-7d4f9c8b5f-abc12 -n day-ns
```

**What happens:**

```
T+0s:  Pod deleted
       ReplicaSet controller notices: current_pods = 1, desired = 2

T+1s:  ReplicaSet creates new pod: day-7d4f9c8b5f-xyz99
       Scheduler assigns it to a node

T+5s:  Kubelet pulls image and starts container

T+15s: Container passes readiness probe
       Pod is Ready
       Service starts sending traffic to it
```

Timeline:
```
kubectl get pods -n day-ns --watch

NAME                   READY   STATUS    RESTARTS   AGE
day-7d4f9c8b5f-abc12   1/1     Running   0          5m
day-7d4f9c8b5f-def34   1/1     Running   0          5m
day-7d4f9c8b5f-abc12   1/1     Terminating   0      5m      ← Deleted
day-7d4f9c8b5f-xyz99   0/1     Pending       0      0s      ← Created
day-7d4f9c8b5f-xyz99   0/1     ContainerCreating   0   1s
day-7d4f9c8b5f-abc12   0/1     Terminating         0   5m
day-7d4f9c8b5f-abc12   0/1     Terminating         0   5m
day-7d4f9c8b5f-xyz99   1/1     Running             0   15s   ← Ready
```

### Scenario 2: Node Failure

```
Node ip-10-0-1-123 becomes unreachable
    ↓
After 40s: Pods on that node marked as Unknown
    ↓
After 5m: ReplicaSet controller creates replacement pods on healthy nodes
    ↓
New pods start on different nodes
```

**Grace period exists** to avoid creating duplicates if node comes back quickly.

### Scenario 3: Manual Scaling

```bash
# Scale up
kubectl scale deployment day --replicas=5 -n day-ns
```

**What happens:**
```
Deployment updated: replicas = 5
    ↓
Deployment controller updates ReplicaSet: replicas = 5
    ↓
ReplicaSet controller sees: current = 2, desired = 5
    ↓
Creates 3 new pods: day-7d4f9c8b5f-aaa11, day-7d4f9c8b5f-bbb22, day-7d4f9c8b5f-ccc33
```

---

## Rolling Updates: Creating New ReplicaSets

When you update the Deployment, a new ReplicaSet is created.

### Example: Update Image

```bash
# Update deployment to use new image
kubectl set image deployment/day day=day:v2 -n day-ns

# Or edit the deployment
kubectl edit deployment day -n day-ns
# Change: image: day:latest → image: day:v2
```

### What Happens During Rolling Update

**Before update:**
```
Deployment: day (image: day:v1)
    ↓
ReplicaSet: day-7d4f9c8b5f (replicas: 2)
    ↓
Pods: day-7d4f9c8b5f-abc12, day-7d4f9c8b5f-def34
```

**After update initiated:**
```
Deployment: day (image: day:v2)  ← Updated
    ↓
    ├─→ ReplicaSet: day-7d4f9c8b5f (old) (replicas: 2 → 0)
    │       ↓
    │   Pods: day-7d4f9c8b5f-abc12, day-7d4f9c8b5f-def34 (terminating)
    │
    └─→ ReplicaSet: day-8f5a3c9d2e (new) (replicas: 0 → 2)
            ↓
        Pods: day-8f5a3c9d2e-ghi78, day-8f5a3c9d2e-jkl90 (starting)
```

**Notice:** New pod template hash `8f5a3c9d2e` because template changed!

### Step-by-Step Rolling Update

With `maxSurge: 1` and `maxUnavailable: 0`:

```
T+0s:   Current state: 2 old pods running

T+1s:   Create 1 new pod (surge)
        Old ReplicaSet: 2 pods
        New ReplicaSet: 1 pod (ContainerCreating)
        Total: 3 pods

T+10s:  New pod becomes Ready
        Old ReplicaSet: 2 pods
        New ReplicaSet: 1 pod (Running)

T+11s:  Terminate 1 old pod
        Old ReplicaSet: 1 pod (Terminating)
        New ReplicaSet: 1 pod (Running)

T+15s:  Old pod terminated, create another new pod
        Old ReplicaSet: 1 pod (Running)
        New ReplicaSet: 2 pods (1 Running, 1 Creating)

T+25s:  Second new pod becomes Ready
        Old ReplicaSet: 1 pod (Running)
        New ReplicaSet: 2 pods (Running)

T+26s:  Terminate last old pod
        Old ReplicaSet: 0 pods
        New ReplicaSet: 2 pods (Running)

Update complete! ✓
```

### Observing the Update

```bash
# Watch the update in real-time
kubectl rollout status deployment/day -n day-ns

# Output:
Waiting for deployment "day" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "day" rollout to finish: 1 old replicas are pending termination...
deployment "day" successfully rolled out

# See both ReplicaSets
kubectl get rs -n day-ns

NAME             DESIRED   CURRENT   READY   AGE
day-7d4f9c8b5f   0         0         0       10m    ← Old (kept for rollback)
day-8f5a3c9d2e   2         2         2       1m     ← New (active)
```

### Rollback

```bash
# Undo last rollout
kubectl rollout undo deployment/day -n day-ns

# What happens:
# - Deployment controller scales up OLD ReplicaSet (day-7d4f9c8b5f)
# - Scales down NEW ReplicaSet (day-8f5a3c9d2e)
# - Same rolling update process, but in reverse!

# Rollback to specific revision
kubectl rollout history deployment/day -n day-ns
kubectl rollout undo deployment/day --to-revision=2 -n day-ns
```

---

## The Controller Reconciliation Loop

Let's look at how the ReplicaSet controller actually works.

### Simplified Controller Code

```python
from kubernetes import client, watch

def replicaset_controller():
    """Simplified ReplicaSet controller logic"""
    v1 = client.AppsV1Api()
    core_v1 = client.CoreV1Api()

    while True:
        # Get all ReplicaSets
        replicasets = v1.list_replica_set_for_all_namespaces()

        for rs in replicasets.items:
            reconcile_replicaset(rs, core_v1)

        time.sleep(5)  # Check every 5 seconds

def reconcile_replicaset(rs, api):
    """Ensure actual state matches desired state"""
    namespace = rs.metadata.namespace
    desired_replicas = rs.spec.replicas
    selector = rs.spec.selector.match_labels

    # Get current pods matching selector
    label_selector = ",".join(f"{k}={v}" for k, v in selector.items())
    pods = api.list_namespaced_pod(
        namespace=namespace,
        label_selector=label_selector
    )

    # Count running/pending pods
    current_replicas = len([
        p for p in pods.items
        if p.status.phase in ['Running', 'Pending']
    ])

    # Reconcile
    if current_replicas < desired_replicas:
        # Need more pods
        diff = desired_replicas - current_replicas
        for i in range(diff):
            create_pod_from_template(rs, api)

    elif current_replicas > desired_replicas:
        # Too many pods
        diff = current_replicas - desired_replicas
        # Delete oldest pods
        pods_to_delete = sorted(
            pods.items,
            key=lambda p: p.metadata.creation_timestamp
        )[:diff]
        for pod in pods_to_delete:
            api.delete_namespaced_pod(
                name=pod.metadata.name,
                namespace=namespace
            )

    # Update ReplicaSet status
    update_replicaset_status(rs, current_replicas, api)

def create_pod_from_template(rs, api):
    """Create a pod from ReplicaSet template"""
    pod = client.V1Pod(
        metadata=client.V1ObjectMeta(
            generate_name=f"{rs.metadata.name}-",  # Adds random suffix
            namespace=rs.metadata.namespace,
            labels=rs.spec.template.metadata.labels,
            owner_references=[
                client.V1OwnerReference(
                    api_version=rs.api_version,
                    kind=rs.kind,
                    name=rs.metadata.name,
                    uid=rs.metadata.uid,
                    controller=True,
                    block_owner_deletion=True
                )
            ]
        ),
        spec=rs.spec.template.spec
    )

    api.create_namespaced_pod(
        namespace=rs.metadata.namespace,
        body=pod
    )
```

### Key Concepts

**Level-triggered, not edge-triggered:**
- Controllers don't react to events
- They continuously check "is actual state correct?"
- If network issues cause them to miss an event, they'll catch it on the next loop

**Idempotent operations:**
- Creating a pod that already exists → no-op
- Deleting a pod that doesn't exist → no-op
- Controllers can safely retry operations

**Eventually consistent:**
- System might be in intermediate state temporarily
- Controllers will keep working until desired state is reached

---

## Hands-On Examples

### Example 1: Create and Observe

```bash
# Apply deployment
kubectl apply -f foundation/gitops/manual_deploy/day/prod/deployment.yaml

# Watch resources being created
watch kubectl get deployment,rs,pod -n day-ns

# See the creation sequence:
# 1. Deployment appears
# 2. ReplicaSet appears
# 3. Pods appear

# Check ownership
kubectl get rs -n day-ns -o yaml | grep -A 5 ownerReferences
kubectl get pod -n day-ns -o yaml | grep -A 5 ownerReferences
```

### Example 2: Test Self-Healing

```bash
# Get current pods
kubectl get pods -n day-ns

# Delete one pod
kubectl delete pod <pod-name> -n day-ns

# Immediately check again
kubectl get pods -n day-ns

# You'll see:
# - Old pod in Terminating state
# - New pod in ContainerCreating state
# - Within 30s, new pod is Running
```

### Example 3: Scale Up and Down

```bash
# Scale up
kubectl scale deployment day --replicas=5 -n day-ns

# Watch pods being created
kubectl get pods -n day-ns -w

# Scale down
kubectl scale deployment day --replicas=2 -n day-ns

# Watch pods being terminated (oldest first)
kubectl get pods -n day-ns -w
```

### Example 4: Rolling Update

```bash
# Make a change
kubectl set image deployment/day day=day:v2 -n day-ns

# Watch the rollout
kubectl rollout status deployment/day -n day-ns

# See both ReplicaSets
kubectl get rs -n day-ns

# See rollout history
kubectl rollout history deployment/day -n day-ns

# Rollback
kubectl rollout undo deployment/day -n day-ns
```

### Example 5: Describe the Hierarchy

```bash
# Describe deployment (see events)
kubectl describe deployment day -n day-ns

# Find ReplicaSet name
RS_NAME=$(kubectl get rs -n day-ns --selector=app=day -o jsonpath='{.items[0].metadata.name}')

# Describe ReplicaSet
kubectl describe rs $RS_NAME -n day-ns

# Get a pod
POD_NAME=$(kubectl get pods -n day-ns --selector=app=day -o jsonpath='{.items[0].metadata.name}')

# Describe pod
kubectl describe pod $POD_NAME -n day-ns

# See the full chain
echo "Deployment → $RS_NAME → $POD_NAME"
```

---

## Common Patterns and Best Practices

### 1. Always Use Deployments for Stateless Apps

```yaml
# ✓ GOOD
apiVersion: apps/v1
kind: Deployment
spec:
  replicas: 3

# ✗ BAD (never create pods directly)
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
```

**Why:** Deployments provide:
- Self-healing (dead pods are replaced)
- Scaling
- Rolling updates
- Rollback capability

### 2. Set Resource Requests and Limits

```yaml
# From foundation/gitops/manual_deploy/day/prod/deployment.yaml
resources:
  requests:
    cpu: 50m        # Guaranteed CPU
    memory: 64Mi    # Guaranteed memory
  limits:
    cpu: 200m       # Max CPU (throttled if exceeded)
    memory: 256Mi   # Max memory (killed if exceeded)
```

**Why:**
- Scheduler can make intelligent placement decisions
- Prevents one pod from starving others
- Enables Horizontal Pod Autoscaler

### 3. Use Health Probes

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8001
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /health
    port: 8001
  initialDelaySeconds: 10
  periodSeconds: 5
```

**Difference:**
- **Liveness:** If fails, pod is restarted
- **Readiness:** If fails, pod is removed from Service (no traffic)

### 4. Use Rolling Update Strategy

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1           # Max extra pods during update
    maxUnavailable: 0     # Min pods that must stay available
```

**Ensures:** Zero-downtime deployments

### 5. Label Everything Consistently

```yaml
metadata:
  labels:
    app: day
    tier: backend
    environment: production
    version: v1.2.3
```

**Why:**
- Easy to query: `kubectl get pods -l app=day,environment=production`
- Services use selectors to find pods
- Helps with monitoring and logging

### 6. Use Namespaces for Isolation

```yaml
# Production
namespace: day-ns

# RC (Release Candidate)
namespace: day-rc-ns
```

**Why:**
- Separate environments in same cluster
- Resource quotas per namespace
- RBAC per namespace

---

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n day-ns

# Describe pod for events
kubectl describe pod <pod-name> -n day-ns

# Common issues:
# - ImagePullBackOff: Can't pull container image
# - CrashLoopBackOff: Container keeps crashing
# - Pending: Can't be scheduled (insufficient resources)
```

**Solutions:**
```bash
# Check pod events
kubectl get events -n day-ns --sort-by='.lastTimestamp'

# Check pod logs
kubectl logs <pod-name> -n day-ns

# Check previous container logs (if restarting)
kubectl logs <pod-name> -n day-ns --previous

# Get detailed pod info
kubectl get pod <pod-name> -n day-ns -o yaml
```

### ReplicaSet Not Creating Pods

```bash
# Check ReplicaSet
kubectl describe rs <rs-name> -n day-ns

# Look for events like:
# - "Error creating pod: ..."
# - Resource quota exceeded
# - Invalid image name
```

### Deployment Not Creating ReplicaSet

```bash
# Check deployment
kubectl describe deployment day -n day-ns

# Common issues:
# - Invalid selector (doesn't match template labels)
# - Invalid template spec
```

**Example of invalid selector:**
```yaml
# ✗ BAD
spec:
  selector:
    matchLabels:
      app: day
  template:
    metadata:
      labels:
        app: different-label  # ← Doesn't match!
```

### Rolling Update Stuck

```bash
# Check rollout status
kubectl rollout status deployment/day -n day-ns

# Check what's wrong
kubectl describe deployment day -n day-ns

# Common issues:
# - New pods failing readiness probes
# - Insufficient resources for surge pods
# - Image doesn't exist

# Pause rollout to investigate
kubectl rollout pause deployment/day -n day-ns

# Resume when ready
kubectl rollout resume deployment/day -n day-ns

# Or rollback
kubectl rollout undo deployment/day -n day-ns
```

### Debugging the Controller

```bash
# Check controller manager logs (contains Deployment and ReplicaSet controllers)
kubectl logs -n kube-system kube-controller-manager-<node> | grep -i deployment

# On managed K8s (EKS, GKE, AKS), you can't access controller logs
# Instead, look at resource events:
kubectl get events -n day-ns --field-selector involvedObject.kind=Deployment
kubectl get events -n day-ns --field-selector involvedObject.kind=ReplicaSet
```

---

## Summary

### The Answer to "How Are Pods Created?"

1. You create a **Deployment** (declarative)
2. **Deployment controller** creates a **ReplicaSet** (automatic)
3. **ReplicaSet controller** creates **Pods** (automatic)
4. **Scheduler** assigns Pods to **Nodes** (automatic)
5. **Kubelet** starts containers (automatic)

### Key Takeaways

- **You control:** Deployment spec
- **Kubernetes controls:** Everything else
- **Self-healing:** If pods die, they're automatically replaced
- **Declarative:** You declare desired state, controllers make it happen
- **Layered:** Each layer has a specific responsibility
- **Auditable:** Owner references create a clear hierarchy

### The Power of Abstraction

```
You think:     "I want 2 replicas of my app"
You write:     Deployment YAML
Kubernetes:    Handles ReplicaSets, Pods, scheduling, health checks,
               networking, storage, restarts, updates, rollbacks...
```

This is why Kubernetes is powerful - you focus on **what** you want, not **how** to achieve it.

---

## Further Reading

- [Kubernetes Documentation: Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Kubernetes Documentation: ReplicaSets](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)
- [Kubernetes Documentation: Pods](https://kubernetes.io/docs/concepts/workloads/pods/)
- [Understanding Kubernetes Controllers](https://kubernetes.io/docs/concepts/architecture/controller/)
- [The Kubernetes Control Plane](https://kubernetes.io/docs/concepts/overview/components/#control-plane-components)

---

**Related files in this repository:**
- `foundation/gitops/manual_deploy/day/prod/deployment.yaml` - Example Deployment
- `foundation/gitops/manual_deploy/day/prod/service.yaml` - Service that routes to pods
- `foundation/gitops/manual_deploy/day/prod/ingress.yaml` - External access via ALB
- `foundation/scripts/explore/explore-deployment-hierarchy.sh` - Interactive demonstration script
