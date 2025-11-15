# HPA Change Safety: Preventing Dangerous Scale-Downs

## The Problem

**Scenario:** Your HPA is currently running at capacity, then someone reduces maxReplicas.

```yaml
# Current state: HPA running at max capacity
Current replicas: 10
HPA maxReplicas: 10
CPU utilization: 80% (at target)

# Someone updates HPA
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp
spec:
  maxReplicas: 5  # ← Changed from 10 to 5
  minReplicas: 2
  targetCPUUtilizationPercentage: 80
```

**What happens immediately:**

```
T+0s:  HPA update applied
T+1s:  HPA controller sees: current=10, max=5
       HPA scales down from 10 to 5 pods IMMEDIATELY
       5 pods terminate at once

T+10s: Service degraded - only 5 pods handling 10 pods worth of traffic
       CPU utilization spikes to 160%
       Response times increase
       Error rate increases

T+30s: Pods might crash from overload
       CPU throttling kicks in
       Users experience outage
```

**This is catastrophic!** You need multiple layers of defense.

---

## Defense Layer 1: Validation Admission Webhook

**Prevent dangerous HPA changes before they're applied.**

### Implementation

```python
# hpa-validator-webhook.py
from flask import Flask, request, jsonify
import logging

app = Flask(__name__)

@app.route('/validate-hpa', methods=['POST'])
def validate_hpa():
    """Validate HPA changes before they're applied"""

    admission_review = request.get_json()
    request_obj = admission_review['request']

    # Get the new HPA spec
    new_hpa = request_obj['object']
    namespace = new_hpa['metadata']['namespace']
    name = new_hpa['metadata']['name']

    # For UPDATE operations, we get the old object too
    if request_obj['operation'] == 'UPDATE':
        old_hpa = request_obj['oldObject']

        # Check if maxReplicas is being reduced
        old_max = old_hpa['spec']['maxReplicas']
        new_max = new_hpa['spec']['maxReplicas']

        if new_max < old_max:
            # Get current replica count from deployment
            current_replicas = get_current_replicas(namespace, name)

            # RULE 1: Don't allow maxReplicas below current count
            if new_max < current_replicas:
                return jsonify({
                    'apiVersion': 'admission.k8s.io/v1',
                    'kind': 'AdmissionReview',
                    'response': {
                        'uid': request_obj['uid'],
                        'allowed': False,
                        'status': {
                            'code': 400,
                            'message': f'DANGEROUS: Cannot set maxReplicas={new_max} '
                                     f'when currently running {current_replicas} replicas. '
                                     f'Scale down the deployment first, then reduce maxReplicas.'
                        }
                    }
                })

            # RULE 2: Don't allow reduction > 50% in one change
            reduction_pct = ((old_max - new_max) / old_max) * 100
            if reduction_pct > 50:
                return jsonify({
                    'apiVersion': 'admission.k8s.io/v1',
                    'kind': 'AdmissionReview',
                    'response': {
                        'uid': request_obj['uid'],
                        'allowed': False,
                        'status': {
                            'code': 400,
                            'message': f'DANGEROUS: Reducing maxReplicas by {reduction_pct:.0f}% '
                                     f'({old_max} → {new_max}) in one change. '
                                     f'Reduce gradually to prevent outages.'
                        }
                    }
                })

            # RULE 3: Require annotation for large reductions
            annotations = new_hpa['metadata'].get('annotations', {})
            if reduction_pct > 30 and annotations.get('hpa.approved') != 'true':
                return jsonify({
                    'apiVersion': 'admission.k8s.io/v1',
                    'kind': 'AdmissionReview',
                    'response': {
                        'uid': request_obj['uid'],
                        'allowed': False,
                        'status': {
                            'code': 400,
                            'message': f'Large HPA reduction ({old_max} → {new_max}) requires approval. '
                                     f'Add annotation: hpa.approved=true'
                        }
                    }
                })

    # Check minReplicas sanity
    min_replicas = new_hpa['spec']['minReplicas']
    max_replicas = new_hpa['spec']['maxReplicas']

    if min_replicas > max_replicas:
        return jsonify({
            'apiVersion': 'admission.k8s.io/v1',
            'kind': 'AdmissionReview',
            'response': {
                'uid': request_obj['uid'],
                'allowed': False,
                'status': {
                    'code': 400,
                    'message': f'Invalid: minReplicas ({min_replicas}) > maxReplicas ({max_replicas})'
                }
            }
        })

    # Check minReplicas against PodDisruptionBudget
    pdb = get_pdb_for_deployment(namespace, name)
    if pdb and pdb['spec'].get('minAvailable'):
        min_available = pdb['spec']['minAvailable']
        if min_replicas < min_available:
            return jsonify({
                'apiVersion': 'admission.k8s.io/v1',
                'kind': 'AdmissionReview',
                'response': {
                    'uid': request_obj['uid'],
                    'allowed': False,
                    'status': {
                        'code': 400,
                        'message': f'HPA minReplicas ({min_replicas}) is less than '
                                 f'PodDisruptionBudget minAvailable ({min_available}). '
                                 f'This could prevent deployments from completing.'
                    }
                }
            })

    # All checks passed
    return jsonify({
        'apiVersion': 'admission.k8s.io/v1',
        'kind': 'AdmissionReview',
        'response': {
            'uid': request_obj['uid'],
            'allowed': True
        }
    })

def get_current_replicas(namespace, hpa_name):
    """Get current replica count for the HPA's target deployment"""
    from kubernetes import client, config

    config.load_incluster_config()
    apps_v1 = client.AppsV1Api()
    autoscaling_v2 = client.AutoscalingV2Api()

    # Get HPA to find target deployment
    hpa = autoscaling_v2.read_namespaced_horizontal_pod_autoscaler(hpa_name, namespace)
    target_ref = hpa.spec.scale_target_ref

    if target_ref.kind == 'Deployment':
        deployment = apps_v1.read_namespaced_deployment(target_ref.name, namespace)
        return deployment.status.replicas or 0

    return 0

def get_pdb_for_deployment(namespace, hpa_name):
    """Get PodDisruptionBudget for the deployment"""
    from kubernetes import client

    policy_v1 = client.PolicyV1Api()

    try:
        pdbs = policy_v1.list_namespaced_pod_disruption_budget(namespace)
        # Find PDB matching the deployment
        # (simplified - would need to match labels)
        for pdb in pdbs.items:
            return pdb.to_dict()
    except:
        return None

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8443, ssl_context='adhoc')
```

