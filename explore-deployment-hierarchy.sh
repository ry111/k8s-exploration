#!/bin/bash
# Demonstration: How Deployments create ReplicaSets which create Pods

echo "=== SCENARIO 1: Create a Deployment ==="
echo "When you apply this deployment:"
cat << 'EOF'
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
EOF

echo ""
echo "=== SCENARIO 2: What Gets Created ==="
echo ""
echo "1. Deployment is created:"
echo "   kubectl get deployment -n day-ns"
echo "   NAME   READY   UP-TO-DATE   AVAILABLE   AGE"
echo "   day    2/2     2            2           1m"
echo ""
echo "2. Deployment creates a ReplicaSet (note the random suffix):"
echo "   kubectl get replicaset -n day-ns"
echo "   NAME             DESIRED   CURRENT   READY   AGE"
echo "   day-7d4f9c8b5f   2         2         2       1m"
echo "                ^^^^^^^^^^^ random hash from pod template"
echo ""
echo "3. ReplicaSet creates 2 Pods (each with random suffix):"
echo "   kubectl get pods -n day-ns"
echo "   NAME                   READY   STATUS    RESTARTS   AGE"
echo "   day-7d4f9c8b5f-abc12   1/1     Running   0          1m"
echo "   day-7d4f9c8b5f-def34   1/1     Running   0          1m"
echo "   ^^^^^^^^^^^^^^^ ReplicaSet name + random suffix"
echo ""

echo "=== SCENARIO 3: See the Ownership Chain ==="
echo ""
echo "Check who owns the ReplicaSet:"
echo "   kubectl get replicaset -n day-ns day-7d4f9c8b5f -o yaml | grep -A 5 ownerReferences"
echo ""
echo "Output:"
echo "   ownerReferences:"
echo "   - apiVersion: apps/v1"
echo "     kind: Deployment"
echo "     name: day          ← ReplicaSet is owned by Deployment"
echo ""
echo "Check who owns a Pod:"
echo "   kubectl get pod -n day-ns day-7d4f9c8b5f-abc12 -o yaml | grep -A 5 ownerReferences"
echo ""
echo "Output:"
echo "   ownerReferences:"
echo "   - apiVersion: apps/v1"
echo "     kind: ReplicaSet"
echo "     name: day-7d4f9c8b5f    ← Pod is owned by ReplicaSet"
echo ""

echo "=== SCENARIO 4: Test Self-Healing ==="
echo ""
echo "Delete a pod manually:"
echo "   kubectl delete pod day-7d4f9c8b5f-abc12 -n day-ns"
echo ""
echo "Immediately check pods:"
echo "   kubectl get pods -n day-ns"
echo "   NAME                   READY   STATUS              RESTARTS   AGE"
echo "   day-7d4f9c8b5f-def34   1/1     Running             0          2m"
echo "   day-7d4f9c8b5f-xyz99   0/1     ContainerCreating   0          1s  ← NEW POD!"
echo ""
echo "The ReplicaSet controller noticed: 'I only have 1 pod, but need 2!'"
echo "So it immediately created a replacement pod."
echo ""

echo "=== SCENARIO 5: Rolling Update ==="
echo ""
echo "Update the deployment image:"
echo "   kubectl set image deployment/day day=day:v2 -n day-ns"
echo ""
echo "Watch what happens:"
echo "   kubectl get replicaset -n day-ns"
echo "   NAME             DESIRED   CURRENT   READY   AGE"
echo "   day-7d4f9c8b5f   0         0         0       5m   ← OLD ReplicaSet (scaled to 0)"
echo "   day-8f5a3c9d2e   2         2         2       10s  ← NEW ReplicaSet created!"
echo "                ^^^^^^^^^^^ different hash (new pod template)"
echo ""
echo "The Deployment:"
echo "  1. Created a NEW ReplicaSet for the new image"
echo "  2. Gradually scaled it up (0 → 1 → 2)"
echo "  3. Gradually scaled down old ReplicaSet (2 → 1 → 0)"
echo "  4. Kept old ReplicaSet for rollback capability"
echo ""

echo "=== SCENARIO 6: The Controller Loop ==="
echo ""
echo "Each controller continuously runs this logic:"
echo ""
cat << 'EOF'
while true:
    current_state = get_current_state()
    desired_state = get_desired_state()

    if current_state != desired_state:
        reconcile(current_state, desired_state)

    sleep(short_time)
EOF
echo ""
echo "Example for ReplicaSet controller:"
echo ""
cat << 'EOF'
desired_replicas = 2
current_pods = count_pods_with_matching_labels()

if current_pods < desired_replicas:
    create_pod()
elif current_pods > desired_replicas:
    delete_oldest_pod()
EOF
echo ""

echo "=== SUMMARY ==="
echo ""
echo "Deployment → ReplicaSet → Pods"
echo "     ↓            ↓          ↓"
echo "  Manages     Ensures    Runs your"
echo "  rollouts    replica    containers"
echo "             count"
echo ""
echo "You never create Pods directly in production!"
echo "You create Deployments, and the controllers handle the rest."
