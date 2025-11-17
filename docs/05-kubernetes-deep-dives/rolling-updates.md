# How Deployments Perform Rolling Updates

## Table of Contents
- [Quick Answer](#quick-answer)
- [The Key Insight: Multiple ReplicaSets](#the-key-insight-multiple-replicasets)
- [Why Not Update Existing ReplicaSets?](#why-not-update-existing-replicasets)
- [Step-by-Step Rolling Update Process](#step-by-step-rolling-update-process)
- [The Deployment Controller Algorithm](#the-deployment-controller-algorithm)
- [maxSurge and maxUnavailable Explained](#maxsurge-and-maxunavailable-explained)
- [What Happens to Pods](#what-happens-to-pods)
- [Rollback Mechanism](#rollback-mechanism)
- [Multiple Updates and Revision History](#multiple-updates-and-revision-history)
- [Update Strategies](#update-strategies)
- [Observing Rolling Updates](#observing-rolling-updates)
- [Real-World Example from This Repository](#real-world-example-from-this-repository)
- [The Complete State Machine](#the-complete-state-machine)
- [Common Scenarios and Edge Cases](#common-scenarios-and-edge-cases)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Quick Answer

**Deployments create a NEW ReplicaSet for each version change.**

They do NOT update existing ReplicaSets or Pods. The rolling update process:

1. **Create** new ReplicaSet with updated pod template
2. **Scale up** new ReplicaSet (creates new pods)
3. **Scale down** old ReplicaSet (deletes old pods)
4. **Repeat** until transition complete
5. **Keep** old ReplicaSet (at 0 replicas) for rollback

```
Deployment: day
    │
    ├─→ ReplicaSet: day-5d89b7c4f6 (old version)
    │       replicas: 2 → 1 → 0 (scaled down)
    │       status: kept for rollback
    │
    └─→ ReplicaSet: day-7f8c9d2e3a (new version)
            replicas: 0 → 1 → 2 (scaled up)
            status: active
```

---

## The Key Insight: Multiple ReplicaSets

### What Most People Think Happens

```
❌ WRONG: Update the existing ReplicaSet
Deployment updates ReplicaSet spec
    ↓
ReplicaSet recreates Pods with new image
```

### What Actually Happens

```
✓ CORRECT: Create a new ReplicaSet
Deployment creates NEW ReplicaSet
    ↓
Old ReplicaSet scaled down (2 → 1 → 0)
New ReplicaSet scaled up (0 → 1 → 2)
    ↓
Old ReplicaSet kept at 0 for rollback
```

### Visual Representation

**Before Update (v1):**
```
Deployment: day
    │
    └─→ ReplicaSet: day-5d89b7c4f6 (replicas: 2)
            ├─→ Pod: day-5d89b7c4f6-abc12 (image: day:v1)
            └─→ Pod: day-5d89b7c4f6-def34 (image: day:v1)
```

**During Update (v1 → v2):**
```
Deployment: day
    │
    ├─→ ReplicaSet: day-5d89b7c4f6 (replicas: 1) ← Scaling DOWN
    │       └─→ Pod: day-5d89b7c4f6-abc12 (image: day:v1)
    │           (Pod: day-5d89b7c4f6-def34 terminated)
    │
    └─→ ReplicaSet: day-7f8c9d2e3a (replicas: 1) ← Scaling UP
            └─→ Pod: day-7f8c9d2e3a-ghi78 (image: day:v2)
```

**After Update (v2):**
```
Deployment: day
    │
    ├─→ ReplicaSet: day-5d89b7c4f6 (replicas: 0) ← KEPT for rollback
    │
    └─→ ReplicaSet: day-7f8c9d2e3a (replicas: 2) ← ACTIVE
            ├─→ Pod: day-7f8c9d2e3a-ghi78 (image: day:v2)
            └─→ Pod: day-7f8c9d2e3a-jkl90 (image: day:v2)
```

---

## Why Not Update Existing ReplicaSets?

There are several reasons Kubernetes uses the "new ReplicaSet per version" approach:

### 1. Immutability

**Pod templates in ReplicaSets are immutable by design.**

```yaml
# ReplicaSet spec
spec:
  template:  # ← This cannot be changed after creation
    spec:
      containers:
      - image: day:v1  # ← Immutable
```

If you try to update it:
```bash
kubectl patch replicaset day-5d89b7c4f6 -n day-ns \
  --type json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"day:v2"}]'

# Error:
The ReplicaSet "day-5d89b7c4f6" is invalid:
spec.template: Forbidden: pod template is immutable except for containers
```

**Why immutable?** ReplicaSets need a stable pod template to know what pods to create. If the template changes, how do you know which pods match?

### 2. Atomic Rollback

With separate ReplicaSets per version, rollback is simple:

```bash
# Rollback = swap which ReplicaSet has non-zero replicas
Old ReplicaSet: 0 → 2
New ReplicaSet: 2 → 0
```

If you updated ReplicaSets in-place, rollback would require:
- Tracking previous templates
- Complex state management
- More potential for errors

### 3. Progressive Rollout Control

By managing two ReplicaSets simultaneously, Deployments can:

- Control how many old vs new pods exist
- Ensure minimum availability (maxUnavailable)
- Control resource usage (maxSurge)
- Pause/resume rollouts
- Monitor health during transition

### 4. Clear Version History

```bash
kubectl get rs -n day-ns
NAME               DESIRED   CURRENT   READY   AGE
day-5d89b7c4f6     0         0         0       1h    # v1
day-7f8c9d2e3a     0         0         0       45m   # v2
day-9a1b2c3d4e     2         2         2       30m   # v3 (active)
```

Each ReplicaSet represents a specific version in history.

### 5. Hash-Based Identification

The ReplicaSet name includes a hash of the pod template:

```
day-5d89b7c4f6
    ↑
    └── Hash of pod template (image: day:v1, env, resources, etc.)
```

If the template changes → different hash → different ReplicaSet name.

This ensures:
- Each unique configuration gets a unique ReplicaSet
- No confusion about which ReplicaSet manages which version
- Duplicate configs reuse existing ReplicaSets

---

## Step-by-Step Rolling Update Process

Let's trace a complete update from `day:v1` to `day:v2`.

### Initial State

```yaml
# Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: day
  namespace: day-ns
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    spec:
      containers:
      - name: day
        image: day:v1  # ← Current version
```

**Resources:**
```
Deployment: day (replicas: 2, image: day:v1)
    │
    └─→ ReplicaSet: day-5d89b7c4f6 (replicas: 2)
            ├─→ Pod: day-5d89b7c4f6-abc12 (Running v1)
            └─→ Pod: day-5d89b7c4f6-def34 (Running v1)
```

### Step 1: User Updates Deployment

```bash
kubectl set image deployment/day day=day:v2 -n day-ns
```

**Deployment spec updated:**
```yaml
spec:
  template:
    spec:
      containers:
      - image: day:v2  # ← Changed
```

### Step 2: Deployment Controller Detects Change

The Deployment controller runs its reconciliation loop:

```python
# Simplified controller logic
def reconcile_deployment(deployment):
    current_template = deployment.spec.template
    current_hash = compute_hash(current_template)

    # Find ReplicaSet with matching hash
    existing_rs = find_replicaset_by_hash(deployment, current_hash)

    if not existing_rs:
        # Template changed! Create new ReplicaSet
        new_rs = create_replicaset(deployment, current_template, current_hash)
        print(f"Created new ReplicaSet: {new_rs.name}")
```

**Result:** New ReplicaSet created

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: day-7f8c9d2e3a  # ← New name (different hash)
  ownerReferences:
  - kind: Deployment
    name: day
spec:
  replicas: 0  # ← Starts at 0
  selector:
    matchLabels:
      app: day
      pod-template-hash: 7f8c9d2e3a
  template:
    spec:
      containers:
      - name: day
        image: day:v2  # ← New image
```

**Current state:**
```
Deployment: day
    │
    ├─→ ReplicaSet: day-5d89b7c4f6 (replicas: 2) ← Old
    │       ├─→ Pod: day-5d89b7c4f6-abc12 (Running v1)
    │       └─→ Pod: day-5d89b7c4f6-def34 (Running v1)
    │
    └─→ ReplicaSet: day-7f8c9d2e3a (replicas: 0) ← New (just created)
```

### Step 3: Deployment Controller Initiates Rollout

The controller calculates what to do based on `maxSurge` and `maxUnavailable`:

```python
desired_replicas = 2
max_surge = 1
max_unavailable = 0

# Calculate limits
max_total_pods = desired_replicas + max_surge  # 2 + 1 = 3
min_available_pods = desired_replicas - max_unavailable  # 2 - 0 = 2

# Current state
old_rs_replicas = 2
new_rs_replicas = 0
total_replicas = 2

# Decision: Can we scale up new ReplicaSet?
if total_replicas < max_total_pods:  # 2 < 3 = True
    new_rs_replicas += 1  # Scale up to 1
```

**Action:** Scale new ReplicaSet to 1

```
T+1s:
Deployment: day
    │
    ├─→ ReplicaSet: day-5d89b7c4f6 (replicas: 2)
    │       ├─→ Pod: day-5d89b7c4f6-abc12 (Running v1)
    │       └─→ Pod: day-5d89b7c4f6-def34 (Running v1)
    │
    └─→ ReplicaSet: day-7f8c9d2e3a (replicas: 0 → 1)
            └─→ Pod: day-7f8c9d2e3a-ghi78 (ContainerCreating v2)
```

### Step 4: Wait for New Pod to Become Ready

```
T+10s:
Deployment: day
    │
    ├─→ ReplicaSet: day-5d89b7c4f6 (replicas: 2)
    │       ├─→ Pod: day-5d89b7c4f6-abc12 (Running v1)
    │       └─→ Pod: day-5d89b7c4f6-def34 (Running v1)
    │
    └─→ ReplicaSet: day-7f8c9d2e3a (replicas: 1)
            └─→ Pod: day-7f8c9d2e3a-ghi78 (Running v2) ✓ Ready!
```

**Key:** The controller waits for the pod to pass readiness probes before continuing.

### Step 5: Scale Down Old ReplicaSet

```python
# Controller logic
old_ready_pods = 2
new_ready_pods = 1
total_ready = 3

# Decision: Can we scale down old ReplicaSet?
if total_ready > min_available_pods:  # 3 > 2 = True
    old_rs_replicas -= 1  # Scale down to 1
```

**Action:** Scale old ReplicaSet to 1

```
T+11s:
Deployment: day
    │
    ├─→ ReplicaSet: day-5d89b7c4f6 (replicas: 2 → 1)
    │       ├─→ Pod: day-5d89b7c4f6-abc12 (Running v1)
    │       └─→ Pod: day-5d89b7c4f6-def34 (Terminating v1)
    │
    └─→ ReplicaSet: day-7f8c9d2e3a (replicas: 1)
            └─→ Pod: day-7f8c9d2e3a-ghi78 (Running v2)
```

### Step 6: Old Pod Terminates

```
T+20s:
Deployment: day
    │
    ├─→ ReplicaSet: day-5d89b7c4f6 (replicas: 1)
    │       └─→ Pod: day-5d89b7c4f6-abc12 (Running v1)
    │
    └─→ ReplicaSet: day-7f8c9d2e3a (replicas: 1)
            └─→ Pod: day-7f8c9d2e3a-ghi78 (Running v2)
```

**Current:** 2 ready pods (1 old, 1 new)

### Step 7: Scale Up New ReplicaSet Again

```python
# Controller logic
new_rs_replicas = 1
desired_replicas = 2
total_replicas = 1 + 1 = 2

# Decision: Scale up new ReplicaSet?
if new_rs_replicas < desired_replicas:  # 1 < 2 = True
    if total_replicas < max_total_pods:  # 2 < 3 = True
        new_rs_replicas += 1  # Scale up to 2
```

**Action:** Scale new ReplicaSet to 2

```
T+21s:
Deployment: day
    │
    ├─→ ReplicaSet: day-5d89b7c4f6 (replicas: 1)
    │       └─→ Pod: day-5d89b7c4f6-abc12 (Running v1)
    │
    └─→ ReplicaSet: day-7f8c9d2e3a (replicas: 1 → 2)
            ├─→ Pod: day-7f8c9d2e3a-ghi78 (Running v2)
            └─→ Pod: day-7f8c9d2e3a-jkl90 (ContainerCreating v2)
```

### Step 8: Wait for Second New Pod to Become Ready

```
T+30s:
Deployment: day
    │
    ├─→ ReplicaSet: day-5d89b7c4f6 (replicas: 1)
    │       └─→ Pod: day-5d89b7c4f6-abc12 (Running v1)
    │
    └─→ ReplicaSet: day-7f8c9d2e3a (replicas: 2)
            ├─→ Pod: day-7f8c9d2e3a-ghi78 (Running v2)
            └─→ Pod: day-7f8c9d2e3a-jkl90 (Running v2) ✓ Ready!
```

**Current:** 3 ready pods (1 old, 2 new)

### Step 9: Scale Down Old ReplicaSet to 0

```python
# Controller logic
total_ready = 3
new_ready = 2
new_rs_replicas = 2
desired_replicas = 2

# New ReplicaSet is fully scaled!
if new_rs_replicas == desired_replicas:  # 2 == 2 = True
    if old_rs_replicas > 0:  # 1 > 0 = True
        old_rs_replicas = 0  # Scale down completely
```

**Action:** Scale old ReplicaSet to 0

```
T+31s:
Deployment: day
    │
    ├─→ ReplicaSet: day-5d89b7c4f6 (replicas: 1 → 0)
    │       └─→ Pod: day-5d89b7c4f6-abc12 (Terminating v1)
    │
    └─→ ReplicaSet: day-7f8c9d2e3a (replicas: 2)
            ├─→ Pod: day-7f8c9d2e3a-ghi78 (Running v2)
            └─→ Pod: day-7f8c9d2e3a-jkl90 (Running v2)
```

### Step 10: Rollout Complete

```
T+40s:
Deployment: day
    │
    ├─→ ReplicaSet: day-5d89b7c4f6 (replicas: 0) ← KEPT for rollback
    │
    └─→ ReplicaSet: day-7f8c9d2e3a (replicas: 2) ← ACTIVE
            ├─→ Pod: day-7f8c9d2e3a-ghi78 (Running v2)
            └─→ Pod: day-7f8c9d2e3a-jkl90 (Running v2)
```

**Deployment status:**
```yaml
status:
  replicas: 2
  updatedReplicas: 2
  readyReplicas: 2
  availableReplicas: 2
  conditions:
  - type: Progressing
    status: "True"
    reason: NewReplicaSetAvailable
    message: "ReplicaSet 'day-7f8c9d2e3a' has successfully progressed."
  - type: Available
    status: "True"
```

**Update complete! All pods now running v2.**

---

## The Deployment Controller Algorithm

Here's the actual algorithm the Deployment controller uses:

```python
def reconcile_deployment(deployment):
    """
    Main reconciliation loop for Deployment updates
    """
    # 1. Get current pod template hash
    current_hash = compute_hash(deployment.spec.template)

    # 2. Find or create ReplicaSet with this hash
    new_rs = find_or_create_replicaset(deployment, current_hash)

    # 3. Find all ReplicaSets owned by this Deployment
    all_rs = list_replicasets(deployment)
    old_rs_list = [rs for rs in all_rs if rs != new_rs]

    # 4. Determine update strategy
    if deployment.spec.strategy.type == "Recreate":
        return reconcile_recreate(deployment, old_rs_list, new_rs)
    else:  # RollingUpdate
        return reconcile_rolling_update(deployment, old_rs_list, new_rs)

def reconcile_rolling_update(deployment, old_rs_list, new_rs):
    """
    Perform rolling update
    """
    desired = deployment.spec.replicas
    max_surge = deployment.spec.strategy.rollingUpdate.maxSurge
    max_unavailable = deployment.spec.strategy.rollingUpdate.maxUnavailable

    # Calculate limits
    max_total = desired + resolve_value(max_surge, desired)
    min_available = desired - resolve_value(max_unavailable, desired)

    # Get current state
    new_ready = count_ready_pods(new_rs)
    old_ready = sum(count_ready_pods(rs) for rs in old_rs_list)
    total_ready = new_ready + old_ready

    current_total = new_rs.spec.replicas + sum(rs.spec.replicas for rs in old_rs_list)

    # SCALE UP new ReplicaSet
    if new_rs.spec.replicas < desired:
        if current_total < max_total:
            # Can scale up
            scale_up = min(
                max_total - current_total,  # Don't exceed max
                desired - new_rs.spec.replicas  # Don't exceed desired
            )
            new_rs.spec.replicas += scale_up
            update_replicaset(new_rs)
            return  # Wait for pods to become ready

    # SCALE DOWN old ReplicaSets
    if new_ready > 0:  # Only if new pods are ready
        for old_rs in old_rs_list:
            if old_rs.spec.replicas == 0:
                continue

            # Check if we can scale down without going below min available
            if total_ready > min_available:
                scale_down = min(
                    total_ready - min_available,  # Don't go below min
                    old_rs.spec.replicas  # Scale down entire RS if possible
                )
                old_rs.spec.replicas -= scale_down
                update_replicaset(old_rs)
                total_ready -= scale_down

    # CLEANUP old ReplicaSets (if configured)
    cleanup_old_replicasets(deployment, old_rs_list)

def resolve_value(value, total):
    """
    Resolve maxSurge/maxUnavailable (can be number or percentage)
    """
    if isinstance(value, int):
        return value
    else:  # Percentage
        return int(total * value / 100)

def cleanup_old_replicasets(deployment, old_rs_list):
    """
    Delete old ReplicaSets beyond revisionHistoryLimit
    """
    limit = deployment.spec.revisionHistoryLimit  # Default: 10

    # Keep only the most recent `limit` ReplicaSets
    sorted_rs = sorted(old_rs_list, key=lambda rs: rs.metadata.creationTimestamp, reverse=True)

    to_delete = sorted_rs[limit:]
    for rs in to_delete:
        if rs.spec.replicas == 0:  # Only delete if scaled to 0
            delete_replicaset(rs)
```

### Key Decision Points

1. **When to scale up new ReplicaSet:**
   - If `new_replicas < desired` AND `total_replicas < max_total`

2. **When to scale down old ReplicaSet:**
   - If `new_ready_pods > 0` AND `total_ready > min_available`

3. **How much to scale:**
   - Scale up: Minimum of (available surge capacity, remaining desired)
   - Scale down: Minimum of (excess availability, old ReplicaSet size)

4. **When update is complete:**
   - When `new_rs.replicas == desired` AND `all_old_rs.replicas == 0`

---

## maxSurge and maxUnavailable Explained

These parameters control the rolling update behavior.

### maxSurge

**Maximum number of extra pods that can exist during the update.**

```yaml
strategy:
  rollingUpdate:
    maxSurge: 1  # Can have 1 extra pod temporarily
```

**With `replicas: 2` and `maxSurge: 1`:**
- Desired: 2 pods
- Max during update: 2 + 1 = 3 pods
- Allows creating new pod before terminating old one

**Examples:**

```yaml
# Absolute number
maxSurge: 1     # Exactly 1 extra pod

# Percentage
maxSurge: 25%   # 25% of desired replicas
                # With replicas=10: 10 * 0.25 = 2.5 → 3 extra pods
```

**Effect on update speed:**
- `maxSurge: 0` → Slow (must delete old before creating new)
- `maxSurge: 1` → Moderate
- `maxSurge: 100%` → Fast (can create all new pods immediately)

**Effect on resources:**
- Higher surge → More resource usage during update
- Lower surge → Less resource usage

### maxUnavailable

**Maximum number of pods that can be unavailable during the update.**

```yaml
strategy:
  rollingUpdate:
    maxUnavailable: 0  # All pods must stay available
```

**With `replicas: 2` and `maxUnavailable: 0`:**
- Desired: 2 pods
- Min available: 2 - 0 = 2 pods
- Cannot delete old pods until new ones are ready

**Examples:**

```yaml
# Absolute number
maxUnavailable: 1     # 1 pod can be down

# Percentage
maxUnavailable: 25%   # 25% of desired replicas can be down
                      # With replicas=10: 10 * 0.25 = 2.5 → 2 pods
```

**Effect on availability:**
- `maxUnavailable: 0` → Zero downtime (safest)
- `maxUnavailable: 1` → Brief capacity reduction
- `maxUnavailable: 100%` → Can take down all pods (risky!)

### Common Combinations

#### 1. Zero-Downtime Update (Safest)

```yaml
maxSurge: 1
maxUnavailable: 0
```

**Behavior:**
- Creates new pod first
- Waits for it to be ready
- Then deletes old pod
- Guaranteed availability

**Use case:** Production services that must always be available

#### 2. Resource-Constrained Update

```yaml
maxSurge: 0
maxUnavailable: 1
```

**Behavior:**
- Deletes old pod first
- Then creates new pod
- No extra resource usage

**Use case:** When cluster doesn't have spare capacity

#### 3. Fast Update

```yaml
maxSurge: 100%
maxUnavailable: 0
```

**Behavior:**
- Creates all new pods immediately
- Waits for them to be ready
- Then deletes all old pods

**Use case:** When you want fast updates and have resources

#### 4. Aggressive Update (Risky)

```yaml
maxSurge: 100%
maxUnavailable: 100%
```

**Behavior:**
- No constraints
- Can delete and create pods freely
- Similar to Recreate strategy

**Use case:** Development environments, non-critical services

### Calculation Examples

**Scenario:** `replicas: 10`

| maxSurge | maxUnavailable | Max Total | Min Available | Notes |
|----------|----------------|-----------|---------------|-------|
| 1 | 0 | 11 | 10 | Safe, slow |
| 25% | 0 | 13 | 10 | Safe, moderate |
| 0 | 1 | 10 | 9 | Minimal resources |
| 50% | 25% | 15 | 8 | Balanced |
| 100% | 0 | 20 | 10 | Fast, resource-heavy |

---

## What Happens to Pods

**Pods are NEVER updated in-place.** They are immutable.

### When ReplicaSet is Scaled Down

```
1. Deployment controller updates old ReplicaSet: replicas: 2 → 1
2. ReplicaSet controller sees: desired=1, current=2
3. ReplicaSet controller selects pod to delete (oldest first)
4. ReplicaSet controller calls API: DELETE /pods/day-5d89b7c4f6-def34
5. API server marks pod for deletion (deletionTimestamp set)
6. Kubelet on that node receives update
7. Kubelet sends SIGTERM to container
8. Container has 30s (terminationGracePeriodSeconds) to shut down
9. After grace period, Kubelet sends SIGKILL
10. Container stopped
11. Kubelet reports pod terminated
12. API server deletes pod object
```

### When ReplicaSet is Scaled Up

```
1. Deployment controller updates new ReplicaSet: replicas: 0 → 1
2. ReplicaSet controller sees: desired=1, current=0
3. ReplicaSet controller creates pod from template
4. API server stores new pod object (status: Pending)
5. Scheduler sees unscheduled pod
6. Scheduler assigns pod to node with available resources
7. Kubelet on that node sees new pod assigned to it
8. Kubelet pulls container image (if not cached)
9. Kubelet creates container
10. Kubelet starts container
11. Container starts, runs startup probes
12. After initialDelaySeconds, runs readiness probes
13. When readiness succeeds, pod marked Ready
14. Deployment controller sees new ready pod
15. Continues rolling update
```

### Pod Lifecycle States During Update

```
Old Pods:
  Running → Terminating → (deleted)

New Pods:
  (created) → Pending → ContainerCreating → Running (not Ready) → Running (Ready)
```

---

## Rollback Mechanism

Rollback works by reversing the scaling: scale up old ReplicaSet, scale down new ReplicaSet.

### How Rollback Works

```bash
# Current state (after update to v2)
kubectl get rs -n day-ns
NAME               DESIRED   CURRENT   READY   AGE
day-5d89b7c4f6     0         0         0       1h    # v1 (old)
day-7f8c9d2e3a     2         2         2       30m   # v2 (current)

# Initiate rollback
kubectl rollout undo deployment day -n day-ns
```

**What happens:**

1. Deployment controller identifies previous ReplicaSet (day-5d89b7c4f6)
2. Updates Deployment spec to use old pod template (image: day:v1)
3. Starts rolling update process:
   - Scale up old ReplicaSet: 0 → 1 → 2
   - Scale down new ReplicaSet: 2 → 1 → 0
4. Same rolling update algorithm, but in reverse!

**Final state:**

```bash
kubectl get rs -n day-ns
NAME               DESIRED   CURRENT   READY   AGE
day-5d89b7c4f6     2         2         2       1h    # v1 (active again)
day-7f8c9d2e3a     0         0         0       30m   # v2 (scaled to 0)
```

### Rollback to Specific Revision

```bash
# View rollout history
kubectl rollout history deployment day -n day-ns
REVISION  CHANGE-CAUSE
1         Initial deployment (image: day:v1)
2         Updated image to day:v2
3         Updated image to day:v3

# Rollback to specific revision
kubectl rollout undo deployment day --to-revision=1 -n day-ns
```

**What happens:**

1. Controller finds ReplicaSet for revision 1
2. Updates Deployment to use that ReplicaSet's pod template
3. Performs rolling update to that version

### Why Old ReplicaSets Are Kept

```yaml
spec:
  revisionHistoryLimit: 10  # Keep last 10 ReplicaSets
```

**Reasons:**
- Enable quick rollback (no need to recreate ReplicaSet)
- Maintain audit trail (what versions were deployed)
- Support `rollout history` command

**Cleanup:**
- ReplicaSets beyond limit are automatically deleted
- Only ReplicaSets with 0 replicas can be deleted
- Set to 0 to disable history (not recommended)

---

## Multiple Updates and Revision History

Each Deployment update creates a new ReplicaSet.

### Scenario: Multiple Updates

```bash
# Initial: v1
kubectl apply -f deployment.yaml  # image: day:v1
# Creates: day-5d89b7c4f6

# Update 1: v1 → v2
kubectl set image deployment/day day=day:v2 -n day-ns
# Creates: day-7f8c9d2e3a
# Scales: day-5d89b7c4f6 to 0

# Update 2: v2 → v3
kubectl set image deployment/day day=day:v3 -n day-ns
# Creates: day-9a1b2c3d4e
# Scales: day-7f8c9d2e3a to 0

# Update 3: v3 → v4
kubectl set image deployment/day day=day:v4 -n day-ns
# Creates: day-1f2a3b4c5d
# Scales: day-9a1b2c3d4e to 0
```

**Final state:**

```bash
kubectl get rs -n day-ns
NAME               DESIRED   CURRENT   READY   AGE
day-5d89b7c4f6     0         0         0       2h    # v1
day-7f8c9d2e3a     0         0         0       1h    # v2
day-9a1b2c3d4e     0         0         0       30m   # v3
day-1f2a3b4c5d     2         2         2       5m    # v4 (active)
```

### Template Hash Deduplication

If you update to a version that existed before, Kubernetes reuses the old ReplicaSet:

```bash
# Current: v3 (ReplicaSet: day-9a1b2c3d4e)

# Update to v1 (which we deployed before)
kubectl set image deployment/day day=day:v1 -n day-ns

# Kubernetes reuses day-5d89b7c4f6 (doesn't create new ReplicaSet)
kubectl get rs -n day-ns
NAME               DESIRED   CURRENT   READY   AGE
day-5d89b7c4f6     2         2         2       2h    # v1 (reactivated!)
day-7f8c9d2e3a     0         0         0       1h    # v2
day-9a1b2c3d4e     0         0         0       30m   # v3 (just scaled to 0)
```

**How it works:**
- Hash is computed from entire pod template
- Same template → same hash → same ReplicaSet name
- Controller finds existing ReplicaSet and scales it up

---

## Update Strategies

Kubernetes supports two update strategies.

### 1. RollingUpdate (Default)

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
```

**Behavior:**
- Gradual replacement of old pods with new pods
- Controlled by maxSurge and maxUnavailable
- Zero downtime possible

**Process:**
1. Create new ReplicaSet (replicas: 0)
2. Incrementally scale up new, scale down old
3. Wait for pods to be ready at each step
4. Complete when new ReplicaSet has all replicas

**Use cases:**
- Production services
- Stateless applications
- Services that can run old and new versions simultaneously

### 2. Recreate

```yaml
spec:
  strategy:
    type: Recreate
```

**Behavior:**
- Delete ALL old pods, then create ALL new pods
- No gradual transition
- Downtime guaranteed

**Process:**
1. Create new ReplicaSet (replicas: 0)
2. Scale old ReplicaSet to 0 (all pods deleted)
3. Wait for all old pods to terminate
4. Scale new ReplicaSet to desired (all pods created)

**Use cases:**
- Applications that cannot run multiple versions simultaneously
- Shared state that would conflict between versions
- Database migrations that require downtime
- Development environments

**Example scenario:**

```yaml
# Before update
Old ReplicaSet: 3 pods running

# During update
All pods deleted
(Downtime: no pods running)

# After update
New ReplicaSet: 3 pods running
```

---

## Observing Rolling Updates

### Watch the Rollout

```bash
# Start the update
kubectl set image deployment/day day=day:v2 -n day-ns

# Watch rollout status
kubectl rollout status deployment day -n day-ns
# Output:
Waiting for deployment "day" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "day" rollout to finish: 1 old replicas are pending termination...
deployment "day" successfully rolled out
```

### Watch ReplicaSets

```bash
kubectl get rs -n day-ns -w

# Output (live updates):
NAME               DESIRED   CURRENT   READY   AGE
day-5d89b7c4f6     2         2         2       5m     ← Old
day-7f8c9d2e3a     0         0         0       0s     ← New (created)
day-7f8c9d2e3a     1         0         0       0s     ← Scaling up
day-7f8c9d2e3a     1         1         0       1s
day-7f8c9d2e3a     1         1         1       10s    ← Ready
day-5d89b7c4f6     1         2         2       5m     ← Scaling down
day-5d89b7c4f6     1         1         1       5m
day-7f8c9d2e3a     2         1         1       11s    ← Scaling up
day-7f8c9d2e3a     2         2         1       11s
day-7f8c9d2e3a     2         2         2       20s    ← Ready
day-5d89b7c4f6     0         1         1       5m     ← Scaling to 0
day-5d89b7c4f6     0         0         0       5m     ← Done
```

### Watch Pods

```bash
kubectl get pods -n day-ns -w

# Output:
NAME                   READY   STATUS              RESTARTS   AGE
day-5d89b7c4f6-abc12   1/1     Running             0          5m
day-5d89b7c4f6-def34   1/1     Running             0          5m
day-7f8c9d2e3a-ghi78   0/1     ContainerCreating   0          1s    ← New
day-7f8c9d2e3a-ghi78   1/1     Running             0          10s   ← Ready
day-5d89b7c4f6-def34   1/1     Terminating         0          5m    ← Terminating
day-7f8c9d2e3a-jkl90   0/1     ContainerCreating   0          11s   ← New
day-5d89b7c4f6-def34   0/1     Terminating         0          5m
day-7f8c9d2e3a-jkl90   1/1     Running             0          20s   ← Ready
day-5d89b7c4f6-abc12   1/1     Terminating         0          5m    ← Terminating
day-5d89b7c4f6-abc12   0/1     Terminating         0          5m
```

### Check Deployment Status

```bash
kubectl describe deployment day -n day-ns

# Relevant sections:
Replicas:               2 desired | 2 updated | 2 total | 2 available
StrategyType:           RollingUpdate
MinReadySeconds:        0
RollingUpdateStrategy:  1 max surge, 0 max unavailable

OldReplicaSets:   day-5d89b7c4f6 (0/0 replicas created)
NewReplicaSet:    day-7f8c9d2e3a (2/2 replicas created)

Events:
  Type    Reason             Message
  ----    ------             -------
  Normal  ScalingReplicaSet  Scaled up replica set day-7f8c9d2e3a to 1
  Normal  ScalingReplicaSet  Scaled down replica set day-5d89b7c4f6 to 1
  Normal  ScalingReplicaSet  Scaled up replica set day-7f8c9d2e3a to 2
  Normal  ScalingReplicaSet  Scaled down replica set day-5d89b7c4f6 to 0
```

---

## Real-World Example from This Repository

Let's use your actual Deployment configuration.

### Your Deployment

From `foundation/k8s/day/prod/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: day
  namespace: day-ns
spec:
  replicas: 2
  # Note: No strategy specified, so defaults to RollingUpdate
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
        readinessProbe:
          httpGet:
            path: /health
            port: 8001
          initialDelaySeconds: 10
          periodSeconds: 5
```

**Default strategy applied:**
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 25%       # 25% of 2 = 0.5 → 1 pod
    maxUnavailable: 25% # 25% of 2 = 0.5 → 1 pod
```

**Effective limits:**
- Max total pods during update: 2 + 1 = 3
- Min available pods during update: 2 - 1 = 1

### Updating Your Deployment

```bash
# Build new image
docker build -t day:v2 foundation/services/day/

# Tag and push to registry
docker tag day:v2 <registry>/day:v2
docker push <registry>/day:v2

# Update deployment
kubectl set image deployment/day day=<registry>/day:v2 -n day-ns
```

**What happens:**

```
T+0s: New ReplicaSet created: day-<hash-v2>
      Old ReplicaSet: day-<hash-v1> (replicas: 2)
      New ReplicaSet: day-<hash-v2> (replicas: 0)

T+1s: Scale up new (surge allowed: 3 - 2 = 1)
      Old ReplicaSet: 2 pods
      New ReplicaSet: 0 → 1 pod (ContainerCreating)

T+11s: New pod ready (after 10s initialDelaySeconds + probe)
       Old ReplicaSet: 2 pods
       New ReplicaSet: 1 pod (Ready)
       Total: 3 pods (1 above desired)

T+12s: Scale down old (can go down to min available: 1)
       Old ReplicaSet: 2 → 1 pod (1 terminating)
       New ReplicaSet: 1 pod
       Total ready: 2 pods

T+22s: Old pod terminated, scale up new
       Old ReplicaSet: 1 pod
       New ReplicaSet: 1 → 2 pods (1 ContainerCreating)

T+33s: Second new pod ready
       Old ReplicaSet: 1 pod
       New ReplicaSet: 2 pods (Ready)
       Total: 3 pods

T+34s: Scale down old to 0
       Old ReplicaSet: 1 → 0 (terminating)
       New ReplicaSet: 2 pods

T+44s: Update complete
       Old ReplicaSet: 0 pods (kept for rollback)
       New ReplicaSet: 2 pods (active)
```

**Timeline:** ~44 seconds for complete rollout with 2 replicas

### Optimizing for Your Use Case

**For zero-downtime production:**

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0  # ← No pods can be unavailable
```

**For faster updates in RC environment:**

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 100%     # ← Create all new pods immediately
    maxUnavailable: 0
```

---

## The Complete State Machine

```
┌─────────────────────────────────────────────────────────────┐
│ INITIAL STATE                                               │
│                                                             │
│ Deployment: image=day:v1, replicas=2                        │
│     └─→ ReplicaSet-v1: replicas=2                          │
│             ├─→ Pod-1 (Running v1)                         │
│             └─→ Pod-2 (Running v1)                         │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ User updates: image=day:v2
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ STATE 1: New ReplicaSet Created                            │
│                                                             │
│ Deployment: image=day:v2, replicas=2                        │
│     ├─→ ReplicaSet-v1: replicas=2 (old)                   │
│     │       ├─→ Pod-1 (Running v1)                        │
│     │       └─→ Pod-2 (Running v1)                        │
│     └─→ ReplicaSet-v2: replicas=0 (new) ← JUST CREATED    │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ Controller scales up new
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ STATE 2: Scaling Up New                                    │
│                                                             │
│ Deployment: image=day:v2, replicas=2                        │
│     ├─→ ReplicaSet-v1: replicas=2                         │
│     │       ├─→ Pod-1 (Running v1)                        │
│     │       └─→ Pod-2 (Running v1)                        │
│     └─→ ReplicaSet-v2: replicas=0→1                       │
│             └─→ Pod-3 (ContainerCreating v2) ← NEW        │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ Wait for readiness
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ STATE 3: New Pod Ready                                     │
│                                                             │
│ Deployment: image=day:v2, replicas=2                        │
│     ├─→ ReplicaSet-v1: replicas=2                         │
│     │       ├─→ Pod-1 (Running v1)                        │
│     │       └─→ Pod-2 (Running v1)                        │
│     └─→ ReplicaSet-v2: replicas=1                         │
│             └─→ Pod-3 (Running v2) ✓                      │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ Controller scales down old
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ STATE 4: Scaling Down Old                                  │
│                                                             │
│ Deployment: image=day:v2, replicas=2                        │
│     ├─→ ReplicaSet-v1: replicas=2→1                       │
│     │       ├─→ Pod-1 (Running v1)                        │
│     │       └─→ Pod-2 (Terminating v1) ← TERMINATING      │
│     └─→ ReplicaSet-v2: replicas=1                         │
│             └─→ Pod-3 (Running v2)                        │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ Wait for termination
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ STATE 5: Old Pod Terminated                                │
│                                                             │
│ Deployment: image=day:v2, replicas=2                        │
│     ├─→ ReplicaSet-v1: replicas=1                         │
│     │       └─→ Pod-1 (Running v1)                        │
│     └─→ ReplicaSet-v2: replicas=1                         │
│             └─→ Pod-3 (Running v2)                        │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ Controller scales up new again
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ STATE 6: Scaling Up New Again                              │
│                                                             │
│ Deployment: image=day:v2, replicas=2                        │
│     ├─→ ReplicaSet-v1: replicas=1                         │
│     │       └─→ Pod-1 (Running v1)                        │
│     └─→ ReplicaSet-v2: replicas=1→2                       │
│             ├─→ Pod-3 (Running v2)                        │
│             └─→ Pod-4 (ContainerCreating v2) ← NEW        │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ Wait for readiness
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ STATE 7: Second New Pod Ready                              │
│                                                             │
│ Deployment: image=day:v2, replicas=2                        │
│     ├─→ ReplicaSet-v1: replicas=1                         │
│     │       └─→ Pod-1 (Running v1)                        │
│     └─→ ReplicaSet-v2: replicas=2                         │
│             ├─→ Pod-3 (Running v2)                        │
│             └─→ Pod-4 (Running v2) ✓                      │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ Controller scales down old to 0
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ STATE 8: Scaling Old to Zero                               │
│                                                             │
│ Deployment: image=day:v2, replicas=2                        │
│     ├─→ ReplicaSet-v1: replicas=1→0                       │
│     │       └─→ Pod-1 (Terminating v1) ← TERMINATING      │
│     └─→ ReplicaSet-v2: replicas=2                         │
│             ├─→ Pod-3 (Running v2)                        │
│             └─→ Pod-4 (Running v2)                        │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ Wait for termination
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ FINAL STATE: Update Complete                               │
│                                                             │
│ Deployment: image=day:v2, replicas=2                        │
│     ├─→ ReplicaSet-v1: replicas=0 ← KEPT FOR ROLLBACK     │
│     └─→ ReplicaSet-v2: replicas=2 ← ACTIVE                │
│             ├─→ Pod-3 (Running v2)                        │
│             └─→ Pod-4 (Running v2)                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Common Scenarios and Edge Cases

### Scenario 1: Update During Update

**What if you update the Deployment again while a rollout is in progress?**

```bash
# Start update v1 → v2
kubectl set image deployment/day day=day:v2 -n day-ns

# Before it finishes, update v2 → v3
kubectl set image deployment/day day=day:v3 -n day-ns
```

**What happens:**

1. First update starts: creates ReplicaSet-v2
2. Second update detected: creates ReplicaSet-v3
3. Deployment controller cancels v2 rollout
4. Scales down both ReplicaSet-v1 and ReplicaSet-v2
5. Scales up ReplicaSet-v3
6. Final state: only v3 running

**ReplicaSets:**
```
day-v1: replicas=0
day-v2: replicas=0  ← Partially scaled, then abandoned
day-v3: replicas=2  ← Active
```

### Scenario 2: Failed Readiness Probes

**What if new pods fail readiness probes?**

```
T+0s:  New pod created
T+10s: Readiness probe fails
T+15s: Readiness probe fails
T+20s: Readiness probe fails
... (continues failing)
```

**Behavior:**
- New pod never becomes Ready
- Deployment controller never scales down old ReplicaSet
- Old pods keep running (maintaining availability!)
- Rollout stalls

**Status:**
```bash
kubectl rollout status deployment day -n day-ns
# Waiting for deployment "day" rollout to finish: 1 out of 2 new replicas have been updated...
# (Hangs indefinitely)
```

**Solution:**
```bash
# Check what's wrong
kubectl describe pod <new-pod-name> -n day-ns

# Fix the issue (update image, config, etc.)
kubectl set image deployment/day day=day:v2-fixed -n day-ns

# Or rollback
kubectl rollout undo deployment day -n day-ns
```

### Scenario 3: Insufficient Resources

**What if cluster doesn't have resources for new pods?**

```
T+0s: New pod created
T+1s: Pod status: Pending (Insufficient CPU)
... (stuck)
```

**Behavior:**
- New pod can't be scheduled
- Never becomes Running/Ready
- Deployment controller waits indefinitely
- Old pods keep running

**Solution:**
- Add more nodes to cluster
- Reduce resource requests
- Delete other pods to free resources
- Use `maxSurge: 0` to avoid needing extra resources

### Scenario 4: Node Failure During Update

**What if a node fails during rolling update?**

```
T+10s: New pod-3 running on node-1 (Ready)
T+15s: Node-1 fails
T+16s: Pod-3 status: Unknown
T+5m:  Pod-3 marked for deletion
       ReplicaSet creates pod-5 on node-2
```

**Behavior:**
- Kubernetes detects node failure
- After grace period (~5 min), pod evicted
- ReplicaSet controller creates replacement
- Rolling update continues

---

## Troubleshooting

### Problem 1: Rollout Stuck

```bash
kubectl rollout status deployment day -n day-ns
# Waiting for deployment "day" rollout to finish: 1 out of 2 new replicas have been updated...
# (Hangs for a long time)
```

**Possible causes:**

1. **Readiness probes failing**
   ```bash
   kubectl describe pod <new-pod> -n day-ns
   # Events: Readiness probe failed: HTTP probe failed with statuscode: 500
   ```

2. **Image pull errors**
   ```bash
   kubectl get pods -n day-ns
   # STATUS: ImagePullBackOff
   ```

3. **Insufficient resources**
   ```bash
   kubectl describe pod <new-pod> -n day-ns
   # Events: FailedScheduling: Insufficient cpu
   ```

4. **CrashLoopBackOff**
   ```bash
   kubectl get pods -n day-ns
   # STATUS: CrashLoopBackOff
   ```

**Solutions:**

```bash
# Check pod events
kubectl describe pod <pod-name> -n day-ns

# Check pod logs
kubectl logs <pod-name> -n day-ns

# Pause rollout to investigate
kubectl rollout pause deployment day -n day-ns

# Fix the issue, then resume
kubectl rollout resume deployment day -n day-ns

# Or rollback
kubectl rollout undo deployment day -n day-ns
```

### Problem 2: Rollout Too Slow

**Symptoms:** Update takes a very long time

**Causes:**

1. **Conservative maxSurge/maxUnavailable**
   ```yaml
   maxSurge: 0
   maxUnavailable: 1
   replicas: 100  # One pod at a time = 100 iterations!
   ```

2. **Long readiness probe delay**
   ```yaml
   readinessProbe:
     initialDelaySeconds: 60  # Wait 60s before first probe
     periodSeconds: 30        # Check every 30s
   ```

**Solutions:**

```yaml
# Increase parallelism
strategy:
  rollingUpdate:
    maxSurge: 25%  # Or higher
    maxUnavailable: 25%

# Reduce probe delays
readinessProbe:
  initialDelaySeconds: 10  # Reduce if app starts faster
  periodSeconds: 5         # Check more frequently
```

### Problem 3: Resource Exhaustion

**Symptoms:** Cluster runs out of resources during update

**Cause:**
```yaml
strategy:
  rollingUpdate:
    maxSurge: 100%  # Doubles pod count temporarily!
```

**With 50 replicas:**
- Desired: 50 pods
- During update: up to 100 pods (50 old + 50 new)
- Resource usage doubles temporarily

**Solution:**

```yaml
# Reduce surge
maxSurge: 1      # Only 1 extra pod at a time
maxUnavailable: 1  # Allow 1 pod to be down

# Or use Recreate strategy
strategy:
  type: Recreate  # No surge, but has downtime
```

---

## Best Practices

### 1. Always Define Update Strategy Explicitly

```yaml
# ✓ GOOD: Explicit strategy
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0

# ✗ BAD: Relying on defaults
spec:
  # No strategy defined
```

**Why:** Defaults may change, explicit config is self-documenting

### 2. Zero-Downtime for Production

```yaml
# Production
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0  # ← No downtime
```

**Why:** Guarantees at least `replicas` pods always available

### 3. Resource-Constrained Environments

```yaml
# Staging/dev with limited resources
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 0          # ← No extra resources needed
    maxUnavailable: 1
```

**Why:** Doesn't require spare cluster capacity

### 4. Fast Rollbacks

```yaml
spec:
  revisionHistoryLimit: 10  # Keep 10 old ReplicaSets
```

**Why:** Enables instant rollback without recreating ReplicaSets

### 5. Progressive Delivery

```yaml
# Update to v2 with only 1 pod first
spec:
  replicas: 10
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
```

Then pause to validate:

```bash
kubectl rollout pause deployment day -n day-ns

# Validate v2 is working
# Monitor metrics, logs, errors

# If good, resume
kubectl rollout resume deployment day -n day-ns

# If bad, rollback
kubectl rollout undo deployment day -n day-ns
```

### 6. Health Checks Are Critical

```yaml
# Without health checks, broken pods are marked Ready!
readinessProbe:
  httpGet:
    path: /health
    port: 8001
  initialDelaySeconds: 10
  periodSeconds: 5
  failureThreshold: 3
```

**Why:** Prevents rolling out broken versions

### 7. Use ImagePullPolicy Carefully

```yaml
# ✓ GOOD: Explicit version tags
image: day:v2
imagePullPolicy: IfNotPresent

# ✗ BAD: Using :latest in production
image: day:latest
imagePullPolicy: Always  # Forces pull every time
```

**Why:**
- Explicit tags are reproducible
- `:latest` makes rollbacks ambiguous
- `Always` pull policy is slow

### 8. Monitor Rollouts

```bash
# Don't just fire and forget!
kubectl set image deployment/day day=day:v2 -n day-ns && \
  kubectl rollout status deployment/day -n day-ns

# Or use CI/CD to monitor
```

---

## Summary

### The Answer: How Rolling Updates Work

**Deployments create a NEW ReplicaSet for each version.**

1. **Don't update** existing ReplicaSets (they're immutable)
2. **Don't update** existing Pods (they're immutable)
3. **Create** new ReplicaSet with new pod template
4. **Orchestrate** two ReplicaSet controllers simultaneously:
   - Scale down old ReplicaSet: 2 → 1 → 0
   - Scale up new ReplicaSet: 0 → 1 → 2
5. **Control** the transition with maxSurge and maxUnavailable
6. **Keep** old ReplicaSets for instant rollback

### Key Insights

- **Immutability:** ReplicaSets and Pods are never modified after creation
- **Multiple ReplicaSets:** Deployment manages multiple ReplicaSets (one per version)
- **Gradual Transition:** New pods created, old pods deleted, controlled by strategy
- **Rollback Ready:** Old ReplicaSets kept at 0 replicas for quick rollback
- **Zero Downtime:** Possible with maxUnavailable: 0
- **Resource Control:** maxSurge controls temporary resource usage

### The Mechanism

```
User updates Deployment
    ↓
Deployment Controller detects change
    ↓
Creates NEW ReplicaSet
    ↓
Orchestrates both ReplicaSet Controllers
    ↓
Old ReplicaSet Controller deletes pods (as replicas decrease)
New ReplicaSet Controller creates pods (as replicas increase)
    ↓
Gradual transition (controlled by maxSurge/maxUnavailable)
    ↓
Update complete when new ReplicaSet has all replicas
```

---

## Further Reading

- [Kubernetes Documentation: Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Deployment Update Strategies](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy)
- [Progressive Delivery](https://blog.kubernetes.io/2018/04/production-grade-progressive-delivery-at-scale.html)

---

**Related files in this repository:**
- `foundation/k8s/day/prod/deployment.yaml` - Example Deployment
- `deployment-hierarchy.md` - How Deployments create Pods
- `configmap-relationships.md` - How ConfigMaps relate to Deployments
- `foundation/scripts/explore/explore-rolling-updates.sh` - Interactive demonstration script