### Deploy the Webhook

```yaml
# hpa-validator-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hpa-validator
  namespace: validators
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hpa-validator
  template:
    metadata:
      labels:
        app: hpa-validator
    spec:
      serviceAccountName: hpa-validator
      containers:
      - name: validator
        image: myorg/hpa-validator:v1
        ports:
        - containerPort: 8443
        volumeMounts:
        - name: certs
          mountPath: /certs
          readOnly: true
      volumes:
      - name: certs
        secret:
          secretName: hpa-validator-certs
---
apiVersion: v1
kind: Service
metadata:
  name: hpa-validator
  namespace: validators
spec:
  selector:
    app: hpa-validator
  ports:
  - port: 443
    targetPort: 8443
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: hpa-validator
  namespace: validators
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: hpa-validator
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list"]
- apiGroups: ["autoscaling"]
  resources: ["horizontalpodautoscalers"]
  verbs: ["get", "list"]
- apiGroups: ["policy"]
  resources: ["poddisruptionbudgets"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: hpa-validator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: hpa-validator
subjects:
- kind: ServiceAccount
  name: hpa-validator
  namespace: validators
```

### Register the Webhook

```yaml
# validating-webhook-config.yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: hpa-validator
webhooks:
- name: validate-hpa.example.com
  admissionReviewVersions: ["v1"]
  sideEffects: None
  failurePolicy: Fail  # Block changes if webhook fails

  clientConfig:
    service:
      name: hpa-validator
      namespace: validators
      path: /validate-hpa
    caBundle: LS0tLS1CRUdJTi... # base64 CA cert

  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: ["autoscaling"]
    apiVersions: ["v1", "v2", "v2beta2"]
    resources: ["horizontalpodautoscalers"]

  namespaceSelector:
    matchLabels:
      validate-hpa: "true"  # Only validate in marked namespaces
```

