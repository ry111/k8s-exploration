#!/bin/bash
# Demonstration: How ConfigMaps relate to Deployments, ReplicaSets, and Pods

echo "=== SCENARIO 1: ConfigMaps are Standalone Resources ==="
echo ""
echo "Unlike ReplicaSets (which are created BY Deployments),"
echo "ConfigMaps exist independently and are REFERENCED by Pods."
echo ""
cat << 'EOF'
# Create ConfigMap (standalone - no owner)
apiVersion: v1
kind: ConfigMap
metadata:
  name: day-config
  namespace: day-ns
  # NOTE: No ownerReferences!
data:
  ENVIRONMENT: "production"
  PORT: "8001"
  LOG_LEVEL: "info"
EOF
echo ""

echo "=== SCENARIO 2: Deployment References ConfigMap ==="
echo ""
echo "The Deployment's pod template references the ConfigMap:"
echo ""
cat << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: day
spec:
  template:
    spec:
      containers:
      - name: day
        envFrom:
        - configMapRef:
            name: day-config  # ← REFERENCE (not ownership)
EOF
echo ""
echo "Key point: Deployment does NOT create the ConfigMap."
echo "The ConfigMap must already exist!"
echo ""

echo "=== SCENARIO 3: The Reference is Copied Down ==="
echo ""
echo "ReplicaSet (auto-created):"
cat << 'EOF'
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: day-7d4f9c8b5f
  ownerReferences:
  - kind: Deployment
    name: day  # ← ReplicaSet is OWNED by Deployment
spec:
  template:
    spec:
      containers:
      - envFrom:
        - configMapRef:
            name: day-config  # ← Same reference copied
EOF
echo ""
echo "Pod (auto-created):"
cat << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: day-7d4f9c8b5f-abc12
  ownerReferences:
  - kind: ReplicaSet
    name: day-7d4f9c8b5f  # ← Pod is OWNED by ReplicaSet
spec:
  containers:
  - envFrom:
    - configMapRef:
        name: day-config  # ← Same reference copied again
EOF
echo ""

echo "=== SCENARIO 4: Ownership vs Reference ==="
echo ""
echo "OWNERSHIP CHAIN:"
echo "  Deployment → owns → ReplicaSet → owns → Pod"
echo ""
echo "  kubectl delete deployment day"
echo "    ↓"
echo "  Deletes ReplicaSet (garbage collection)"
echo "    ↓"
echo "  Deletes Pods (garbage collection)"
echo ""
echo "REFERENCE (not ownership):"
echo "  Pod → references → ConfigMap"
echo ""
echo "  kubectl delete deployment day"
echo "    ↓"
echo "  ConfigMap is NOT deleted! ✓"
echo ""
echo "  kubectl delete configmap day-config"
echo "    ↓"
echo "  Pods keep running! (they already have the env vars)"
echo "  But new pods will fail to start."
echo ""

echo "=== SCENARIO 5: Creation Order Matters ==="
echo ""
echo "CORRECT order:"
echo "  1. kubectl apply -f configmap.yaml     # Create ConfigMap first"
echo "  2. kubectl apply -f deployment.yaml    # Then Deployment"
echo "     └─→ Creates ReplicaSet"
echo "         └─→ Creates Pods"
echo "             └─→ Kubelet reads ConfigMap and injects into container"
echo ""
echo "WRONG order:"
echo "  1. kubectl apply -f deployment.yaml    # Deployment first"
echo "     └─→ Creates ReplicaSet"
echo "         └─→ Creates Pods"
echo "             └─→ Kubelet tries to read ConfigMap... NOT FOUND!"
echo "                 Pod status: CreateContainerConfigError"
echo ""
echo "  2. kubectl apply -f configmap.yaml     # ConfigMap second"
echo "     └─→ Existing pods WON'T auto-fix!"
echo "         You need to restart them:"
echo "         kubectl rollout restart deployment day -n day-ns"
echo ""

echo "=== SCENARIO 6: Viewing the Relationships ==="
echo ""
echo "View resources:"
echo "  kubectl get configmap,deployment,replicaset,pod -n day-ns"
echo ""
echo "Output:"
echo "  NAME                        DATA   AGE"
echo "  configmap/day-config        4      5m"
echo ""
echo "  NAME                  READY   UP-TO-DATE   AVAILABLE   AGE"
echo "  deployment.apps/day   2/2     2            2           4m"
echo ""
echo "  NAME                             DESIRED   CURRENT   READY   AGE"
echo "  replicaset.apps/day-7d4f9c8b5f   2         2         2       4m"
echo ""
echo "  NAME                       READY   STATUS    RESTARTS   AGE"
echo "  pod/day-7d4f9c8b5f-abc12   1/1     Running   0          4m"
echo "  pod/day-7d4f9c8b5f-def34   1/1     Running   0          4m"
echo ""
echo "Check who owns the ReplicaSet:"
echo "  kubectl get rs day-7d4f9c8b5f -n day-ns -o yaml | grep -A 5 ownerReferences"
echo ""
echo "Output:"
echo "  ownerReferences:"
echo "  - kind: Deployment"
echo "    name: day           # ← ReplicaSet is OWNED by Deployment"
echo ""
echo "Check if ConfigMap is owned by anything:"
echo "  kubectl get configmap day-config -n day-ns -o yaml | grep -A 5 ownerReferences"
echo ""
echo "Output:"
echo "  (nothing - no ownerReferences field)"
echo "  # ← ConfigMap is NOT owned by anyone!"
echo ""

