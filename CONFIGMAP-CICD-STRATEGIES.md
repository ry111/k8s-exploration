# CI/CD Strategies for ConfigMap Rollouts

## The Problem with Manual Canary

The canary approach shown earlier is **too manual** for production:

```bash
# Manual steps (error-prone!)
1. Update app-config-canary.yaml
2. kubectl apply -f app-config-canary.yaml
3. Wait 5 minutes
4. Manually check logs/metrics
5. If good, copy to app-config-stable.yaml
6. kubectl apply -f app-config-stable.yaml
7. Hope you didn't make a mistake!
```

**Problems:**
- ❌ Manual verification is slow and error-prone
- ❌ No automated rollback
- ❌ Inconsistent process across teams
- ❌ Doesn't scale to multiple environments
- ❌ Hard to audit who changed what

**Solution:** Automate the entire process with CI/CD pipelines and progressive delivery tools.

---

## Strategy 1: GitOps with ArgoCD + Progressive Delivery

**Best for:** Teams already using GitOps, want declarative config management

### Architecture

```
Git Repo (Source of Truth)
    ├── base/
    │   └── configmap.yaml
    ├── overlays/
    │   ├── canary/
    │   │   └── configmap.yaml
    │   └── stable/
    │       └── configmap.yaml
    ↓
ArgoCD (Continuous Sync)
    ↓
Kubernetes Cluster
    ├── app-canary (uses canary config)
    └── app-stable (uses stable config)
```

### Implementation

#### Repository Structure

```
k8s-config/
├── apps/
│   └── myapp/
│       ├── base/
│       │   ├── kustomization.yaml
│       │   ├── deployment.yaml
│       │   └── configmap.yaml
│       ├── overlays/
│       │   ├── canary/
│       │   │   ├── kustomization.yaml
│       │   │   ├── configmap-patch.yaml
│       │   │   └── deployment-patch.yaml
│       │   └── stable/
│       │       ├── kustomization.yaml
│       │       ├── configmap-patch.yaml
│       │       └── deployment-patch.yaml
└── .github/
    └── workflows/
        └── promote-config.yaml
```

**base/configmap.yaml:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: production
data:
  config.yaml: |
    log_level: info
    database:
      pool_size: 10
    feature_flags:
      new_ui: false
```

**overlays/canary/kustomization.yaml:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: production

resources:
- ../../base

nameSuffix: -canary

patches:
- path: deployment-patch.yaml
- path: configmap-patch.yaml
```

**overlays/canary/configmap-patch.yaml:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  config.yaml: |
    log_level: debug        # ← Testing new value
    database:
      pool_size: 20         # ← Testing new value
    feature_flags:
      new_ui: true          # ← Testing new feature
```

**overlays/stable/kustomization.yaml:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: production

resources:
- ../../base

nameSuffix: -stable

patches:
- path: deployment-patch.yaml
- path: configmap-patch.yaml
```

#### ArgoCD Applications

**Canary application:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-canary
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/k8s-config
    targetRevision: main
    path: apps/myapp/overlays/canary
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

**Stable application:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-stable
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/k8s-config
    targetRevision: main
    path: apps/myapp/overlays/stable
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

#### Automated Promotion Pipeline

**GitHub Actions workflow (.github/workflows/promote-config.yaml):**