### Example: Webhook Blocking Dangerous Change

```bash
# Current state: 10 pods running
kubectl get hpa myapp -n production
# NAME    REFERENCE          TARGETS   MINPODS   MAXPODS   REPLICAS
# myapp   Deployment/myapp   80%/80%   2         10        10

# Try to reduce maxReplicas below current count
kubectl patch hpa myapp -n production -p '{"spec":{"maxReplicas":5}}'

# Output:
Error from server: admission webhook "validate-hpa.example.com" denied the request:
DANGEROUS: Cannot set maxReplicas=5 when currently running 10 replicas.
Scale down the deployment first, then reduce maxReplicas.

# Safe approach: Scale down first
kubectl scale deployment myapp -n production --replicas=6
# Wait for scale down to complete

kubectl get deployment myapp -n production
# NAME    READY   UP-TO-DATE   AVAILABLE
# myapp   6/6     6            6

# Now reduce HPA maxReplicas
kubectl patch hpa myapp -n production -p '{"spec":{"maxReplicas":8}}'
# Success! ✓
```

---

## Defense Layer 2: PodDisruptionBudget

**Limit how many pods can be terminated simultaneously.**

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb
  namespace: production
spec:
  minAvailable: 8  # At least 8 pods must stay available
  selector:
    matchLabels:
      app: myapp
```

**What this does:**

```
Current: 10 pods running
HPA maxReplicas reduced to 5

HPA tries to scale down from 10 → 5 (delete 5 pods)
    ↓
PDB blocks the scale-down
    ↓
Only allows scaling to minAvailable (8 pods)
    ↓
Result: 8 pods remain (not 5)
    ↓
HPA will keep trying to scale down
But PDB prevents going below 8
```

**Important:** PDB doesn't prevent the configuration change, it just slows down the scale-down. You still need validation webhooks.

### Dynamic PDB Based on Load

```yaml
# Use percentage instead of absolute number
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb
spec:
  minAvailable: 80%  # At least 80% of pods must stay available
  selector:
    matchLabels:
      app: myapp
```

**Example:**
- 10 pods running → minAvailable = 8 pods (80%)
- 20 pods running → minAvailable = 16 pods (80%)

---

## Defense Layer 3: Pre-Change Validation in CI/CD

**Validate HPA changes before they reach the cluster.**

```yaml
# .github/workflows/validate-hpa.yaml
name: Validate HPA Changes

