# Gradual Runtime Configuration Reload with Health Checks

## The Problem

When you update a ConfigMap mounted as a volume, Kubernetes propagates changes to **all pods at roughly the same time** (~60s). This creates a risk:

```
Update ConfigMap → All pods get new files → All apps reload →
If config is bad → All pods fail health checks → Total outage! ❌
```

**This is NOT a gradual rollout by default.**

## Solution Strategies

### Strategy 1: Config Validation + Graceful Degradation

**The safest approach:** Validate config before applying, gracefully handle bad config.

#### Implementation

**Application code with validation:**

```python
import yaml
import logging
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

class SafeConfigReloader(FileSystemEventHandler):
    def __init__(self, config_path):
        self.config_path = config_path
        self.config = self.load_and_validate_config()
        self.last_good_config = self.config.copy()

    def load_and_validate_config(self):
        """Load and validate config, return None if invalid"""
        try:
            with open(self.config_path, 'r') as f:
                config = yaml.safe_load(f)

            # Validate required fields
            required = ['log_level', 'database', 'feature_flags']
            for field in required:
                if field not in config:
                    raise ValueError(f"Missing required field: {field}")

            # Validate values
            valid_log_levels = ['debug', 'info', 'warn', 'error']
            if config['log_level'] not in valid_log_levels:
                raise ValueError(f"Invalid log_level: {config['log_level']}")

            # Validate database config
            if config['database']['pool_size'] < 1:
                raise ValueError("pool_size must be >= 1")

            logging.info(f"✓ Config validation passed: {config}")
            return config

        except Exception as e:
            logging.error(f"✗ Config validation failed: {e}")
            return None

    def on_modified(self, event):
        if event.src_path.endswith('..data'):
            logging.info("Config file change detected, validating...")

            # Try to load new config
            new_config = self.load_and_validate_config()

            if new_config is not None:
                # Config is valid, apply it
                logging.info("✓ New config is valid, applying...")
                self.config = new_config
                self.last_good_config = new_config.copy()
                apply_config(self.config)
            else:
                # Config is invalid, keep using last good config
                logging.warning("✗ New config is invalid, keeping current config")
                logging.warning(f"Still using: {self.last_good_config}")
                # Health check will still pass because we're using valid config

# Usage
reloader = SafeConfigReloader('/etc/config/config.yaml')
observer = Observer()
observer.schedule(reloader, '/etc/config', recursive=False)
observer.start()

# Your app uses reloader.config
run_app(reloader.config)
```

**Health check endpoint:**

```python
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/health')
def health():
    """Kubernetes calls this for liveness/readiness probes"""

    # Check if we have valid config
    if reloader.config is None:
        return jsonify({
            'status': 'unhealthy',
            'reason': 'No valid configuration loaded'
        }), 503

    # Check if app is functioning correctly
    try:
        # Test database connection
        db.ping()

        return jsonify({
            'status': 'healthy',
            'config_version': reloader.config.get('version', 'unknown')
        }), 200

    except Exception as e:
        return jsonify({
            'status': 'unhealthy',
            'reason': str(e)
        }), 503

@app.route('/ready')
def ready():
    """Readiness probe - are we ready to receive traffic?"""

    # More strict checks for readiness
    if reloader.config is None:
        return jsonify({'status': 'not ready'}), 503

    if not db.is_connected():
        return jsonify({'status': 'not ready', 'reason': 'db not connected'}), 503

    return jsonify({'status': 'ready'}), 200
```

**Kubernetes Deployment with health checks:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: app
        image: myapp:latest
        volumeMounts:
        - name: config
          mountPath: /etc/config

        # Liveness probe - restart if app is broken
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          failureThreshold: 3      # Restart after 3 failures (30s)
          timeoutSeconds: 5

        # Readiness probe - remove from service if not ready
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
          failureThreshold: 2      # Remove from service after 2 failures (10s)
          successThreshold: 1      # Add back after 1 success
          timeoutSeconds: 3

      volumes:
      - name: config
        configMap:
          name: app-config
```

**What happens with bad config:**

```
T+0s:   Update ConfigMap with invalid config
T+60s:  Files updated in all 3 pods
T+61s:  All apps detect change, try to reload
        App validates config → FAILS validation
        Apps keep using last_good_config
        Health checks still pass ✓

