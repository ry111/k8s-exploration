#!/bin/bash
# Demonstration: How Deployments perform rolling updates via multiple ReplicaSets

echo "=== The Key Insight ==="
echo ""
echo "Deployments DON'T update existing ReplicaSets or Pods."
echo "Instead, they create a NEW ReplicaSet for each version!"
echo ""
echo "┌─────────────────────────────────────────────────────┐"
echo "│ Deployment (manages multiple ReplicaSets)          │"
echo "└────────────────┬────────────────────────────────────┘"
echo "                 │"
echo "                 ├─→ ReplicaSet v1 (old) - scaled to 0"
echo "                 │       └─→ Pods deleted"
echo "                 │"
echo "                 └─→ ReplicaSet v2 (new) - scaled to 2"
echo "                         └─→ New pods created"
echo ""

echo "=== SCENARIO 1: Initial Deployment ==="
echo ""
echo "You create a Deployment:"
cat << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: day
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: day
        image: day:v1  # ← Version 1
EOF
echo ""
echo "Deployment controller creates ReplicaSet:"
cat << 'EOF'
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: day-5d89b7c4f6  # ← Hash of pod template with v1
  ownerReferences:
  - kind: Deployment
    name: day
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: day
        image: day:v1
EOF
echo ""
echo "ReplicaSet creates 2 pods:"
echo "  day-5d89b7c4f6-abc12 (running day:v1)"
echo "  day-5d89b7c4f6-def34 (running day:v1)"
echo ""

echo "=== SCENARIO 2: You Update the Image ==="
echo ""
echo "You change the Deployment:"
echo "  kubectl set image deployment/day day=day:v2 -n day-ns"
echo ""
echo "Or edit directly:"
echo "  kubectl edit deployment day -n day-ns"
cat << 'EOF'
  # Change:
  image: day:v1  →  image: day:v2
EOF
echo ""

echo "=== SCENARIO 3: Deployment Controller's Response ==="
echo ""
echo "The Deployment controller sees the change and:"
echo ""
echo "Step 1: Create NEW ReplicaSet with new pod template"
cat << 'EOF'
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: day-7f8c9d2e3a  # ← DIFFERENT hash (new template)
  ownerReferences:
  - kind: Deployment
    name: day
spec:
  replicas: 0  # ← Starts at 0
  template:
    spec:
      containers:
      - name: day
        image: day:v2  # ← New image
EOF
echo ""
echo "Step 2: Gradually scale up NEW ReplicaSet and scale down OLD ReplicaSet"
echo ""
echo "The Deployment controller uses the 'maxSurge' and 'maxUnavailable' settings:"
cat << 'EOF'
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1        # Max 1 extra pod during update
    maxUnavailable: 0  # Min pods that must stay available
EOF
echo ""

echo "=== SCENARIO 4: The Rolling Update Process ==="
echo ""
echo "T+0s: Initial state"
echo "  Old ReplicaSet: day-5d89b7c4f6 (replicas: 2)"
echo "    └─→ day-5d89b7c4f6-abc12 (Running v1)"
echo "    └─→ day-5d89b7c4f6-def34 (Running v1)"
echo "  New ReplicaSet: day-7f8c9d2e3a (replicas: 0)"
echo "  Total pods: 2 (desired: 2, max during update: 3)"
echo ""

echo "T+1s: Create 1 new pod (maxSurge: 1)"
echo "  Old ReplicaSet: day-5d89b7c4f6 (replicas: 2)"
echo "    └─→ day-5d89b7c4f6-abc12 (Running v1)"
echo "    └─→ day-5d89b7c4f6-def34 (Running v1)"
echo "  New ReplicaSet: day-7f8c9d2e3a (replicas: 0 → 1)"
echo "    └─→ day-7f8c9d2e3a-ghi78 (ContainerCreating v2)"
echo "  Total pods: 3 (surge allowed)"
echo ""

echo "T+10s: New pod becomes Ready"
echo "  Old ReplicaSet: day-5d89b7c4f6 (replicas: 2)"
echo "    └─→ day-5d89b7c4f6-abc12 (Running v1)"
echo "    └─→ day-5d89b7c4f6-def34 (Running v1)"
echo "  New ReplicaSet: day-7f8c9d2e3a (replicas: 1)"
echo "    └─→ day-7f8c9d2e3a-ghi78 (Running v2) ✓"
echo "  Total ready pods: 3"
echo ""

echo "T+11s: Scale down old ReplicaSet by 1"
echo "  Old ReplicaSet: day-5d89b7c4f6 (replicas: 2 → 1)"
echo "    └─→ day-5d89b7c4f6-abc12 (Running v1)"
echo "    └─→ day-5d89b7c4f6-def34 (Terminating v1)"
echo "  New ReplicaSet: day-7f8c9d2e3a (replicas: 1)"
echo "    └─→ day-7f8c9d2e3a-ghi78 (Running v2)"
echo "  Total ready pods: 2 (back to desired)"
echo ""