on:
  pull_request:
    paths:
      - 'k8s/hpa/*.yaml'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Get current HPA state
        run: |
          # Query production cluster
          CURRENT_REPLICAS=$(kubectl get hpa myapp -n production -o jsonpath='{.status.currentReplicas}')
          CURRENT_MAX=$(kubectl get hpa myapp -n production -o jsonpath='{.spec.maxReplicas}')

          echo "current_replicas=$CURRENT_REPLICAS" >> $GITHUB_ENV
          echo "current_max=$CURRENT_MAX" >> $GITHUB_ENV

      - name: Parse new HPA spec
        run: |
          NEW_MAX=$(yq eval '.spec.maxReplicas' k8s/hpa/myapp.yaml)
          NEW_MIN=$(yq eval '.spec.minReplicas' k8s/hpa/myapp.yaml)

          echo "new_max=$NEW_MAX" >> $GITHUB_ENV
          echo "new_min=$NEW_MIN" >> $GITHUB_ENV

      - name: Validate maxReplicas reduction
        run: |
          if [ $NEW_MAX -lt $CURRENT_REPLICAS ]; then
            echo "❌ DANGER: New maxReplicas ($NEW_MAX) is less than current replicas ($CURRENT_REPLICAS)"
            echo "This would cause immediate scale-down and potential outage."
            echo ""
            echo "Safe approach:"
            echo "1. Manually scale deployment to $NEW_MAX or below"
            echo "2. Wait for scale-down to complete"
            echo "3. Then update HPA maxReplicas"
            exit 1
          fi

      - name: Validate reduction size
        run: |
          REDUCTION=$(( $CURRENT_MAX - $NEW_MAX ))
          REDUCTION_PCT=$(( $REDUCTION * 100 / $CURRENT_MAX ))

          if [ $REDUCTION_PCT -gt 50 ]; then
            echo "❌ DANGER: Reducing maxReplicas by $REDUCTION_PCT% in one change"
            echo "Old max: $CURRENT_MAX"
            echo "New max: $NEW_MAX"
            echo ""
            echo "Reduce gradually (max 50% at a time) to prevent issues."
            exit 1
          fi

      - name: Check minReplicas vs PDB
        run: |
          PDB_MIN=$(kubectl get pdb myapp-pdb -n production -o jsonpath='{.spec.minAvailable}')

          if [ $NEW_MIN -lt $PDB_MIN ]; then
            echo "❌ CONFLICT: HPA minReplicas ($NEW_MIN) < PDB minAvailable ($PDB_MIN)"
            echo "This could prevent rolling updates from completing."
            exit 1
          fi

      - name: Validation passed
        run: |
          echo "✅ HPA change validation passed"
          echo "Old: minReplicas=$CURRENT_MIN, maxReplicas=$CURRENT_MAX"
          echo "New: minReplicas=$NEW_MIN, maxReplicas=$NEW_MAX"
          echo "Current replicas: $CURRENT_REPLICAS"
```

---

## Defense Layer 4: Gradual HPA Reduction Script

**Automate safe step-down of maxReplicas.**

```bash
#!/bin/bash
# gradual-hpa-reduction.sh

set -e

NAMESPACE="production"
HPA_NAME="myapp"
TARGET_MAX=$1
STEP_SIZE=${2:-2}  # Reduce by 2 at a time
WAIT_TIME=${3:-60}  # Wait 60s between steps

if [ -z "$TARGET_MAX" ]; then
  echo "Usage: $0 <target-max-replicas> [step-size] [wait-seconds]"
  echo "Example: $0 5 2 60"
  exit 1
fi

# Get current state
CURRENT_MAX=$(kubectl get hpa $HPA_NAME -n $NAMESPACE -o jsonpath='{.spec.maxReplicas}')
CURRENT_REPLICAS=$(kubectl get hpa $HPA_NAME -n $NAMESPACE -o jsonpath='{.status.currentReplicas}')

echo "Current HPA state:"
echo "  maxReplicas: $CURRENT_MAX"
echo "  currentReplicas: $CURRENT_REPLICAS"
echo ""
echo "Target: $TARGET_MAX"
echo ""

if [ $TARGET_MAX -ge $CURRENT_MAX ]; then
  echo "Target is >= current max. No reduction needed."
  exit 0
fi

if [ $TARGET_MAX -lt $CURRENT_REPLICAS ]; then
  echo "❌ DANGER: Target maxReplicas ($TARGET_MAX) is less than current replicas ($CURRENT_REPLICAS)"
  echo "This would cause immediate scale-down."
  echo ""
  read -p "Scale down deployment first? (yes/no): " CONFIRM

  if [ "$CONFIRM" = "yes" ]; then
    echo "Scaling deployment to $TARGET_MAX replicas..."
    kubectl scale deployment $HPA_NAME -n $NAMESPACE --replicas=$TARGET_MAX

    echo "Waiting for scale-down to complete..."
    kubectl wait --for=jsonpath='{.status.replicas}'=$TARGET_MAX \
      deployment/$HPA_NAME -n $NAMESPACE --timeout=300s

    echo "✓ Deployment scaled down"
  else
    echo "Aborted."
    exit 1
  fi
fi

# Gradually reduce maxReplicas
NEXT_MAX=$CURRENT_MAX