Result: No pods restart, no traffic disruption
        Logs show validation errors
        You fix ConfigMap, try again
```

---

### Strategy 2: Canary Rollout with Multiple ConfigMaps

**For true gradual rollout:** Use separate ConfigMaps for stable vs canary pods.

```
┌────────────────────────────────────────────┐
│ Stable Deployment (9 pods)                 │
│ Uses: app-config-stable                    │
│ 90% of traffic                             │
└────────────────────────────────────────────┘

┌────────────────────────────────────────────┐
│ Canary Deployment (1 pod)                  │
│ Uses: app-config-canary                    │
│ 10% of traffic                             │
└────────────────────────────────────────────┘
```

#### Implementation

**Stable deployment:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-stable
  namespace: production
data:
  config.yaml: |
    log_level: info
    feature_flags:
      new_feature: false
    database:
      pool_size: 10
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-stable
  namespace: production
spec:
  replicas: 9
  selector:
    matchLabels:
      app: myapp
      track: stable
  template:
    metadata:
      labels:
        app: myapp
        track: stable
    spec:
      containers:
      - name: app
        image: myapp:latest
        volumeMounts:
        - name: config
          mountPath: /etc/config
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          periodSeconds: 5
      volumes:
      - name: config
        configMap:
          name: app-config-stable  # ← Stable config
```

**Canary deployment:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-canary
  namespace: production
data:
  config.yaml: |
    log_level: debug        # ← Testing new log level
    feature_flags:
      new_feature: true     # ← Testing new feature
    database:
      pool_size: 20         # ← Testing increased pool
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-canary
  namespace: production
spec:
  replicas: 1               # ← Only 1 canary pod
  selector:
    matchLabels:
      app: myapp
      track: canary
  template:
    metadata:
      labels:
        app: myapp
        track: canary
    spec:
      containers:
      - name: app
        image: myapp:latest
        volumeMounts:
        - name: config
          mountPath: /etc/config
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          periodSeconds: 5
      volumes:
      - name: config
        configMap:
          name: app-config-canary  # ← Canary config
```

**Service routes to both:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: app-service
  namespace: production
spec:
  selector:
    app: myapp     # ← Matches both stable and canary
  ports:
  - port: 80
    targetPort: 8080
```

**Rollout process:**

```bash
# 1. Update canary config with new settings
kubectl apply -f app-config-canary.yaml

# 2. Wait for canary pod to reload (~60s)
sleep 60

# 3. Check canary health
kubectl get pods -n production -l track=canary
kubectl logs -n production -l track=canary --tail=50

# 4. Monitor canary metrics
# - Error rate
# - Response time
# - Health check status

# 5a. If canary is healthy, promote to stable
kubectl apply -f app-config-stable.yaml  # Copy canary config to stable
# Now all 9 stable pods gradually reload with new config

# 5b. If canary is unhealthy, rollback
kubectl rollout undo deployment/app-canary -n production
# Or revert app-config-canary to previous values
```

**Monitoring canary:**

```bash
# Watch canary pod health
watch kubectl get pods -n production -l track=canary

# Check if canary is ready
kubectl get pods -n production -l track=canary -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}'

# Compare error rates (requires Prometheus)
# Canary error rate
rate(http_requests_total{track="canary",status=~"5.."}[5m])

# Stable error rate
rate(http_requests_total{track="stable",status=~"5.."}[5m])
```

---

### Strategy 3: Progressive Reload with Staggered Timing

**Application-level control:** Each pod reloads config at different times.