echo "T+20s: Old pod terminated, create another new pod"
echo "  Old ReplicaSet: day-5d89b7c4f6 (replicas: 1)"
echo "    └─→ day-5d89b7c4f6-abc12 (Running v1)"
echo "  New ReplicaSet: day-7f8c9d2e3a (replicas: 1 → 2)"
echo "    └─→ day-7f8c9d2e3a-ghi78 (Running v2)"
echo "    └─→ day-7f8c9d2e3a-jkl90 (ContainerCreating v2)"
echo "  Total pods: 3 (surge allowed)"
echo ""

echo "T+30s: Second new pod becomes Ready"
echo "  Old ReplicaSet: day-5d89b7c4f6 (replicas: 1)"
echo "    └─→ day-5d89b7c4f6-abc12 (Running v1)"
echo "  New ReplicaSet: day-7f8c9d2e3a (replicas: 2)"
echo "    └─→ day-7f8c9d2e3a-ghi78 (Running v2)"
echo "    └─→ day-7f8c9d2e3a-jkl90 (Running v2) ✓"
echo "  Total ready pods: 3"
echo ""

echo "T+31s: Scale down old ReplicaSet to 0"
echo "  Old ReplicaSet: day-5d89b7c4f6 (replicas: 1 → 0)"
echo "    └─→ day-5d89b7c4f6-abc12 (Terminating v1)"
echo "  New ReplicaSet: day-7f8c9d2e3a (replicas: 2)"
echo "    └─→ day-7f8c9d2e3a-ghi78 (Running v2)"
echo "    └─→ day-7f8c9d2e3a-jkl90 (Running v2)"
echo "  Total ready pods: 2 (desired state reached)"
echo ""

echo "T+40s: Update complete!"
echo "  Old ReplicaSet: day-5d89b7c4f6 (replicas: 0) ← KEPT for rollback"
echo "  New ReplicaSet: day-7f8c9d2e3a (replicas: 2)"
echo "    └─→ day-7f8c9d2e3a-ghi78 (Running v2)"
echo "    └─→ day-7f8c9d2e3a-jkl90 (Running v2)"
echo ""
echo "All pods now running v2! ✓"
echo ""

echo "=== SCENARIO 5: What You See With kubectl ==="
echo ""
echo "During the rollout:"
echo "  kubectl get rs -n day-ns -w"
echo ""
echo "Output:"
echo "  NAME               DESIRED   CURRENT   READY   AGE"
echo "  day-5d89b7c4f6     2         2         2       5m    ← Old"
echo "  day-7f8c9d2e3a     0         0         0       0s    ← New (just created)"
echo "  day-7f8c9d2e3a     1         0         0       0s    ← Scaling up"
echo "  day-7f8c9d2e3a     1         1         0       1s"
echo "  day-7f8c9d2e3a     1         1         1       10s   ← Ready"
echo "  day-5d89b7c4f6     1         2         2       5m    ← Scaling down"
echo "  day-5d89b7c4f6     1         1         1       5m"
echo "  day-7f8c9d2e3a     2         1         1       11s   ← Scaling up again"
echo "  day-7f8c9d2e3a     2         2         1       11s"
echo "  day-7f8c9d2e3a     2         2         2       20s   ← Ready"
echo "  day-5d89b7c4f6     0         1         1       5m    ← Scaling to 0"
echo "  day-5d89b7c4f6     0         0         0       5m    ← Done"
echo ""

echo "=== SCENARIO 6: The Deployment Manages Both ReplicaSets ==="
echo ""
echo "View the Deployment:"
echo "  kubectl get deployment day -n day-ns -o yaml"
echo ""
echo "Key fields:"
cat << 'EOF'
spec:
  replicas: 2  # ← Total desired replicas
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
status:
  replicas: 2              # Total replicas across all ReplicaSets
  updatedReplicas: 2       # Replicas in new ReplicaSet
  readyReplicas: 2         # Ready replicas
  availableReplicas: 2     # Available replicas
  conditions:
  - type: Progressing
    status: "True"
    reason: NewReplicaSetAvailable
EOF
echo ""

echo "=== SCENARIO 7: How Deployment Controller Decides Scaling ==="
echo ""
echo "Pseudocode:"
cat << 'EOF'
def perform_rolling_update(deployment, old_rs, new_rs):
    desired_replicas = deployment.spec.replicas
    max_surge = deployment.spec.strategy.rollingUpdate.maxSurge
    max_unavailable = deployment.spec.strategy.rollingUpdate.maxUnavailable

    # Calculate limits
    max_total = desired_replicas + max_surge
    min_available = desired_replicas - max_unavailable

    # Current state
    new_ready = count_ready_pods(new_rs)
    old_ready = count_ready_pods(old_rs)
    total_ready = new_ready + old_ready

    # Scale up new ReplicaSet if possible
    if new_rs.replicas < desired_replicas:
        if (new_rs.replicas + old_rs.replicas) < max_total:
            scale_up(new_rs, by=1)
            return

    # Scale down old ReplicaSet if new is ready
    if new_ready > 0 and old_rs.replicas > 0:
        if total_ready > min_available:
            scale_down(old_rs, by=1)
            return

    # Wait for pods to become ready
    wait()