```yaml
name: Promote Config from Canary to Stable

on:
  workflow_dispatch:  # Manual trigger
    inputs:
      confirm:
        description: 'Type "promote" to confirm'
        required: true

  # Or automated trigger based on metrics
  repository_dispatch:
    types: [canary-validated]

jobs:
  validate-canary:
    runs-on: ubuntu-latest
    outputs:
      canary-healthy: ${{ steps.check.outputs.healthy }}
    steps:
      - name: Check canary health
        id: check
        run: |
          # Query Prometheus for canary metrics
          ERROR_RATE=$(curl -s "http://prometheus:9090/api/v1/query?query=rate(http_requests_total{deployment='myapp-canary',status=~'5..'}[5m])")

          # Parse error rate (simplified)
          if [ "$(echo $ERROR_RATE | jq -r '.data.result[0].value[1]')" == "0" ]; then
            echo "healthy=true" >> $GITHUB_OUTPUT
          else
            echo "healthy=false" >> $GITHUB_OUTPUT
            exit 1
          fi

      - name: Check canary readiness
        run: |
          kubectl get pods -n production -l app=myapp,track=canary -o json | \
            jq -e '.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))'

  promote:
    needs: validate-canary
    runs-on: ubuntu-latest
    if: ${{ needs.validate-canary.outputs.canary-healthy == 'true' }}
    steps:
      - uses: actions/checkout@v3
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Copy canary config to stable
        run: |
          # Copy canary ConfigMap patch to stable
          cp apps/myapp/overlays/canary/configmap-patch.yaml \
             apps/myapp/overlays/stable/configmap-patch.yaml

      - name: Create Pull Request
        uses: peter-evans/create-pull-request@v5
        with:
          commit-message: "Promote canary config to stable"
          title: "Config Promotion: Canary → Stable"
          body: |
            ## Automated Config Promotion

            Canary validation passed. Promoting config to stable.

            **Canary Metrics:**
            - Error Rate: 0%
            - Health Checks: Passing
            - Duration: 10 minutes

            **Changes:**
            - log_level: info → debug
            - database.pool_size: 10 → 20
            - feature_flags.new_ui: false → true
          branch: promote-config-${{ github.run_id }}
          labels: |
            automated
            config-promotion

  rollback-on-failure:
    needs: validate-canary
    runs-on: ubuntu-latest
    if: ${{ failure() }}
    steps:
      - uses: actions/checkout@v3

      - name: Revert canary config
        run: |
          git checkout HEAD~1 -- apps/myapp/overlays/canary/configmap-patch.yaml
          git commit -m "Rollback canary config - validation failed"
          git push

      - name: Notify team
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": "🚨 Canary config validation FAILED. Auto-rolled back.",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Canary Validation Failed*\nConfig has been automatically rolled back."
                  }
                }
              ]
            }
```

#### Workflow Process

```
Developer workflow:
1. Edit apps/myapp/overlays/canary/configmap-patch.yaml
2. Commit and push to feature branch
3. Create PR → automated tests run
4. Merge PR → ArgoCD syncs to canary deployment
5. Wait 10 minutes (automated)
6. GitHub Actions validates canary metrics
7. If healthy: Auto-creates promotion PR
8. Team reviews and merges promotion PR
9. ArgoCD syncs to stable deployment
10. Config gradually rolls out to stable pods
```

---

## Strategy 2: Flagger for Automated Progressive Delivery

**Best for:** Full automation, metric-driven promotions

### What is Flagger?

Flagger automates canary deployments with **automatic promotion** based on metrics.

```
┌─────────────────────────────────────────────────┐
│ Flagger Controller                               │
│                                                  │
│ 1. Detects ConfigMap change                      │
│ 2. Updates canary pods                           │
│ 3. Monitors metrics (error rate, latency)        │
│ 4. Gradually shifts traffic: 10% → 50% → 100%   │
│ 5. Auto-promotes if metrics good                 │
│ 6. Auto-rollbacks if metrics bad                 │
└─────────────────────────────────────────────────┘
```

### Installation

```bash
# Install Flagger
kubectl apply -k github.com/fluxcd/flagger//kustomize/linkerd

# Install Prometheus for metrics
helm install prometheus prometheus-community/kube-prometheus-stack
```

### Implementation

**ConfigMap with version annotation:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: production
  annotations:
    config.version: "v2"  # ← Flagger watches for changes
data:
  config.yaml: |
    log_level: debug
    database:
      pool_size: 20
```

**Deployment:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: production
spec:
  replicas: 3
  template:
    metadata:
      annotations:
        # Tell Flagger to restart pods on ConfigMap changes
        configmap.hash: "{{ configmapHash }}"
    spec:
      containers:
      - name: app
        image: myapp:latest
        volumeMounts:
        - name: config
          mountPath: /etc/config
      volumes:
      - name: config
        configMap:
          name: app-config
```

**Flagger Canary Resource:**