while [ $NEXT_MAX -gt $TARGET_MAX ]; do
  NEXT_MAX=$(( $NEXT_MAX - $STEP_SIZE ))

  # Don't go below target
  if [ $NEXT_MAX -lt $TARGET_MAX ]; then
    NEXT_MAX=$TARGET_MAX
  fi

  echo "Reducing maxReplicas: $CURRENT_MAX → $NEXT_MAX"

  kubectl patch hpa $HPA_NAME -n $NAMESPACE --type=merge -p "{\"spec\":{\"maxReplicas\":$NEXT_MAX}}"

  if [ $NEXT_MAX -gt $TARGET_MAX ]; then
    echo "Waiting ${WAIT_TIME}s before next step..."
    sleep $WAIT_TIME

    # Check current replicas
    CURRENT_REPLICAS=$(kubectl get hpa $HPA_NAME -n $NAMESPACE -o jsonpath='{.status.currentReplicas}')
    echo "Current replicas: $CURRENT_REPLICAS"
  fi

  CURRENT_MAX=$NEXT_MAX
done

echo ""
echo "✅ HPA maxReplicas safely reduced to $TARGET_MAX"
kubectl get hpa $HPA_NAME -n $NAMESPACE
```

**Usage:**

```bash
# Reduce from 10 to 5, stepping down by 2, waiting 60s between steps
./gradual-hpa-reduction.sh 5 2 60

# Output:
Current HPA state:
  maxReplicas: 10
  currentReplicas: 10

Target: 5

Reducing maxReplicas: 10 → 8
Waiting 60s before next step...
Current replicas: 8

Reducing maxReplicas: 8 → 6
Waiting 60s before next step...
Current replicas: 6

Reducing maxReplicas: 6 → 5

✅ HPA maxReplicas safely reduced to 5
NAME    REFERENCE          TARGETS   MINPODS   MAXPODS   REPLICAS
myapp   Deployment/myapp   75%/80%   2         5         5
```

---

## Defense Layer 5: Policy Enforcement with OPA/Kyverno

**Declarative policies to prevent dangerous changes.**

### Using Kyverno

```yaml
# kyverno-hpa-policy.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: hpa-safety-checks
spec:
  validationFailureAction: enforce  # Block invalid changes
  background: false
  rules:

  # Rule 1: Prevent maxReplicas reduction > 50%
  - name: prevent-large-max-reduction
    match:
      any:
      - resources:
          kinds:
          - HorizontalPodAutoscaler
    preconditions:
      all:
      - key: "{{ request.operation }}"
        operator: Equals
        value: UPDATE
      - key: "{{ request.object.spec.maxReplicas }}"
        operator: LessThan
        value: "{{ request.oldObject.spec.maxReplicas }}"
    validate:
      message: >-
        Large HPA maxReplicas reduction detected.
        Reducing from {{ request.oldObject.spec.maxReplicas }} to {{ request.object.spec.maxReplicas }}.
        Reduce gradually to prevent outages.
      deny:
        conditions:
          all:
          - key: "{{ divide(subtract(request.oldObject.spec.maxReplicas, request.object.spec.maxReplicas), request.oldObject.spec.maxReplicas) }}"
            operator: GreaterThan
            value: 0.5  # 50% reduction

  # Rule 2: Prevent maxReplicas below current count
  - name: prevent-max-below-current
    match:
      any:
      - resources:
          kinds:
          - HorizontalPodAutoscaler
    preconditions:
      all:
      - key: "{{ request.operation }}"
        operator: Equals
        value: UPDATE
    validate:
      message: >-
        Cannot set maxReplicas to {{ request.object.spec.maxReplicas }}
        when current replicas is {{ request.oldObject.status.currentReplicas }}.
        Scale down the deployment first.
      deny:
        conditions:
          all:
          - key: "{{ request.object.spec.maxReplicas }}"
            operator: LessThan
            value: "{{ request.oldObject.status.currentReplicas }}"

  # Rule 3: Require approval annotation for reductions
  - name: require-approval-for-reduction
    match:
      any:
      - resources:
          kinds:
          - HorizontalPodAutoscaler
    preconditions:
      all:
      - key: "{{ request.operation }}"
        operator: Equals
        value: UPDATE
      - key: "{{ request.object.spec.maxReplicas }}"
        operator: LessThan
        value: "{{ request.oldObject.spec.maxReplicas }}"
    validate:
      message: >-
        HPA maxReplicas reduction requires approval annotation.
        Add: hpa.approved=true to metadata.annotations
      pattern:
        metadata:
          annotations:
            hpa.approved: "true"