```python
import random
import time
import os

class StaggeredConfigReloader(FileSystemEventHandler):
    def __init__(self, config_path):
        self.config_path = config_path
        self.config = self.load_config()
        self.reload_pending = False

        # Each pod gets a random delay (0-300 seconds = 5 minutes)
        # This spreads reloads across a 5-minute window
        self.reload_delay = random.randint(0, 300)

        # Or use pod ordinal for StatefulSet
        pod_name = os.environ.get('POD_NAME', '')
        if 'myapp-' in pod_name:
            ordinal = int(pod_name.split('-')[-1])
            # Pod 0: 0s, Pod 1: 30s, Pod 2: 60s, etc.
            self.reload_delay = ordinal * 30

    def on_modified(self, event):
        if event.src_path.endswith('..data'):
            logging.info(f"Config change detected, will reload in {self.reload_delay}s")
            self.reload_pending = True

            # Schedule delayed reload
            threading.Timer(self.reload_delay, self.perform_reload).start()

    def perform_reload(self):
        if self.reload_pending:
            logging.info("Performing config reload now...")
            new_config = self.load_and_validate_config()

            if new_config:
                self.config = new_config
                apply_config(self.config)
                logging.info("✓ Config reloaded successfully")
            else:
                logging.error("✗ Config reload failed validation")

            self.reload_pending = False
```

**Timeline with 3 pods:**

```
T+0s:   Update ConfigMap
T+60s:  All pods get new files

        Pod 0 (delay: 0s):
        T+60s:  Reload immediately
        T+65s:  Health check passes/fails

        Pod 1 (delay: 30s):
        T+90s:  Reload
        T+95s:  Health check passes/fails

        Pod 2 (delay: 60s):
        T+120s: Reload
        T+125s: Health check passes/fails
```

**If config is bad:**

```
T+60s:  Pod 0 reloads → Fails health check → Removed from service
T+65s:  Service now routes to Pod 1 and Pod 2 only
        Monitoring alerts: "Pod 0 unhealthy!"

        You notice the problem and fix ConfigMap

T+70s:  New (fixed) config propagates to all pods
T+130s: Pod 0 reloads with fixed config → Healthy again
```

**Pod disruption budget protects availability:**

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: app-pdb
spec:
  minAvailable: 2      # At least 2 pods must be healthy
  selector:
    matchLabels:
      app: myapp
```

This ensures Service always has enough healthy backends.

---

### Strategy 4: Admission Webhook for Config Validation

**Prevent bad configs from being applied** in the first place.

```python
from flask import Flask, request, jsonify
import yaml

app = Flask(__name__)

@app.route('/validate-configmap', methods=['POST'])
def validate_configmap():
    """Kubernetes calls this webhook before creating/updating ConfigMap"""

    admission_review = request.get_json()

    # Extract ConfigMap data
    configmap = admission_review['request']['object']
    config_data = configmap.get('data', {}).get('config.yaml', '')

    try:
        # Parse and validate
        config = yaml.safe_load(config_data)

        # Validation rules
        if config['log_level'] not in ['debug', 'info', 'warn', 'error']:
            raise ValueError(f"Invalid log_level: {config['log_level']}")

        if config['database']['pool_size'] < 1 or config['database']['pool_size'] > 100:
            raise ValueError(f"pool_size must be 1-100")

        # Allow the ConfigMap
        return jsonify({
            'apiVersion': 'admission.k8s.io/v1',
            'kind': 'AdmissionReview',
            'response': {
                'uid': admission_review['request']['uid'],
                'allowed': True
            }
        })

    except Exception as e:
        # Reject the ConfigMap
        return jsonify({
            'apiVersion': 'admission.k8s.io/v1',
            'kind': 'AdmissionReview',
            'response': {
                'uid': admission_review['request']['uid'],
                'allowed': False,
                'status': {
                    'message': f'ConfigMap validation failed: {str(e)}'
                }
            }
        })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8443, ssl_context='adhoc')
```

**ValidatingWebhookConfiguration:**

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: configmap-validator
webhooks:
- name: validate-configmap.example.com
  clientConfig:
    service:
      name: configmap-validator
      namespace: validators
      path: /validate-configmap
    caBundle: <base64-encoded-ca-cert>
  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["configmaps"]
  namespaceSelector:
    matchLabels:
      validate-configmaps: "true"
  admissionReviewVersions: ["v1"]
  sideEffects: None
  failurePolicy: Fail  # Block invalid configs
```

**Result:**

```bash
# Try to apply bad config
kubectl apply -f bad-config.yaml

# Output:
Error from server: admission webhook "validate-configmap.example.com" denied the request:
ConfigMap validation failed: Invalid log_level: invalid_value

# Bad config is BLOCKED, never reaches cluster
```

---

## Recommended Approach: Combine Strategies