```yaml
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: myapp
  namespace: production
spec:
  # Target Deployment
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp

  # Service configuration
  service:
    port: 80
    targetPort: 8080

  # Progressive traffic shift
  analysis:
    # How long to wait before starting analysis
    interval: 1m

    # How many checks must pass
    threshold: 5

    # Max weight before promotion
    maxWeight: 50

    # Traffic increment step
    stepWeight: 10

    # Metrics to check
    metrics:
    - name: request-success-rate
      thresholdRange:
        min: 99  # 99% success rate required
      interval: 1m

    - name: request-duration
      thresholdRange:
        max: 500  # p99 latency < 500ms
      interval: 1m

    # Custom Prometheus queries
    - name: error-rate
      templateRef:
        name: error-rate
        namespace: flagger-system
      thresholdRange:
        max: 1  # Max 1% error rate
      interval: 1m

    # Webhooks for validation
    webhooks:
    - name: load-test
      url: http://load-tester.production/
      timeout: 5s
      metadata:
        cmd: "hey -z 1m -q 10 -c 2 http://myapp.production/"

    - name: notify-slack
      url: http://slack-bot.production/
      metadata:
        message: "Canary deployment for myapp started"

# Prometheus query template for custom metrics
---
apiVersion: flagger.app/v1beta1
kind: MetricTemplate
metadata:
  name: error-rate
  namespace: flagger-system
spec:
  provider:
    type: prometheus
    address: http://prometheus.monitoring:9090
  query: |
    100 - sum(
      rate(
        http_requests_total{
          namespace="{{ namespace }}",
          deployment="{{ target }}",
          status!~"5.."
        }[{{ interval }}]
      )
    )
    /
    sum(
      rate(
        http_requests_total{
          namespace="{{ namespace }}",
          deployment="{{ target }}"
        }[{{ interval }}]
      )
    ) * 100
```

### How Flagger Works

**Timeline of automated rollout:**

```
T+0m:   Developer updates ConfigMap (config.version: "v2")
        Flagger detects change

T+1m:   Flagger creates canary deployment
        - myapp-canary (with new config)
        - myapp-primary (with old config)
        Traffic: 100% → primary, 0% → canary

T+2m:   Flagger shifts 10% traffic to canary
        Traffic: 90% → primary, 10% → canary
        Checks metrics...
        ✓ Error rate: 0%
        ✓ Latency p99: 250ms
        ✓ Success rate: 99.9%

T+3m:   Metrics good, shift 20% traffic
        Traffic: 80% → primary, 20% → canary
        Checks metrics...
        ✓ All metrics passing

T+4m:   Shift 30% traffic
        Traffic: 70% → primary, 30% → canary

...continue every minute...

T+7m:   Shift 50% traffic (maxWeight reached)
        Traffic: 50% → primary, 50% → canary
        Wait for threshold (5 checks) to pass

T+12m:  All 5 checks passed at 50% traffic
        Flagger promotes canary → primary

T+13m:  Traffic: 100% → primary (now using new config)
        Canary deployment deleted
        ✓ Rollout complete!
```

**If metrics fail at any point:**

```
T+4m:   Shift 30% traffic
        Traffic: 70% → primary, 30% → canary
        Checks metrics...
        ✗ Error rate: 5% (exceeds threshold of 1%)

T+4m:   Flagger immediately rolls back
        Traffic: 100% → primary (old config)
        Canary deployment deleted
        ✗ Rollout aborted!

        Webhook notification sent to Slack:
        "🚨 Canary rollout failed - error rate too high"
```

### GitOps Workflow with Flagger

```yaml
# .github/workflows/deploy-config.yaml
name: Deploy ConfigMap

on:
  push:
    paths:
      - 'k8s/configmaps/app-config.yaml'
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Bump config version
        run: |
          # Increment version annotation to trigger Flagger
          VERSION=$(date +%Y%m%d-%H%M%S)
          yq eval ".metadata.annotations.\"config.version\" = \"$VERSION\"" \
            -i k8s/configmaps/app-config.yaml

      - name: Commit version bump
        run: |
          git config user.name "GitHub Actions"
          git config user.email "actions@github.com"
          git add k8s/configmaps/app-config.yaml
          git commit -m "Bump config version to $VERSION"
          git push

      - name: Apply ConfigMap
        run: |
          kubectl apply -f k8s/configmaps/app-config.yaml

      - name: Wait for Flagger
        run: |
          # Flagger will automatically handle the canary rollout
          echo "Flagger will monitor and promote canary automatically"
          echo "Watch progress: kubectl -n production describe canary myapp"

      - name: Monitor rollout
        run: |
          # Wait up to 15 minutes for promotion
          timeout 900 bash -c '
            while true; do
              STATUS=$(kubectl get canary myapp -n production -o jsonpath="{.status.phase}")
              echo "Canary status: $STATUS"

              if [ "$STATUS" == "Succeeded" ]; then
                echo "✓ Canary promotion succeeded!"
                exit 0
              elif [ "$STATUS" == "Failed" ]; then
                echo "✗ Canary promotion failed!"
                exit 1
              fi

              sleep 30
            done
          '

      - name: Notify on failure
        if: failure()
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": "🚨 ConfigMap rollout failed - Flagger rolled back automatically"
            }
```