```

**Install Kyverno:**

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm install kyverno kyverno/kyverno -n kyverno --create-namespace

# Apply policy
kubectl apply -f kyverno-hpa-policy.yaml
```

**Example: Policy blocking dangerous change:**

```bash
kubectl patch hpa myapp -n production -p '{"spec":{"maxReplicas":3}}'

# Output:
Error from server: admission webhook "validate.kyverno.svc" denied the request:

policy HorizontalPodAutoscaler/production/myapp for resource violation:

hpa-safety-checks:
  prevent-max-below-current: 'validation error: Cannot set maxReplicas to 3 when
    current replicas is 10. Scale down the deployment first.'
```

---

## Defense Layer 6: Monitoring and Alerting

**Detect when HPA is at capacity and alert before changes.**

### Prometheus Alert

```yaml
# prometheus-hpa-alerts.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-hpa-alerts
  namespace: monitoring
data:
  hpa-alerts.yaml: |
    groups:
    - name: hpa
      interval: 30s
      rules:

      # Alert when HPA is at max capacity
      - alert: HPAAtMaxCapacity
        expr: |
          kube_horizontalpodautoscaler_status_current_replicas
          >=
          kube_horizontalpodautoscaler_spec_max_replicas
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "HPA {{ $labels.horizontalpodautoscaler }} at max capacity"
          description: |
            HPA {{ $labels.horizontalpodautoscaler }} in namespace {{ $labels.namespace }}
            has been at maximum capacity for 5 minutes.
            Current: {{ $value }} replicas
            Max: {{ $labels.max_replicas }} replicas

            Consider increasing maxReplicas if load is legitimate.

            ⚠️  WARNING: Do NOT reduce maxReplicas while at capacity!

      # Alert on large HPA maxReplicas reduction
      - alert: HPAMaxReplicasReduced
        expr: |
          (
            kube_horizontalpodautoscaler_spec_max_replicas
            -
            kube_horizontalpodautoscaler_spec_max_replicas offset 5m
          ) < -3  # Reduced by more than 3
        labels:
          severity: critical
        annotations:
          summary: "HPA maxReplicas significantly reduced"
          description: |
            HPA {{ $labels.horizontalpodautoscaler }} maxReplicas reduced by {{ $value }}.

            Monitor for:
            - Increased error rates
            - Increased latency
            - CPU/memory saturation

            Rollback if service degrades.

      # Alert when current > max (shouldn't happen, but detect it)
      - alert: HPACurrentExceedsMax
        expr: |
          kube_horizontalpodautoscaler_status_current_replicas
          >
          kube_horizontalpodautoscaler_spec_max_replicas
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "HPA current replicas exceeds max"
          description: |
            HPA {{ $labels.horizontalpodautoscaler }} has more replicas than max!
            Current: {{ $value }}
            Max: {{ $labels.max_replicas }}

            This indicates a race condition or bug.
```

### Grafana Dashboard

```json
{
  "dashboard": {
    "title": "HPA Safety Monitoring",
    "panels": [
      {
        "title": "HPA Utilization",
        "targets": [
          {
            "expr": "kube_horizontalpodautoscaler_status_current_replicas / kube_horizontalpodautoscaler_spec_max_replicas * 100"
          }
        ],
        "alert": {
          "conditions": [
            {
              "evaluator": {
                "type": "gt",
                "params": [90]
              }
            }
          ],
          "notifications": [
            {
              "uid": "slack-oncall"
            }
          ]
        }
      }
    ]
  }
}
```