**Best practice for production:**

```
1. Admission webhook (prevent bad configs)
   ↓
2. Canary deployment (test new configs safely)
   ↓
3. App-level validation (defense in depth)
   ↓
4. Health checks (detect and recover from issues)
   ↓
5. PodDisruptionBudget (maintain availability)
```

**Example architecture:**

```yaml
# Namespace with validation enabled
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    validate-configmaps: "true"  # ← Admission webhook applies here
```

```yaml
# Stable config
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-stable
  namespace: production
  annotations:
    validated-at: "2025-11-15T12:00:00Z"
    validated-by: "admission-webhook-v1"
data:
  config.yaml: |
    log_level: info
    database:
      pool_size: 10
```

```yaml
# Canary config (test new settings)
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-canary
  namespace: production
data:
  config.yaml: |
    log_level: debug
    database:
      pool_size: 20
```

```yaml
# Stable deployment with validation + health checks
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-stable
spec:
  replicas: 9
  template:
    spec:
      containers:
      - name: app
        # App has built-in config validation
        # App watches config files with staggered reload
        volumeMounts:
        - name: config
          mountPath: /etc/config

        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          periodSeconds: 10
          failureThreshold: 3

        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          periodSeconds: 5
          failureThreshold: 2

      volumes:
      - name: config
        configMap:
          name: app-config-stable
```

```yaml
# PDB ensures availability during config reloads
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: app-pdb
spec:
  minAvailable: 7  # Out of 9 stable pods, 7 must stay healthy
  selector:
    matchLabels:
      app: myapp
      track: stable
```

**Rollout process:**

```bash
# 1. Update canary config
kubectl apply -f app-config-canary.yaml
# ✓ Passes admission webhook validation

# 2. Wait for canary pod to reload
sleep 90

# 3. Check canary health
kubectl logs -l track=canary --tail=50
kubectl get pods -l track=canary

# 4. Monitor for 5-10 minutes
# - Check metrics
# - Check error logs
# - Check health checks

# 5. If canary is healthy, promote to stable
kubectl apply -f app-config-stable.yaml

# 6. Watch stable pods reload gradually (staggered)
kubectl get pods -l track=stable -w

# 7. Monitor PDB
kubectl get pdb app-pdb
# Should show: ALLOWED DISRUPTIONS: 2 (always at least 7 healthy)
```

---

## Summary

### The Truth About Runtime Config Reload

**Without additional measures:**
- ❌ All pods get new config files at same time (~60s)
- ❌ All apps reload simultaneously
- ❌ If config is bad, all pods can fail at once
- ❌ **NOT a gradual rollout by default**

**To make it truly gradual:**
1. **Config validation** - Prevent bad configs from breaking pods
2. **Canary deployments** - Test config on subset of pods first
3. **Staggered reload** - Apps reload at different times
4. **Admission webhooks** - Block bad configs before they reach cluster
5. **Health checks** - Detect and remove unhealthy pods from service
6. **PodDisruptionBudgets** - Ensure minimum availability

### When to Use Runtime Reload

✅ **Good fit:**
- App supports hot config reload
- Zero-downtime is critical
- Frequent config changes
- Combined with validation + canary pattern

❌ **Bad fit:**
- App doesn't validate config well
- Config changes are rare
- Team prefers explicit rollout control
- Use immutable ConfigMaps instead

### Comparison with Immutable ConfigMap Rollout

| Aspect | Immutable ConfigMap | Runtime Reload + Validation |
|--------|--------------------|-----------------------------|
| **Gradual by default** | ✅ Yes (rolling update) | ❌ No (need extra work) |
| **Pod restarts** | ✅ Yes | ❌ No |
| **Downtime** | ⚠️ Brief | ✅ None |
| **Rollback** | ✅ Easy (kubectl rollout undo) | ⚠️ Update ConfigMap back |
| **Complexity** | Low | High |
| **Safety** | ✅ High (isolated rollout) | ⚠️ Medium (needs validation) |
| **Best for** | Most production apps | HA apps with good validation |

**Recommendation:** For most teams, **immutable ConfigMaps** are simpler and safer. Use runtime reload only when zero-downtime is truly required and you can implement proper validation + canary pattern.