### Monitoring Flagger

```bash
# Watch canary progress
kubectl -n production get canary myapp -w

# Output:
NAME    STATUS        WEIGHT   LASTTRANSITIONTIME
myapp   Progressing   0        2025-11-15T12:00:00Z
myapp   Progressing   10       2025-11-15T12:01:00Z
myapp   Progressing   20       2025-11-15T12:02:00Z
myapp   Progressing   30       2025-11-15T12:03:00Z
myapp   Progressing   50       2025-11-15T12:05:00Z
myapp   Succeeded     0        2025-11-15T12:12:00Z

# Detailed status
kubectl -n production describe canary myapp

# Events:
# Normal   Synced  Advance myapp.production canary weight 10
# Normal   Synced  Advance myapp.production canary weight 20
# Normal   Synced  Copying myapp.production template spec to myapp-primary.production
# Normal   Synced  Promotion completed! myapp.production
```

---

## Strategy 3: Helm-based CI/CD with Validation

**Best for:** Teams using Helm, multi-environment deployments

### Repository Structure

```
helm-charts/
└── myapp/
    ├── Chart.yaml
    ├── values.yaml              # Defaults
    ├── values-dev.yaml          # Dev overrides
    ├── values-staging.yaml      # Staging overrides
    ├── values-production.yaml   # Production overrides
    └── templates/
        ├── deployment.yaml
        ├── configmap.yaml
        └── tests/
            └── test-config.yaml
```

**templates/configmap.yaml:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "myapp.fullname" . }}
  namespace: {{ .Release.Namespace }}
  annotations:
    # Hash of config data - changes trigger rollout
    checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
data:
  config.yaml: |
    log_level: {{ .Values.config.logLevel }}
    database:
      host: {{ .Values.config.database.host }}
      pool_size: {{ .Values.config.database.poolSize }}
    feature_flags:
      {{- toYaml .Values.config.featureFlags | nindent 6 }}
```

**templates/deployment.yaml:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "myapp.fullname" . }}
spec:
  replicas: {{ .Values.replicaCount }}
  template:
    metadata:
      annotations:
        # Pod restarts when this annotation changes
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    spec:
      containers:
      - name: {{ .Chart.Name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        {{- if .Values.config.mountAsVolume }}
        volumeMounts:
        - name: config
          mountPath: /etc/config
        {{- else }}
        envFrom:
        - configMapRef:
            name: {{ include "myapp.fullname" . }}
        {{- end }}
      {{- if .Values.config.mountAsVolume }}
      volumes:
      - name: config
        configMap:
          name: {{ include "myapp.fullname" . }}
      {{- end }}
```

**values-production.yaml:**

```yaml
replicaCount: 10

config:
  mountAsVolume: true  # Use runtime reload
  logLevel: info
  database:
    host: prod-db.example.com
    poolSize: 20
  featureFlags:
    newUI: false
    betaFeatures: false

# Canary configuration
canary:
  enabled: true
  replicaCount: 2
  config:
    logLevel: debug      # Test new value
    database:
      poolSize: 30       # Test new value
    featureFlags:
      newUI: true        # Test new feature
```

### CI/CD Pipeline with Helm

**GitLab CI (.gitlab-ci.yml):**