EOF
echo ""

echo "=== SCENARIO 8: Why Keep Old ReplicaSet? ==="
echo ""
echo "After update completes:"
echo "  kubectl get rs -n day-ns"
echo ""
echo "  NAME               DESIRED   CURRENT   READY   AGE"
echo "  day-5d89b7c4f6     0         0         0       10m   ← OLD (kept!)"
echo "  day-7f8c9d2e3a     2         2         2       5m    ← NEW (active)"
echo ""
echo "The old ReplicaSet is kept for ROLLBACK:"
echo ""
echo "  kubectl rollout undo deployment day -n day-ns"
echo ""
echo "What happens:"
echo "  1. Deployment controller scales UP old ReplicaSet (0 → 2)"
echo "  2. Scales DOWN new ReplicaSet (2 → 0)"
echo "  3. Same rolling update process, but in reverse!"
echo ""
echo "Final state after rollback:"
echo "  NAME               DESIRED   CURRENT   READY   AGE"
echo "  day-5d89b7c4f6     2         2         2       15m   ← OLD (active again)"
echo "  day-7f8c9d2e3a     0         0         0       10m   ← NEW (scaled to 0)"
echo ""

echo "=== SCENARIO 9: Multiple Updates Create Multiple ReplicaSets ==="
echo ""
echo "Update 1: v1 → v2"
echo "  day-5d89b7c4f6 (v1, replicas: 0)"
echo "  day-7f8c9d2e3a (v2, replicas: 2) ← active"
echo ""
echo "Update 2: v2 → v3"
echo "  day-5d89b7c4f6 (v1, replicas: 0)"
echo "  day-7f8c9d2e3a (v2, replicas: 0)"
echo "  day-9a1b2c3d4e (v3, replicas: 2) ← active"
echo ""
echo "Update 3: v3 → v4"
echo "  day-5d89b7c4f6 (v1, replicas: 0)"
echo "  day-7f8c9d2e3a (v2, replicas: 0)"
echo "  day-9a1b2c3d4e (v3, replicas: 0)"
echo "  day-1f2a3b4c5d (v4, replicas: 2) ← active"
echo ""
echo "Kubernetes keeps the last 10 ReplicaSets by default"
echo "(configured by spec.revisionHistoryLimit)"
echo ""

echo "=== SCENARIO 10: What About Pods? ==="
echo ""
echo "Pods are NEVER updated in-place!"
echo ""
echo "When ReplicaSet is scaled down:"
echo "  1. ReplicaSet controller deletes oldest Pod"
echo "  2. Kubelet on that node terminates container"
echo "  3. Pod deleted from API server"
echo ""
echo "When ReplicaSet is scaled up:"
echo "  1. ReplicaSet controller creates NEW Pod (from template)"
echo "  2. Scheduler assigns Pod to Node"
echo "  3. Kubelet starts NEW container"
echo ""
echo "Pods are immutable! They're created and deleted, never modified."
echo ""

echo "=== SCENARIO 11: Different Update Strategies ==="
echo ""
echo "Strategy 1: RollingUpdate (default)"
cat << 'EOF'
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1        # Extra pods during update
    maxUnavailable: 0  # Pods that can be unavailable
EOF
echo ""
echo "Result: Gradual replacement, zero downtime"
echo ""
echo "Strategy 2: Recreate"
cat << 'EOF'
strategy:
  type: Recreate
EOF
echo ""
echo "Result: Delete ALL old pods, then create ALL new pods"
echo "  1. Scale old ReplicaSet to 0 (all pods terminated)"
echo "  2. Wait for all pods to terminate"
echo "  3. Scale new ReplicaSet to desired (all pods created)"
echo ""
echo "Use case: When you can't run old and new versions simultaneously"
echo ""

echo "=== SUMMARY ==="
echo ""
echo "How Deployments perform rolling updates:"
echo ""
echo "1. CREATE new ReplicaSet with new pod template"
echo "2. SCALE UP new ReplicaSet (creates new pods)"
echo "3. SCALE DOWN old ReplicaSet (deletes old pods)"
echo "4. REPEAT until new ReplicaSet has all replicas"
echo "5. KEEP old ReplicaSet at 0 replicas for rollback"
echo ""
echo "Key insights:"
echo "  • Deployments DON'T update existing ReplicaSets"
echo "  • Deployments DON'T update existing Pods"
echo "  • Deployments manage MULTIPLE ReplicaSets simultaneously"
echo "  • Each version gets its own ReplicaSet"
echo "  • Pods are immutable (created/deleted, never updated)"
echo "  • Old ReplicaSets kept for rollback capability"
echo ""
echo "The mechanism:"
echo "  Deployment Controller orchestrates TWO ReplicaSet Controllers"
echo "  Each ReplicaSet Controller manages its own set of Pods"
echo ""
