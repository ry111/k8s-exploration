# How ConfigMaps Relate to Deployments, ReplicaSets, and Pods

## Table of Contents
- [Quick Answer](#quick-answer)
- [The Fundamental Difference: Ownership vs Reference](#the-fundamental-difference-ownership-vs-reference)
- [What is a ConfigMap?](#what-is-a-configmap)
- [How Each Resource Relates to ConfigMaps](#how-each-resource-relates-to-configmaps)
- [The Complete Relationship Diagram](#the-complete-relationship-diagram)
- [ConfigMap Reference Methods](#configmap-reference-methods)
- [Lifecycle and Dependencies](#lifecycle-and-dependencies)
- [The Critical Gotcha: Updates Don't Auto-Restart Pods](#the-critical-gotcha-updates-dont-auto-restart-pods)
- [ConfigMaps Can Be Shared](#configmaps-can-be-shared)
- [Your Use Case: Separate Configs for Prod and RC](#your-use-case-separate-configs-for-prod-and-rc)
- [How ConfigMap Data Becomes Environment Variables](#how-configmap-data-becomes-environment-variables)
- [Comparison: Ownership vs Reference](#comparison-ownership-vs-reference)
- [Best Practices](#best-practices)
- [Common Patterns](#common-patterns)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)

---

## Quick Answer

**ConfigMaps are REFERENCED by Pods, not created by them.**

This is fundamentally different from the Deployment→ReplicaSet→Pod ownership chain.

```
ConfigMap (standalone resource - exists independently)
    ↑ referenced by (not owned by)
Pod specification (in Deployment template)
    ↓ copied to
ReplicaSet pod template
    ↓ copied to
Pod (uses reference at runtime)
```

**Key insight:** ConfigMaps have no `ownerReferences` field. They exist independently and can be shared across multiple Deployments and Pods.

---

## The Fundamental Difference: Ownership vs Reference

### Ownership Chain (Deployment → ReplicaSet → Pod)

```
Deployment
    ↓ CREATES (and OWNS)
ReplicaSet
    ↓ CREATES (and OWNS)
Pod

• Parent creates child
• ownerReferences field present
• Deleting parent → deletes children (garbage collection)
• One-to-many (one Deployment → many ReplicaSets)
• Tightly coupled lifecycle
```

### Reference (Pod → ConfigMap)

```
Pod
    ↓ REFERENCES (does NOT own)
ConfigMap

• Child references parent
• No ownerReferences field
• Deleting Deployment → ConfigMap remains
• Many-to-one possible (many Pods → one ConfigMap)
• Loosely coupled lifecycle
```

---

## What is a ConfigMap?

**ConfigMap** is a Kubernetes resource that stores non-confidential configuration data as key-value pairs.

### Purpose

- Decouple configuration from container images
- Make containerized applications portable
- Allow different configs for different environments (dev/staging/prod)

### Example from This Repository

From `foundation/gitops/manual_deploy/day/prod/configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: day-config
  namespace: day-ns
  # NOTE: No ownerReferences field!
  # ConfigMaps are standalone resources
data:
  ENVIRONMENT: "production"
  PORT: "8001"
  LOG_LEVEL: "info"
  SERVICE_NAME: "Day"
```

**Characteristics:**
- ✅ Standalone resource (not created by Deployment)
- ✅ No owner (no `ownerReferences`)
- ✅ Can exist before Deployment is created
- ✅ Can be shared by multiple Deployments
- ✅ Can be updated independently
- ✅ Persists after Deployment is deleted

---

## How Each Resource Relates to ConfigMaps

### Deployment → ConfigMap: Indirect Reference (via Pod Template)

The Deployment itself doesn't directly "know about" ConfigMaps. The pod template within the Deployment spec contains the reference.

From `foundation/gitops/manual_deploy/day/prod/deployment.yaml:25-27`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: day
spec:
  template:  # Pod template
    spec:
      containers:
      - name: day
        envFrom:
        - configMapRef:
            name: day-config  # ← REFERENCE to ConfigMap
```

**What the Deployment does:**
- Defines a pod template that references a ConfigMap
- Does NOT create the ConfigMap
- Does NOT own the ConfigMap
- Does NOT validate that the ConfigMap exists (at Deployment creation time)

**Analogy:** The Deployment is like a blueprint that says *"when you build pods, use config from day-config"* — but it doesn't create that config.

### ReplicaSet → ConfigMap: Copied Reference

When the Deployment controller creates a ReplicaSet, it copies the entire pod template, including the ConfigMap reference.

**Auto-generated ReplicaSet:**

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: day-7d4f9c8b5f
  ownerReferences:
  - kind: Deployment
    name: day  # ← Owned by Deployment
spec:
  template:
    spec:
      containers:
      - name: day
        envFrom:
        - configMapRef:
            name: day-config  # ← Same reference copied
```

**What the ReplicaSet does:**
- Stores the same pod template as Deployment
- Does NOT create the ConfigMap
- Does NOT own the ConfigMap
- Passes the reference to Pods it creates

**Analogy:** The ReplicaSet is like a copy machine that duplicates the blueprint, including the note that says *"use day-config"*.

### Pod → ConfigMap: Runtime Reference

Pods are what actually **use** ConfigMaps at runtime.

**Auto-generated Pod:**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: day-7d4f9c8b5f-abc12
  ownerReferences:
  - kind: ReplicaSet
    name: day-7d4f9c8b5f  # ← Owned by ReplicaSet
spec:
  containers:
  - name: day
    envFrom:
    - configMapRef:
        name: day-config  # ← References ConfigMap
```

**What happens at Pod startup:**

1. **Scheduler** assigns Pod to a Node
2. **Kubelet** (on that Node) sees the Pod spec
3. Kubelet reads `configMapRef: day-config`
4. Kubelet **fetches ConfigMap data** from API server
5. If ConfigMap doesn't exist → Pod fails: `CreateContainerConfigError`
6. If ConfigMap exists → Kubelet injects data as environment variables
7. Kubelet starts the container with those env vars

**Analogy:** The Pod is the construction worker who actually goes to the config store and retrieves the values before building the house.

---

## The Complete Relationship Diagram

```
┌─────────────────────────────────────────────────────────┐
│ ConfigMap: day-config                                   │
│ • Standalone resource                                   │
│ • Created independently (kubectl apply -f)              │
│ • No ownerReferences                                    │
│ • Can be shared across multiple Deployments             │
│ • Lifecycle independent of Deployment                   │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ referenced by (not owned by)
                     │
                     ↓
┌─────────────────────────────────────────────────────────┐
│ Deployment: day                                         │
│ • Pod template contains: configMapRef: day-config       │
│ • Does NOT create ConfigMap                             │
│ • Does NOT own ConfigMap                                │
│ • Passes reference to ReplicaSet                        │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ creates & owns
                     │
                     ↓
┌─────────────────────────────────────────────────────────┐
│ ReplicaSet: day-7d4f9c8b5f                              │
│ • ownerReferences → Deployment                          │
│ • Pod template contains: configMapRef: day-config       │
│ • Does NOT create ConfigMap                             │
│ • Does NOT own ConfigMap                                │
│ • Passes reference to Pods                              │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ creates & owns
                     │
                     ↓
┌─────────────────────────────────────────────────────────┐
│ Pod: day-7d4f9c8b5f-abc12                               │
│ • ownerReferences → ReplicaSet                          │
│ • Spec contains: configMapRef: day-config               │
│ • Does NOT own ConfigMap                                │
│ • Kubelet USES ConfigMap at container startup           │
└─────────────────────────────────────────────────────────┘
```

### Comparison with Secrets

ConfigMaps work exactly the same way as **Secrets** (but Secrets are for sensitive data).

```
ConfigMap/Secret (standalone)
    ↑ referenced by
Pod spec
```

Both are reference relationships, not ownership relationships.

---

## ConfigMap Reference Methods

There are three ways to use ConfigMaps in Pods:

### Method 1: All Keys as Environment Variables (Your Current Setup)

From `foundation/gitops/manual_deploy/day/prod/deployment.yaml:25-27`:

```yaml
envFrom:
- configMapRef:
    name: day-config
```

**Result:** All keys in ConfigMap become environment variables

```bash
# Inside container
echo $ENVIRONMENT  # "production"
echo $PORT         # "8001"
echo $LOG_LEVEL    # "info"
echo $SERVICE_NAME # "Day"
```

**Pros:**
- Simple, inject all config at once
- Easy to use in applications

**Cons:**
- All keys are injected (can't be selective)
- Key names become env var names (must be valid env var names)

### Method 2: Specific Keys as Environment Variables

```yaml
env:
- name: APP_PORT          # Environment variable name
  valueFrom:
    configMapKeyRef:
      name: day-config    # ConfigMap name
      key: PORT           # Key in ConfigMap
- name: APP_LOG_LEVEL
  valueFrom:
    configMapKeyRef:
      name: day-config
      key: LOG_LEVEL
```

**Result:** Only selected keys, with custom env var names

```bash
# Inside container
echo $APP_PORT       # "8001"
echo $APP_LOG_LEVEL  # "info"
```

**Pros:**
- Selective (only what you need)
- Can rename env vars
- Can mix ConfigMap keys with other sources

**Cons:**
- More verbose
- Need to list each key individually

### Method 3: Mount as Files (Volume)

```yaml
volumes:
- name: config-volume
  configMap:
    name: day-config

containers:
- name: day
  volumeMounts:
  - name: config-volume
    mountPath: /etc/config
    readOnly: true
```

**Result:** Each key becomes a file

```bash
# Inside container
ls /etc/config/
# ENVIRONMENT  PORT  LOG_LEVEL  SERVICE_NAME

cat /etc/config/ENVIRONMENT
# production

cat /etc/config/PORT
# 8001
```

**Pros:**
- Supports large config files (JSON, XML, etc.)
- Updates propagate to running pods (within ~60s)
- Can make files read-only

**Cons:**
- Apps need to read files instead of env vars
- Slightly more complex

### Method 4: Specific Files from ConfigMap

```yaml
volumes:
- name: config-volume
  configMap:
    name: day-config
    items:
    - key: LOG_LEVEL
      path: app/log-level.txt  # Custom filename/path
    - key: PORT
      path: app/port.txt

containers:
- name: day
  volumeMounts:
  - name: config-volume
    mountPath: /etc/config
```

**Result:**

```bash
ls /etc/config/app/
# log-level.txt  port.txt

cat /etc/config/app/log-level.txt
# info
```

---

## Lifecycle and Dependencies

### Creation Order Matters

#### Correct Order

```bash
# 1. Create ConfigMap first
kubectl apply -f foundation/gitops/manual_deploy/day/prod/configmap.yaml

# 2. Create Deployment
kubectl apply -f foundation/gitops/manual_deploy/day/prod/deployment.yaml
```

**What happens:**
```
T+0s:  ConfigMap created
T+1s:  Deployment created
       → Deployment creates ReplicaSet
       → ReplicaSet creates Pods
       → Kubelet fetches ConfigMap (exists! ✓)
       → Container starts successfully
```

#### Wrong Order

```bash
# 1. Create Deployment first (ConfigMap doesn't exist)
kubectl apply -f foundation/gitops/manual_deploy/day/prod/deployment.yaml

# 2. Create ConfigMap
kubectl apply -f foundation/gitops/manual_deploy/day/prod/configmap.yaml
```

**What happens:**
```
T+0s:  Deployment created
       → Deployment creates ReplicaSet
       → ReplicaSet creates Pods
       → Kubelet tries to fetch ConfigMap... NOT FOUND!
       → Pod status: CreateContainerConfigError

T+10s: ConfigMap created
       → Existing pods DON'T auto-recover!
       → You must restart them manually
```

**Fix:**
```bash
kubectl rollout restart deployment day -n day-ns
# Or
kubectl delete pods -l app=day -n day-ns
```

### Deletion Order

#### Safe Deletion

```bash
# 1. Delete Deployment first
kubectl delete deployment day -n day-ns
# Pods are terminated gracefully

# 2. Delete ConfigMap
kubectl delete configmap day-config -n day-ns
# ConfigMap deleted (no longer needed)
```

#### Dangerous Deletion

```bash
# 1. Delete ConfigMap while Pods are running
kubectl delete configmap day-config -n day-ns

# Existing pods continue running (they already have env vars)
# BUT if a pod restarts, it will fail!

kubectl delete pod day-7d4f9c8b5f-abc12 -n day-ns
# ReplicaSet creates replacement pod...
# New pod fails: CreateContainerConfigError (ConfigMap not found)
```

**Lesson:** Don't delete ConfigMaps while Deployments are still using them!

### Updating ConfigMap Lifecycle

```
1. ConfigMap exists: LOG_LEVEL=info
2. Pods running with LOG_LEVEL=info
3. Update ConfigMap: LOG_LEVEL=debug
4. Pods STILL running with LOG_LEVEL=info (not updated!)
5. Restart Deployment
6. New pods get LOG_LEVEL=debug
7. Old pods terminated
```

---

## The Critical Gotcha: Updates Don't Auto-Restart Pods

**This is one of the most common Kubernetes gotchas!**

### Scenario

```bash
# Initial state
kubectl get configmap day-config -n day-ns -o yaml
# data:
#   LOG_LEVEL: "info"

kubectl exec day-7d4f9c8b5f-abc12 -n day-ns -- env | grep LOG_LEVEL
# LOG_LEVEL=info  ✓

# Update ConfigMap
kubectl patch configmap day-config -n day-ns \
  --type merge \
  -p '{"data":{"LOG_LEVEL":"debug"}}'

# ConfigMap updated successfully
kubectl get configmap day-config -n day-ns -o yaml
# data:
#   LOG_LEVEL: "debug"  ✓

# Check running pod
kubectl exec day-7d4f9c8b5f-abc12 -n day-ns -- env | grep LOG_LEVEL
# LOG_LEVEL=info  ← STILL THE OLD VALUE!
```

### Why?

**Environment variables are injected when the container starts.**

1. Pod starts
2. Kubelet reads ConfigMap
3. Kubelet sets env vars: `LOG_LEVEL=info`
4. Container starts with those env vars
5. ConfigMap updated to `LOG_LEVEL=debug`
6. Pod keeps running with old env vars (`LOG_LEVEL=info`)

**The environment variables don't magically update!**

### Solutions

#### Solution 1: Restart the Deployment (Recommended)

```bash
kubectl rollout restart deployment day -n day-ns
```

**What happens:**
- Creates new ReplicaSet with updated pod template hash
- Gradually creates new pods (which read updated ConfigMap)
- Gradually terminates old pods
- Zero-downtime rolling update

#### Solution 2: Delete Pods Manually

```bash
kubectl delete pods -l app=day -n day-ns
```

**What happens:**
- All pods terminated immediately
- ReplicaSet creates new pods
- New pods read updated ConfigMap
- Brief downtime

#### Solution 3: Use ConfigMap Versions

```yaml
# Create new ConfigMap version
apiVersion: v1
kind: ConfigMap
metadata:
  name: day-config-v2  # ← New name
data:
  LOG_LEVEL: "debug"
---
# Update Deployment to reference new ConfigMap
spec:
  template:
    spec:
      containers:
      - envFrom:
        - configMapRef:
            name: day-config-v2  # ← Updated reference
```

**What happens:**
- Deployment detects pod template change
- Automatic rolling update triggered
- New pods use new ConfigMap
- Old ConfigMap remains for rollback

**Pros:**
- Automatic rollout
- Built-in rollback capability
- Clear version history

**Cons:**
- ConfigMaps accumulate (need cleanup)
- More complex

#### Solution 4: Use Volume Mounts (for file-based config)

```yaml
volumes:
- name: config-volume
  configMap:
    name: day-config

containers:
- volumeMounts:
  - name: config-volume
    mountPath: /etc/config
```

**Behavior:**
- ConfigMap updates propagate to mounted files
- Typically within 60 seconds (kubelet sync period)
- App must watch files for changes and reload

**Pros:**
- Updates propagate automatically
- No pod restart needed

**Cons:**
- Only works for file-based config (not env vars)
- App must support config reloading
- Eventual consistency (delay of ~60s)

---

## ConfigMaps Can Be Shared

Unlike ownership (one parent, one or more children), **many resources can reference the same ConfigMap**.

### Example: Shared Database Config

```yaml
# One ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: database-config
  namespace: default
data:
  DB_HOST: "postgres.example.com"
  DB_PORT: "5432"
  DB_NAME: "myapp"
---
# Frontend Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  template:
    spec:
      containers:
      - name: frontend
        envFrom:
        - configMapRef:
            name: database-config  # ← References shared ConfigMap
---
# Backend Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
spec:
  template:
    spec:
      containers:
      - name: backend
        envFrom:
        - configMapRef:
            name: database-config  # ← Same ConfigMap
---
# Worker Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker
spec:
  template:
    spec:
      containers:
      - name: worker
        envFrom:
        - configMapRef:
            name: database-config  # ← Same ConfigMap
```

**Relationship:**

```
database-config (one ConfigMap)
    ↑ ↑ ↑
    │ │ └─ referenced by worker pods
    │ └─── referenced by backend pods
    └───── referenced by frontend pods
```

**Benefits:**
- DRY (Don't Repeat Yourself)
- Update once, affects all deployments
- Consistent configuration

**Risks:**
- Update breaks all deployments if wrong
- Need to restart all deployments after update

---

## Your Use Case: Separate Configs for Prod and RC

Looking at your repository structure:

### Production Configuration

`foundation/gitops/manual_deploy/day/prod/configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: day-config
  namespace: day-ns
data:
  ENVIRONMENT: "production"
  PORT: "8001"
  LOG_LEVEL: "info"  # Less verbose
  SERVICE_NAME: "Day"
```

`foundation/gitops/manual_deploy/day/prod/deployment.yaml`:

```yaml
metadata:
  name: day
  namespace: day-ns
spec:
  template:
    spec:
      containers:
      - envFrom:
        - configMapRef:
            name: day-config  # ← References production config
```

### RC (Release Candidate) Configuration

`foundation/gitops/manual_deploy/day/rc/configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: day-rc-config
  namespace: day-rc-ns
data:
  ENVIRONMENT: "rc"
  PORT: "8001"
  LOG_LEVEL: "debug"  # More verbose for testing
  SERVICE_NAME: "Day-RC"
```

`foundation/gitops/manual_deploy/day/rc/deployment.yaml`:

```yaml
metadata:
  name: day-rc
  namespace: day-rc-ns
spec:
  template:
    spec:
      containers:
      - envFrom:
        - configMapRef:
            name: day-rc-config  # ← References RC config
```

### Visual Representation

```
┌──────────────────┐         ┌──────────────────┐
│ day-config       │         │ day-rc-config    │
│ (production)     │         │ (rc)             │
│                  │         │                  │
│ ENVIRONMENT:     │         │ ENVIRONMENT:     │
│   production     │         │   rc             │
│ LOG_LEVEL: info  │         │ LOG_LEVEL: debug │
└────────┬─────────┘         └────────┬─────────┘
         │                            │
         │ referenced by              │ referenced by
         ↓                            ↓
┌──────────────────┐         ┌──────────────────┐
│ Deployment: day  │         │ Deployment:      │
│ namespace:       │         │   day-rc         │
│   day-ns         │         │ namespace:       │
│ replicas: 2      │         │   day-rc-ns      │
│                  │         │ replicas: 1      │
└────────┬─────────┘         └────────┬─────────┘
         │                            │
         ↓                            ↓
   Production pods              RC pods
   LOG_LEVEL=info              LOG_LEVEL=debug
```

### Why This Pattern Works Well

1. **Namespace Isolation:**
   - Prod and RC are in separate namespaces
   - Pods in `day-ns` cannot accidentally reference `day-rc-config`
   - Network policies can further isolate them

2. **Different Configurations:**
   - Production: `LOG_LEVEL=info` (less noise)
   - RC: `LOG_LEVEL=debug` (more detail for testing)

3. **Same Application Code:**
   - Both use `image: day:latest` (or different tags)
   - Configuration determines behavior
   - Easy to test RC before promoting to prod

4. **Independent Lifecycles:**
   - Update RC config without affecting production
   - Test changes in RC
   - Promote to production by updating production ConfigMap

---

## How ConfigMap Data Becomes Environment Variables

Let's trace the complete flow from ConfigMap creation to environment variables in the container.

### Step 1: ConfigMap Exists

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: day-config
  namespace: day-ns
data:
  ENVIRONMENT: "production"
  PORT: "8001"
  LOG_LEVEL: "info"
  SERVICE_NAME: "Day"
```

Stored in etcd as a resource in the API server.

### Step 2: Deployment References ConfigMap

```yaml
spec:
  template:
    spec:
      containers:
      - name: day
        envFrom:
        - configMapRef:
            name: day-config  # ← Reference
```

### Step 3: Deployment Creates ReplicaSet

ReplicaSet gets the same pod template (including ConfigMap reference).

### Step 4: ReplicaSet Creates Pod

Pod spec includes:

```yaml
spec:
  containers:
  - name: day
    envFrom:
    - configMapRef:
        name: day-config
```

### Step 5: Scheduler Assigns Pod to Node

```yaml
spec:
  nodeName: ip-10-0-1-123  # Added by scheduler
```

### Step 6: Kubelet Processes Pod Spec

**Kubelet on node `ip-10-0-1-123`:**

1. Sees new pod assigned to this node
2. Reads pod spec
3. Finds `configMapRef: day-config`
4. Calls API server: `GET /api/v1/namespaces/day-ns/configmaps/day-config`
5. API server returns ConfigMap data:
   ```json
   {
     "data": {
       "ENVIRONMENT": "production",
       "PORT": "8001",
       "LOG_LEVEL": "info",
       "SERVICE_NAME": "Day"
     }
   }
   ```
6. Kubelet converts to environment variables:
   ```bash
   ENVIRONMENT=production
   PORT=8001
   LOG_LEVEL=info
   SERVICE_NAME=Day
   ```

### Step 7: Container Runtime Starts Container

Kubelet calls container runtime (containerd/Docker) with:

```bash
docker run \
  -e ENVIRONMENT=production \
  -e PORT=8001 \
  -e LOG_LEVEL=info \
  -e SERVICE_NAME=Day \
  day:latest
```

### Step 8: Application Reads Environment Variables

Inside the container, application code:

```python
import os

environment = os.getenv('ENVIRONMENT')  # "production"
port = int(os.getenv('PORT'))           # 8001
log_level = os.getenv('LOG_LEVEL')     # "info"
service_name = os.getenv('SERVICE_NAME') # "Day"
```

### Complete Flow Diagram

```
┌─────────────────────────────────────────────┐
│ 1. ConfigMap stored in etcd                 │
│    Key: ENVIRONMENT, Value: "production"    │
└──────────────────┬──────────────────────────┘
                   │
                   │ API Server
                   ↓
┌─────────────────────────────────────────────┐
│ 2. Deployment pod template references       │
│    configMapRef: day-config                 │
└──────────────────┬──────────────────────────┘
                   │
                   │ Deployment Controller
                   ↓
┌─────────────────────────────────────────────┐
│ 3. ReplicaSet copies reference              │
└──────────────────┬──────────────────────────┘
                   │
                   │ ReplicaSet Controller
                   ↓
┌─────────────────────────────────────────────┐
│ 4. Pod spec includes configMapRef           │
└──────────────────┬──────────────────────────┘
                   │
                   │ Scheduler
                   ↓
┌─────────────────────────────────────────────┐
│ 5. Pod assigned to Node                     │
└──────────────────┬──────────────────────────┘
                   │
                   │ Kubelet
                   ↓
┌─────────────────────────────────────────────┐
│ 6. Kubelet fetches ConfigMap from API       │
│    GET /configmaps/day-config               │
│    Response: {ENVIRONMENT: "production"}    │
└──────────────────┬──────────────────────────┘
                   │
                   │ Kubelet
                   ↓
┌─────────────────────────────────────────────┐
│ 7. Kubelet calls container runtime          │
│    docker run -e ENVIRONMENT=production ... │
└──────────────────┬──────────────────────────┘
                   │
                   │ Container Runtime
                   ↓
┌─────────────────────────────────────────────┐
│ 8. Container starts with env vars           │
│    os.getenv('ENVIRONMENT') → "production"  │
└─────────────────────────────────────────────┘
```

---

## Comparison: Ownership vs Reference

| Aspect | Deployment→ReplicaSet→Pod | Pod→ConfigMap |
|--------|---------------------------|---------------|
| **Relationship Type** | Ownership (parent-child) | Reference (consumer-provider) |
| **Direction** | Parent creates child | Child references parent |
| **ownerReferences** | ✓ Yes (child has it) | ✗ No |
| **Garbage Collection** | Deleting parent → deletes children | Deleting ConfigMap → pods unaffected |
| **Creation Order** | Parent must exist first | ConfigMap should exist first |
| **Sharing** | One parent per child | Multiple consumers per ConfigMap |
| **Lifecycle Coupling** | Tightly coupled | Loosely coupled |
| **Updates** | Deployment update → new ReplicaSet | ConfigMap update → manual restart |
| **Visibility** | `kubectl get deployment,rs,pod` shows hierarchy | No hierarchy; separate resources |
| **Dependency** | Automatic (controller creates) | Manual (must reference by name) |
| **Namespace** | Child inherits parent namespace | Must be in same namespace |

---

## Best Practices

### 1. Create ConfigMaps Before Deployments

```bash
# ✓ GOOD
kubectl apply -f configmap.yaml
kubectl apply -f deployment.yaml

# ✗ BAD
kubectl apply -f deployment.yaml  # Pods will fail!
kubectl apply -f configmap.yaml   # Pods won't auto-recover
```

**Tool support:**
```yaml
# kustomization.yaml enforces order
resources:
- configmap.yaml
- deployment.yaml  # Applied after configmap
```

### 2. Use Namespaces for Environment Isolation

```yaml
# Production
namespace: day-ns
configMap: day-config

# RC
namespace: day-rc-ns
configMap: day-rc-config

# Development
namespace: day-dev-ns
configMap: day-dev-config
```

**Benefit:** Cannot accidentally use wrong config (namespace boundary).

### 3. Version ConfigMaps for Safe Updates

```yaml
# Instead of updating day-config
apiVersion: v1
kind: ConfigMap
metadata:
  name: day-config-v2  # ← New version
data:
  LOG_LEVEL: "debug"
---
# Update Deployment
spec:
  template:
    spec:
      containers:
      - envFrom:
        - configMapRef:
            name: day-config-v2  # ← Reference new version
```

**Benefits:**
- Deployment update triggers automatic rollout
- Easy rollback: revert to `day-config`
- Old ConfigMap preserved

**Cleanup:**
```bash
# Delete old ConfigMaps after successful rollout
kubectl delete configmap day-config day-config-v1 -n day-ns
```

### 4. Use Immutable ConfigMaps (Kubernetes 1.19+)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: day-config
immutable: true  # ← Cannot be modified
data:
  PORT: "8001"
```

**Benefits:**
- Prevents accidental changes
- Better performance (kubelet doesn't watch for changes)
- Forces versioning pattern (create new ConfigMap for changes)

**Limitations:**
- Cannot edit (must delete and recreate)
- Only for config that shouldn't change

### 5. Document ConfigMap Dependencies

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: day
  annotations:
    configmaps: "day-config"  # ← Document dependencies
    secrets: "day-secrets"
```

Or use labels:

```yaml
metadata:
  labels:
    app: day
    config: day-config
```

### 6. Validate ConfigMaps Exist Before Deployment

```bash
# Pre-deployment check script
#!/bin/bash
NAMESPACE="day-ns"
CONFIGMAP="day-config"

if ! kubectl get configmap $CONFIGMAP -n $NAMESPACE &>/dev/null; then
    echo "Error: ConfigMap $CONFIGMAP not found in namespace $NAMESPACE"
    exit 1
fi

kubectl apply -f deployment.yaml
```

### 7. Use ConfigMaps for Environment-Specific Config Only

**ConfigMaps should contain:**
- ✓ Environment variables
- ✓ Configuration files
- ✓ Non-sensitive data

**ConfigMaps should NOT contain:**
- ✗ Secrets (passwords, API keys) → use Secrets instead
- ✗ Large binary data (>1MB) → use volumes
- ✗ Application code → use containers

### 8. Separate Shared vs App-Specific ConfigMaps

```yaml
# Shared ConfigMap (used by multiple deployments)
apiVersion: v1
kind: ConfigMap
metadata:
  name: shared-config
  labels:
    scope: shared
data:
  DB_HOST: "postgres.example.com"
---
# App-specific ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: day-config
  labels:
    scope: app-specific
    app: day
data:
  SERVICE_NAME: "Day"
```

---

## Common Patterns

### Pattern 1: Base + Override ConfigMaps

```yaml
# Base configuration (shared)
apiVersion: v1
kind: ConfigMap
metadata:
  name: base-config
data:
  PORT: "8000"
  TIMEOUT: "30"
---
# Environment-specific overrides
apiVersion: v1
kind: ConfigMap
metadata:
  name: prod-config
data:
  LOG_LEVEL: "info"
  REPLICAS: "5"
---
# Deployment uses both
spec:
  template:
    spec:
      containers:
      - envFrom:
        - configMapRef:
            name: base-config
        - configMapRef:
            name: prod-config  # Overrides base if keys conflict
```

### Pattern 2: ConfigMap Per Service Component

```yaml
# Database config
ConfigMap: database-config
# Cache config
ConfigMap: cache-config
# API config
ConfigMap: api-config

# Deployment references multiple
spec:
  containers:
  - envFrom:
    - configMapRef:
        name: database-config
    - configMapRef:
        name: cache-config
    - configMapRef:
        name: api-config
```

### Pattern 3: Git-Based ConfigMap Source of Truth

```bash
# Store ConfigMaps in Git
config/
  production/
    day-config.yaml
  rc/
    day-rc-config.yaml

# Deploy from Git
kubectl apply -f config/production/day-config.yaml
kubectl apply -f deployments/day.yaml
```

**Benefits:**
- Version control
- Code review for config changes
- Audit trail

---

## Troubleshooting

### Problem 1: Pod Status `CreateContainerConfigError`

```bash
kubectl get pods -n day-ns
NAME                   READY   STATUS                       RESTARTS   AGE
day-7d4f9c8b5f-abc12   0/1     CreateContainerConfigError   0          10s
```

**Cause:** Referenced ConfigMap doesn't exist

**Check:**
```bash
# Describe pod
kubectl describe pod day-7d4f9c8b5f-abc12 -n day-ns

# Events:
Events:
  Type     Reason     Message
  ----     ------     -------
  Warning  Failed     Error: configmap "day-config" not found
```

**Solution:**
```bash
# Create missing ConfigMap
kubectl apply -f foundation/k8s/day/prod/configmap.yaml

# Restart deployment to recreate pods
kubectl rollout restart deployment day -n day-ns
```

### Problem 2: Wrong Namespace

```bash
# ConfigMap in wrong namespace
kubectl get configmap day-config -n default  # Found here
kubectl get configmap day-config -n day-ns   # Not found

# Pod in day-ns tries to reference it
# Error: configmap "day-config" not found
```

**Solution:**
```bash
# Move ConfigMap to correct namespace
kubectl get configmap day-config -n default -o yaml | \
  sed 's/namespace: default/namespace: day-ns/' | \
  kubectl apply -f -

# Or recreate in correct namespace
kubectl delete configmap day-config -n default
kubectl apply -f foundation/k8s/day/prod/configmap.yaml
```

### Problem 3: ConfigMap Updated But Pods Have Old Values

```bash
# Updated ConfigMap
kubectl patch configmap day-config -n day-ns \
  --type merge -p '{"data":{"LOG_LEVEL":"debug"}}'

# But pods still have old value
kubectl exec day-7d4f9c8b5f-abc12 -n day-ns -- env | grep LOG_LEVEL
LOG_LEVEL=info  # ← Old value
```

**Cause:** Environment variables set at container startup

**Solution:**
```bash
kubectl rollout restart deployment day -n day-ns
```

### Problem 4: ConfigMap Too Large

```bash
# Error: ConfigMap exceeds maximum size
Error from server: configmap "large-config" is forbidden:
  size of ConfigMap data exceeds the maximum size of 1048576 bytes
```

**Cause:** ConfigMaps limited to 1 MB

**Solution:**
- Split into multiple ConfigMaps
- Use Secrets for sensitive data (same size limit)
- Store large files externally (S3, ConfigMap with URLs)
- Use init containers to download config

### Problem 5: Typo in ConfigMap Key

```yaml
# ConfigMap
data:
  LOG_LEVEL: "info"  # ← Correct key

# Deployment
env:
- name: LOG_LEVEL
  valueFrom:
    configMapKeyRef:
      name: day-config
      key: LOGLEVEL  # ← Typo! Should be LOG_LEVEL
```

**Result:** Pod fails to start

**Solution:**
```bash
# Check ConfigMap keys
kubectl get configmap day-config -n day-ns -o yaml

# Fix typo in deployment
kubectl edit deployment day -n day-ns
```

---

## Advanced Topics

### Using ConfigMaps with Init Containers

```yaml
spec:
  initContainers:
  - name: init-config
    image: busybox
    envFrom:
    - configMapRef:
        name: day-config
    command:
    - sh
    - -c
    - echo "Initializing with ENVIRONMENT=$ENVIRONMENT"
  containers:
  - name: day
    envFrom:
    - configMapRef:
        name: day-config
```

**Use case:** Pre-process config before app starts

### ConfigMap with Binary Data

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: binary-config
binaryData:
  cert.pem: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...  # Base64 encoded
```

### Watching ConfigMap Changes in Application

```python
# Python example using Kubernetes client
from kubernetes import client, watch

v1 = client.CoreV1Api()
w = watch.Watch()

for event in w.stream(v1.list_namespaced_config_map, namespace="day-ns"):
    configmap = event['object']
    if configmap.metadata.name == "day-config":
        print(f"ConfigMap changed: {event['type']}")
        # Reload application config
```

### ConfigMap Rollback with kubectl

```bash
# View rollout history
kubectl rollout history deployment day -n day-ns

# Rollout to previous version (which used old ConfigMap reference)
kubectl rollout undo deployment day -n day-ns
```

---

## Summary

### The Answer: How ConfigMaps Relate to Resources

**ConfigMaps:**
- Are **standalone resources** (not created by Deployments)
- Are **referenced** by Pods (not owned)
- Have **no `ownerReferences`**
- Can be **shared** by multiple Deployments
- Must **exist before** Pods that reference them start
- **Don't auto-update** running pods when changed

**Deployments:**
- Reference ConfigMaps in pod template
- Don't create or own ConfigMaps
- Pass references to ReplicaSets

**ReplicaSets:**
- Copy ConfigMap references from Deployment
- Don't create or own ConfigMaps
- Pass references to Pods

**Pods:**
- Actually **use** ConfigMaps at runtime
- Kubelet fetches ConfigMap data when starting containers
- Inject as environment variables or mount as files
- Don't own ConfigMaps

### Key Takeaways

1. **Ownership vs Reference:** ConfigMaps use reference relationship, not ownership
2. **Creation Order:** ConfigMaps must exist before Deployments
3. **No Auto-Update:** Updating ConfigMap requires manual pod restart
4. **Sharing:** One ConfigMap can be used by many Pods
5. **Namespace Boundary:** ConfigMaps can only be referenced within same namespace
6. **Lifecycle:** ConfigMaps persist after Deployment deletion

---

## Further Reading

- [Kubernetes Documentation: ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/)
- [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) (similar to ConfigMaps but for sensitive data)

---

**Related files in this repository:**
- `foundation/gitops/manual_deploy/day/prod/configmap.yaml` - Production ConfigMap
- `foundation/gitops/manual_deploy/day/rc/configmap.yaml` - RC ConfigMap
- `foundation/gitops/manual_deploy/day/prod/deployment.yaml` - Deployment referencing ConfigMap
- `deployment-hierarchy.md` - How Deployments create Pods
- `foundation/scripts/explore/explore-configmap-relationships.sh` - Interactive demonstration script