```yaml
stages:
  - validate
  - deploy-canary
  - test-canary
  - promote
  - rollback

variables:
  HELM_RELEASE: myapp
  NAMESPACE: production

# Validate Helm chart and config
validate:
  stage: validate
  script:
    # Lint Helm chart
    - helm lint helm-charts/myapp

    # Dry-run to catch errors
    - helm template $HELM_RELEASE helm-charts/myapp
        -f helm-charts/myapp/values-production.yaml
        --validate

    # Validate config values
    - python scripts/validate-config.py
        helm-charts/myapp/values-production.yaml

# Deploy to canary
deploy-canary:
  stage: deploy-canary
  script:
    # Deploy canary with new config
    - helm upgrade --install ${HELM_RELEASE}-canary helm-charts/myapp
        -f helm-charts/myapp/values-production.yaml
        -f helm-charts/myapp/values-canary.yaml
        --namespace $NAMESPACE
        --set canary.enabled=true
        --wait
        --timeout 5m
  only:
    - main

# Automated canary testing
test-canary:
  stage: test-canary
  script:
    # Wait for canary to be ready
    - kubectl wait --for=condition=available --timeout=300s
        deployment/${HELM_RELEASE}-canary -n $NAMESPACE

    # Run smoke tests
    - ./scripts/smoke-test.sh canary

    # Monitor metrics for 5 minutes
    - python scripts/monitor-canary.py
        --deployment ${HELM_RELEASE}-canary
        --namespace $NAMESPACE
        --duration 300
  only:
    - main

# Promote to stable if tests pass
promote:
  stage: promote
  script:
    # Copy canary values to stable
    - cp helm-charts/myapp/values-canary.yaml
         helm-charts/myapp/values-production.yaml

    # Upgrade stable deployment
    - helm upgrade --install $HELM_RELEASE helm-charts/myapp
        -f helm-charts/myapp/values-production.yaml
        --namespace $NAMESPACE
        --wait
        --timeout 10m

    # Clean up canary
    - helm uninstall ${HELM_RELEASE}-canary -n $NAMESPACE

    # Commit the promotion
    - git add helm-charts/myapp/values-production.yaml
    - git commit -m "Promote canary config to production"
    - git push
  only:
    - main
  when: manual  # Require manual approval

# Rollback if anything fails
rollback:
  stage: rollback
  script:
    - helm rollback $HELM_RELEASE 0 -n $NAMESPACE
    - helm uninstall ${HELM_RELEASE}-canary -n $NAMESPACE || true
  when: on_failure
  only:
    - main
```

**Validation script (scripts/validate-config.py):**

```python
#!/usr/bin/env python3
import yaml
import sys
import jsonschema

# Define config schema
CONFIG_SCHEMA = {
    "type": "object",
    "required": ["config"],
    "properties": {
        "config": {
            "type": "object",
            "required": ["logLevel", "database"],
            "properties": {
                "logLevel": {
                    "type": "string",
                    "enum": ["debug", "info", "warn", "error"]
                },
                "database": {
                    "type": "object",
                    "required": ["host", "poolSize"],
                    "properties": {
                        "host": {"type": "string"},
                        "poolSize": {
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 100
                        }
                    }
                }
            }
        }
    }
}

def validate_config(values_file):
    with open(values_file) as f:
        values = yaml.safe_load(f)

    try:
        jsonschema.validate(values, CONFIG_SCHEMA)
        print(f"✓ {values_file} validation passed")
        return True
    except jsonschema.ValidationError as e:
        print(f"✗ {values_file} validation failed:")
        print(f"  {e.message}")
        return False

if __name__ == "__main__":
    if not validate_config(sys.argv[1]):
        sys.exit(1)
```

**Monitoring script (scripts/monitor-canary.py):**

```python
#!/usr/bin/env python3
import time
import argparse
from prometheus_api_client import PrometheusConnect

def monitor_canary(deployment, namespace, duration):
    prom = PrometheusConnect(url="http://prometheus:9090")

    end_time = time.time() + duration

    while time.time() < end_time:
        # Query error rate
        error_rate = prom.custom_query(
            f'rate(http_requests_total{{deployment="{deployment}",namespace="{namespace}",status=~"5.."}}[1m])'
        )

        # Query latency
        latency_p99 = prom.custom_query(
            f'histogram_quantile(0.99, http_request_duration_seconds{{deployment="{deployment}",namespace="{namespace}"}})'
        )

        # Check thresholds
        error_rate_val = float(error_rate[0]['value'][1]) if error_rate else 0
        latency_val = float(latency_p99[0]['value'][1]) if latency_p99 else 0

        print(f"Error rate: {error_rate_val:.2%}, Latency p99: {latency_val:.0f}ms")

        if error_rate_val > 0.01:  # > 1% error rate
            print("✗ Error rate too high!")
            sys.exit(1)

        if latency_val > 500:  # > 500ms
            print("✗ Latency too high!")
            sys.exit(1)

        time.sleep(30)

    print("✓ Canary metrics look good!")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--deployment', required=True)
    parser.add_argument('--namespace', required=True)
    parser.add_argument('--duration', type=int, required=True)
    args = parser.parse_args()

    monitor_canary(args.deployment, args.namespace, args.duration)
```