---

## Defense Layer 7: GitOps Review Process

**Require human review for HPA changes.**

```yaml
# .github/CODEOWNERS
# Require SRE team approval for HPA changes
k8s/hpa/*.yaml @sre-team
k8s/*/hpa.yaml @sre-team
```

```yaml
# .github/workflows/hpa-review.yaml
name: HPA Change Review

on:
  pull_request:
    paths:
      - 'k8s/hpa/*.yaml'

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Analyze HPA changes
        id: analyze
        run: |
          # Get changed files
          git diff origin/main...HEAD --name-only | grep 'hpa\.yaml' > changed_hpas.txt

          # Analyze each change
          for file in $(cat changed_hpas.txt); do
            OLD_MAX=$(git show origin/main:$file | yq eval '.spec.maxReplicas')
            NEW_MAX=$(yq eval '.spec.maxReplicas' $file)

            if [ $NEW_MAX -lt $OLD_MAX ]; then
              echo "⚠️  $file: maxReplicas reduced from $OLD_MAX to $NEW_MAX"
              echo "::warning file=$file::HPA maxReplicas reduction detected"
            fi
          done

      - name: Comment on PR
        uses: actions/github-script@v6
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `## HPA Change Review Required

              This PR modifies HPA configurations. Please verify:

              - [ ] Current replica count checked (not at max capacity)
              - [ ] Load testing performed at new scale
              - [ ] Monitoring dashboards reviewed
              - [ ] Rollback plan documented
              - [ ] Change approved by SRE team

              **Validation checklist:**
              \`\`\`bash
              # Check current state
              kubectl get hpa -n production

              # Check pod count
              kubectl get deployment -n production

              # Check metrics
              kubectl top pods -n production
              \`\`\`
              `
            })
```

---

## Complete Safety Checklist

Before reducing HPA maxReplicas:

```bash
#!/bin/bash
# pre-hpa-reduction-checklist.sh

NAMESPACE="production"
HPA_NAME="myapp"
NEW_MAX=$1

echo "HPA Reduction Safety Checklist"
echo "================================"
echo ""

# 1. Check current state
CURRENT_MAX=$(kubectl get hpa $HPA_NAME -n $NAMESPACE -o jsonpath='{.spec.maxReplicas}')
CURRENT_MIN=$(kubectl get hpa $HPA_NAME -n $NAMESPACE -o jsonpath='{.spec.minReplicas}')
CURRENT_REPLICAS=$(kubectl get hpa $HPA_NAME -n $NAMESPACE -o jsonpath='{.status.currentReplicas}')
DESIRED_REPLICAS=$(kubectl get hpa $HPA_NAME -n $NAMESPACE -o jsonpath='{.status.desiredReplicas}')

echo "1. Current HPA State"
echo "   Current maxReplicas: $CURRENT_MAX"
echo "   Current minReplicas: $CURRENT_MIN"
echo "   Current replicas: $CURRENT_REPLICAS"
echo "   Desired replicas: $DESIRED_REPLICAS"
echo "   Target maxReplicas: $NEW_MAX"
echo ""

# 2. Check if at capacity
if [ $CURRENT_REPLICAS -ge $CURRENT_MAX ]; then
  echo "   ❌ DANGER: HPA is at max capacity!"
  echo "      Do NOT reduce maxReplicas now."
  SAFE=false
else
  echo "   ✓ HPA not at max capacity"
  SAFE=true
fi
echo ""

# 3. Check if target is below current
if [ $NEW_MAX -lt $CURRENT_REPLICAS ]; then
  echo "2. Target Check"
  echo "   ❌ DANGER: Target maxReplicas ($NEW_MAX) < current replicas ($CURRENT_REPLICAS)"
  echo "      This would cause immediate scale-down!"
  SAFE=false
else
  echo "2. Target Check"
  echo "   ✓ Target maxReplicas > current replicas"
fi
echo ""