echo "=== SCENARIO 7: ConfigMap Updates Don't Auto-Restart Pods ==="
echo ""
echo "Initial state:"
echo "  ConfigMap: LOG_LEVEL=info"
echo "  Pod environment: LOG_LEVEL=info ✓"
echo ""
echo "Update ConfigMap:"
echo "  kubectl patch configmap day-config -n day-ns \\"
echo "    --type merge -p '{\"data\":{\"LOG_LEVEL\":\"debug\"}}'"
echo ""
echo "Check pod environment:"
echo "  kubectl exec day-7d4f9c8b5f-abc12 -n day-ns -- env | grep LOG_LEVEL"
echo "  LOG_LEVEL=info  # ← Still the OLD value!"
echo ""
echo "Why? Environment variables are set when container STARTS."
echo "The ConfigMap update doesn't restart the container."
echo ""
echo "Fix: Restart the pods:"
echo "  kubectl rollout restart deployment day -n day-ns"
echo ""
echo "Now pods get the new value:"
echo "  kubectl exec day-7d4f9c8b5f-xyz99 -n day-ns -- env | grep LOG_LEVEL"
echo "  LOG_LEVEL=debug  # ← New value! ✓"
echo ""

echo "=== SCENARIO 8: ConfigMaps Can Be Shared ==="
echo ""
echo "One ConfigMap, multiple Deployments:"
echo ""
cat << 'EOF'
# Shared ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: database-config
data:
  DB_HOST: "postgres.example.com"
  DB_PORT: "5432"
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
            name: database-config  # ← Shared
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
EOF
echo ""
echo "Both deployments share the same config!"
echo "Update database-config → affects both deployments"
echo ""

echo "=== SCENARIO 9: How ConfigMap Data Becomes Environment Variables ==="
echo ""
echo "ConfigMap data:"
cat << 'EOF'
data:
  ENVIRONMENT: "production"
  PORT: "8001"
  LOG_LEVEL: "info"
  SERVICE_NAME: "Day"
EOF
echo ""
echo "Referenced in Deployment:"
cat << 'EOF'
envFrom:
- configMapRef:
    name: day-config
EOF
echo ""
echo "Results in container environment variables:"
echo "  ENVIRONMENT=production"
echo "  PORT=8001"
echo "  LOG_LEVEL=info"
echo "  SERVICE_NAME=Day"
echo ""
echo "Process:"
echo "  1. Deployment defines pod template with ConfigMap reference"
echo "  2. ReplicaSet copies the pod template"
echo "  3. ReplicaSet creates Pods with the reference"
echo "  4. Scheduler assigns Pod to a Node"
echo "  5. Kubelet on that Node:"
echo "     a. Sees the configMapRef in pod spec"
echo "     b. Fetches ConfigMap data from API server"
echo "     c. Creates environment variables from ConfigMap data"
echo "     d. Starts container with those env vars"
echo ""

echo "=== SUMMARY ==="
echo ""
echo "┌─────────────────────────────────────────────────┐"
echo "│ ConfigMap (standalone)                          │"
echo "│ - Not created by Deployment                     │"
echo "│ - Not owned by Deployment                       │"
echo "│ - Exists independently                          │"
echo "└──────────────────┬──────────────────────────────┘"
echo "                   │"
echo "                   │ referenced by (not owned by)"
echo "                   ↓"
echo "┌─────────────────────────────────────────────────┐"
echo "│ Deployment                                      │"
echo "│ - References ConfigMap in pod template          │"
echo "└──────────────────┬──────────────────────────────┘"
echo "                   │ creates & owns"
echo "                   ↓"
echo "┌─────────────────────────────────────────────────┐"
echo "│ ReplicaSet                                      │"
echo "│ - Copies ConfigMap reference                    │"
echo "└──────────────────┬──────────────────────────────┘"
echo "                   │ creates & owns"
echo "                   ↓"
echo "┌─────────────────────────────────────────────────┐"
echo "│ Pod                                             │"
echo "│ - Uses ConfigMap reference at runtime           │"
echo "│ - Kubelet injects ConfigMap data into container │"
echo "└─────────────────────────────────────────────────┘"
echo ""
echo "Key Differences:"
echo ""
echo "  Ownership (Deployment → ReplicaSet → Pod):"
echo "    - Parent creates child"
echo "    - ownerReferences field exists"
echo "    - Deleting parent deletes children"
echo ""
echo "  Reference (Pod → ConfigMap):"
echo "    - Child references parent"
echo "    - No ownerReferences"
echo "    - Deleting Deployment doesn't delete ConfigMap"
echo "    - ConfigMap can be shared by multiple resources"
echo ""