---

## Strategy 4: Kustomize + GitHub Actions

**Best for:** Kubernetes-native approach, no Helm

### Repository Structure

```
k8s/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── configmap.yaml
│   └── service.yaml
├── overlays/
│   ├── production-canary/
│   │   ├── kustomization.yaml
│   │   └── configmap.yaml
│   └── production-stable/
│       ├── kustomization.yaml
│       └── configmap.yaml
└── .github/
    └── workflows/
        ├── deploy-canary.yaml
        └── promote-stable.yaml
```

**GitHub Actions: Deploy Canary**

```yaml
# .github/workflows/deploy-canary.yaml
name: Deploy Config to Canary

on:
  push:
    paths:
      - 'k8s/overlays/production-canary/**'
    branches:
      - main

jobs:
  deploy-canary:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up kubectl
        uses: azure/setup-kubectl@v3

      - name: Configure kubectl
        run: |
          echo "${{ secrets.KUBECONFIG }}" | base64 -d > /tmp/kubeconfig
          export KUBECONFIG=/tmp/kubeconfig

      - name: Validate config
        run: |
          kustomize build k8s/overlays/production-canary | \
            python scripts/validate-k8s.py

      - name: Deploy to canary
        run: |
          kustomize build k8s/overlays/production-canary | \
            kubectl apply -f -

      - name: Wait for rollout
        run: |
          kubectl rollout status deployment/myapp-canary -n production --timeout=5m

      - name: Run smoke tests
        run: |
          ./scripts/smoke-test.sh production myapp-canary

      - name: Monitor metrics
        run: |
          python scripts/monitor-canary.py \
            --deployment myapp-canary \
            --namespace production \
            --duration 300

      - name: Create promotion issue
        if: success()
        uses: actions/github-script@v6
        with:
          script: |
            github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: 'Promote config from canary to stable',
              body: `Canary deployment succeeded. Ready to promote to stable.

              **Canary Metrics:**
              - Error Rate: < 0.1%
              - Latency p99: < 300ms
              - Duration: 5 minutes

              Review and approve to trigger promotion.`,
              labels: ['promotion', 'automated']
            })
```

---

## Comparison of CI/CD Strategies

| Strategy | Automation | Complexity | Best For |
|----------|-----------|------------|----------|
| **ArgoCD + GitOps** | Medium | Medium | Teams using GitOps |
| **Flagger** | High | Medium | Full automation needed |
| **Helm + CI/CD** | Medium | Low | Multi-environment |
| **Kustomize + Actions** | Medium | Low | Kubernetes-native |

## Recommendations

### For Most Teams
**Use Flagger** if you:
- Want full automation
- Have good metrics/monitoring
- Trust automated decisions
- Deploy frequently

### For Cautious Teams
**Use ArgoCD + Manual Promotion** if you:
- Want human approval
- Deploy less frequently
- Need audit trail
- Prefer GitOps

### For Simple Setups
**Use Helm + CI/CD** if you:
- Already use Helm
- Have multiple environments
- Want simple workflow
- Don't need complex canary logic

---

## Summary

**Manual canary is too slow and error-prone for production.**

**Better approach:**
1. Store config in Git (source of truth)
2. Automated validation in CI
3. Auto-deploy to canary
4. Automated metric monitoring
5. Either auto-promote or manual approval
6. Automated rollback on failure

**Key principles:**
- Everything in Git
- Automated validation
- Metric-driven decisions
- Fast rollback capability
- Audit trail of changes

Choose the strategy that matches your team's risk tolerance and automation maturity.