# 4. Check recent load trends
echo "3. Recent Load Trends (last 6 hours)"
kubectl top pods -n $NAMESPACE -l app=$HPA_NAME --no-headers | \
  awk '{cpu+=$2; mem+=$3} END {print "   Avg CPU:", cpu/NR "m, Avg Mem:", mem/NR "Mi"}'

# 5. Check PDB
PDB_MIN=$(kubectl get pdb ${HPA_NAME}-pdb -n $NAMESPACE -o jsonpath='{.spec.minAvailable}' 2>/dev/null)
if [ -n "$PDB_MIN" ]; then
  echo ""
  echo "4. PodDisruptionBudget"
  echo "   PDB minAvailable: $PDB_MIN"

  if [ $NEW_MAX -lt $PDB_MIN ]; then
    echo "   ❌ WARNING: New maxReplicas ($NEW_MAX) < PDB minAvailable ($PDB_MIN)"
    SAFE=false
  else
    echo "   ✓ Compatible with PDB"
  fi
fi
echo ""

# 6. Summary
echo "================================"
if [ "$SAFE" = "true" ]; then
  echo "✅ SAFE to proceed with HPA reduction"
  echo ""
  echo "Recommended command:"
  echo "  kubectl patch hpa $HPA_NAME -n $NAMESPACE -p '{\"spec\":{\"maxReplicas\":$NEW_MAX}}'"
else
  echo "❌ NOT SAFE to reduce HPA maxReplicas"
  echo ""
  echo "Safe procedure:"
  echo "1. Scale down deployment first:"
  echo "   kubectl scale deployment $HPA_NAME -n $NAMESPACE --replicas=$NEW_MAX"
  echo ""
  echo "2. Wait for scale-down to complete:"
  echo "   kubectl wait --for=jsonpath='{.status.replicas}'=$NEW_MAX deployment/$HPA_NAME -n $NAMESPACE"
  echo ""
  echo "3. Monitor for issues (wait 5-10 minutes)"
  echo ""
  echo "4. Then reduce HPA maxReplicas:"
  echo "   kubectl patch hpa $HPA_NAME -n $NAMESPACE -p '{\"spec\":{\"maxReplicas\":$NEW_MAX}}'"
fi
```

**Usage:**

```bash
./pre-hpa-reduction-checklist.sh 5

# Output:
HPA Reduction Safety Checklist
================================

1. Current HPA State
   Current maxReplicas: 10
   Current minReplicas: 2
   Current replicas: 10
   Desired replicas: 10
   Target maxReplicas: 5

   ❌ DANGER: HPA is at max capacity!
      Do NOT reduce maxReplicas now.

2. Target Check
   ❌ DANGER: Target maxReplicas (5) < current replicas (10)
      This would cause immediate scale-down!

3. Recent Load Trends (last 6 hours)
   Avg CPU: 750m, Avg Mem: 512Mi

4. PodDisruptionBudget
   PDB minAvailable: 8
   ❌ WARNING: New maxReplicas (5) < PDB minAvailable (8)

================================
❌ NOT SAFE to reduce HPA maxReplicas
```

---

## Summary

### Defense Layers (Implement All)

1. **Validation Admission Webhook** - Block dangerous changes at API level
2. **PodDisruptionBudget** - Limit simultaneous pod terminations
3. **CI/CD Validation** - Catch issues before merge
4. **Gradual Reduction Script** - Automate safe step-down
5. **Policy Enforcement** - Declarative rules (Kyverno/OPA)
6. **Monitoring & Alerts** - Detect capacity issues early
7. **GitOps Review** - Human approval for risky changes

### Safe HPA Reduction Procedure

```
1. Check current replica count
2. If at max capacity → Investigate why before reducing
3. If reducing below current count:
   a. Manually scale deployment down first
   b. Monitor for issues
   c. Then reduce HPA maxReplicas
4. Reduce gradually (max 50% at a time)
5. Monitor metrics after each reduction
6. Keep PDB aligned with HPA minReplicas
```

### Key Takeaway

**Never reduce HPA maxReplicas below the current replica count without first manually scaling down the deployment.** The admission webhook is your safety net.
