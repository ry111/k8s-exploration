# Gradual ConfigMap Rollouts in Kubernetes

## Table of Contents
- [Quick Answer](#quick-answer)
- [Understanding ConfigMaps](#understanding-configmaps)
- [How Pods Consume ConfigMaps](#how-pods-consume-configmaps)
- [The ConfigMap Update Problem](#the-configmap-update-problem)
- [Strategy 1: Rolling Updates with Immutable ConfigMaps](#strategy-1-rolling-updates-with-immutable-configmaps)
- [Strategy 2: Automatic Restart on ConfigMap Change](#strategy-2-automatic-restart-on-configmap-change)
- [Strategy 3: Runtime Configuration Reload](#strategy-3-runtime-configuration-reload)
- [Comparison of Strategies](#comparison-of-strategies)
- [Hands-On Examples](#hands-on-examples)
- [Production Best Practices](#production-best-practices)
- [Troubleshooting](#troubleshooting)

---

## Quick Answer

**There are three main strategies for gradually rolling out ConfigMap changes:**

### For configs requiring process restart (environment variables):

1. **Immutable ConfigMaps** (recommended) - Create new ConfigMap versions, update Deployment
2. **Reloader tools** - Automatically restart pods when ConfigMap changes
3. **Manual rollout** - Update ConfigMap, then `kubectl rollout restart`

### For configs that support runtime updates (mounted files):

1. **Volume mounts with app reload** - ConfigMap updates automatically propagate to mounted files
2. **Application watches config files** - App detects changes and reloads without restart
3. **ConfigMap hash annotations** - Trigger rolling update when config changes

**Key insight:** Kubernetes automatically updates mounted ConfigMap files, but **doesn't restart pods**. Your rollout strategy depends on whether your app can reload config at runtime.

---

## Understanding ConfigMaps

### What is a ConfigMap?

A **ConfigMap** is a Kubernetes resource that stores configuration data as key-value pairs.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: dawn-config
  namespace: dawn-ns
data:
  # Simple key-value pairs
  ENVIRONMENT: "production"
  PORT: "8000"
  LOG_LEVEL: "info"

  # Multi-line configuration file
  app.properties: |
    database.host=postgres.example.com
    database.port=5432
    feature.flags.new_ui=true
    cache.ttl=300
```

### Why Use ConfigMaps?

```
┌─────────────────────────────────────────────────────┐
│ WITHOUT ConfigMaps (hardcoded config)               │
│                                                      │
│  ❌ Config embedded in container image               │
│  ❌ Need to rebuild image for config changes         │
│  ❌ Can't share config between environments          │
│  ❌ Secrets visible in Dockerfile                    │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ WITH ConfigMaps (externalized config)               │
│                                                      │
│  ✅ Config separate from code                        │
│  ✅ Same image across environments                   │
│  ✅ Update config without rebuilding                 │
│  ✅ Centralized configuration management             │
└─────────────────────────────────────────────────────┘
```

**Separation of concerns:**
- **Container image** = application code (immutable)
- **ConfigMap** = configuration data (mutable)
- **Secret** = sensitive data (encrypted at rest)

---

## How Pods Consume ConfigMaps

Pods can consume ConfigMaps in **three ways**, each with different update behavior:

### Method 1: Environment Variables

**How it works:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: my-app:latest
    env:
    - name: LOG_LEVEL
      valueFrom:
        configMapKeyRef:
          name: dawn-config
          key: LOG_LEVEL
    # Or load all keys as env vars
    envFrom:
    - configMapRef:
        name: dawn-config
```

**Behavior:**
- ✅ Simple to use
- ✅ Works like regular environment variables in your app
- ❌ **Values set ONLY at pod creation**
- ❌ **Updating ConfigMap does NOT update running pods**
- ❌ **Requires pod restart to pick up changes**

**When ConfigMap updates:**
```
1. You update ConfigMap
2. Existing pods keep old environment values
3. New pods get new environment values
4. Need rolling update to gradually replace pods
```

### Method 2: Volume Mounts (Files)

**How it works:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: my-app:latest
    volumeMounts:
    - name: config-volume
      mountPath: /etc/config
      readOnly: true
  volumes:
  - name: config-volume
    configMap:
      name: dawn-config
```

**Result in container:**
```bash
/etc/config/
├── ENVIRONMENT       # Contains: "production"
├── PORT              # Contains: "8000"
├── LOG_LEVEL         # Contains: "info"
└── app.properties    # Contains: multi-line content
```

**Behavior:**
- ✅ **Files automatically update** when ConfigMap changes
- ✅ Update propagation time: ~60 seconds (kubelet sync period)
- ❌ **Application still needs to detect and reload changes**
- ✅ Supports partial updates (mount specific keys)

**When ConfigMap updates:**
```
1. You update ConfigMap
2. Kubelet syncs changes to mounted volumes (~60s delay)
3. Files in /etc/config are updated
4. Application must detect file changes and reload
5. No pod restart required (if app supports reload)
```

### Method 3: Immutable ConfigMaps (Recommended for Gradual Rollouts)

**How it works:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: dawn-config-v2  # ← Versioned name
immutable: true          # ← Prevents modifications
data:
  LOG_LEVEL: "debug"
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dawn
spec:
  template:
    spec:
      containers:
      - name: app
        envFrom:
        - configMapRef:
            name: dawn-config-v2  # ← Reference specific version
```

**Behavior:**
- ✅ **ConfigMap cannot be modified** after creation
- ✅ **Explicit version control** built into name
- ✅ **Atomic rollout** via Deployment update
- ✅ **Easy rollback** to previous ConfigMap version
- ✅ **No accidental changes** to running config
- ✅ **Performance benefit** - kubelet doesn't watch for changes

**When config updates:**
```
1. Create new ConfigMap (dawn-config-v3)
2. Update Deployment to reference new ConfigMap
3. Deployment rolling update replaces pods gradually
4. New pods use new config, old pods use old config
5. Controlled gradual rollout
```

---

## The ConfigMap Update Problem

### The Core Issue

When you update a ConfigMap, Kubernetes does **NOT** automatically restart pods using it.

```
┌─────────────────────────────────────────────────┐
│ What developers EXPECT:                         │
│                                                  │
│  1. Update ConfigMap                             │
│  2. Pods automatically restart                   │
│  3. New config is live                           │
│                                                  │
│  Reality: ❌ Doesn't work this way!              │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ What ACTUALLY happens:                           │
│                                                  │
│  1. Update ConfigMap                             │
│  2. Environment variables: NO CHANGE             │
│  3. Volume mounts: Files updated in ~60s         │
│  4. Application: Still using old config          │
│                                                  │
│  Solution: Implement a rollout strategy          │
└─────────────────────────────────────────────────┘
```

### Why Doesn't Kubernetes Auto-Restart?

**Design philosophy:**
- ConfigMaps are **decoupled** from Pods
- Multiple Pods can share same ConfigMap
- Pods can use multiple ConfigMaps
- Kubernetes doesn't know if config change requires restart

**The problem with auto-restart:**
```
One ConfigMap → Used by 10 Deployments → 100 Pods total

If Kubernetes auto-restarted on ConfigMap changes:
- Updating one key would restart ALL 100 pods
- No control over rollout speed
- Potential service disruption
```

**The solution:** You control when and how pods pick up config changes.

---

## Strategy 1: Rolling Updates with Immutable ConfigMaps

**Best for:** Production environments, strict change control, configs requiring restart

### The Concept

Treat ConfigMaps like container images - **versioned and immutable**.

```
Old version:                      New version:
┌──────────────────────┐         ┌──────────────────────┐
│ dawn-config-v1       │         │ dawn-config-v2       │
│ LOG_LEVEL: info      │         │ LOG_LEVEL: debug     │
│ immutable: true      │         │ immutable: true      │
└──────────────────────┘         └──────────────────────┘
          ↑                                ↑
          │                                │
    ┌─────┴──────┐                  ┌─────┴──────┐
    │ Old Pods   │  Rolling Update  │ New Pods   │
    │ (2 pods)   │  ────────────→   │ (2 pods)   │
    └────────────┘                  └────────────┘
```

### Implementation

#### Step 1: Create Versioned ConfigMap

```bash
# Current ConfigMap
kubectl get configmap dawn-config -n dawn-ns -o yaml > config-v2.yaml
```

**config-v2.yaml:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: dawn-config-v2  # ← Changed name
  namespace: dawn-ns
  labels:
    app: dawn
    version: v2         # ← Version label
immutable: true         # ← Make it immutable
data:
  ENVIRONMENT: "production"
  PORT: "8000"
  LOG_LEVEL: "debug"    # ← Changed from "info" to "debug"
  SERVICE_NAME: "Dawn"
```

```bash
kubectl apply -f config-v2.yaml
```

#### Step 2: Update Deployment to Reference New ConfigMap

```bash
kubectl edit deployment dawn -n dawn-ns
```

**Change this:**
```yaml
spec:
  template:
    spec:
      containers:
      - name: dawn
        envFrom:
        - configMapRef:
            name: dawn-config     # ← Old version
```

**To this:**
```yaml
spec:
  template:
    metadata:
      labels:
        app: dawn
        config-version: v2        # ← Optional: track config version
    spec:
      containers:
      - name: dawn
        envFrom:
        - configMapRef:
            name: dawn-config-v2  # ← New version
```

**What happens:**
- Pod template hash changes (because ConfigMap reference changed)
- Deployment creates new ReplicaSet
- Rolling update begins automatically
- Old pods keep using dawn-config-v1
- New pods use dawn-config-v2

#### Step 3: Monitor the Rollout

```bash
# Watch the rolling update
kubectl rollout status deployment/dawn -n dawn-ns

# Output:
Waiting for deployment "dawn" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "dawn" rollout to finish: 1 old replicas are pending termination...
deployment "dawn" successfully rolled out
```

```bash
# See both old and new pods during rollout
kubectl get pods -n dawn-ns -w

NAME                    READY   STATUS    RESTARTS   AGE
dawn-7d4f9c8b5f-abc12   1/1     Running   0          5m    ← Old config
dawn-7d4f9c8b5f-def34   1/1     Running   0          5m    ← Old config
dawn-9e6g0d1c4h-xyz99   0/1     Pending   0          0s    ← New config
dawn-9e6g0d1c4h-xyz99   0/1     ContainerCreating   0      1s
dawn-9e6g0d1c4h-xyz99   1/1     Running             0      15s
dawn-7d4f9c8b5f-abc12   1/1     Terminating         0      5m
```

#### Step 4: Verify New Config

```bash
# Get a new pod
POD=$(kubectl get pods -n dawn-ns -l app=dawn --sort-by=.metadata.creationTimestamp | tail -1 | awk '{print $1}')

# Check environment variables
kubectl exec -n dawn-ns $POD -- env | grep LOG_LEVEL
# Output: LOG_LEVEL=debug

# Or check application logs
kubectl logs -n dawn-ns $POD --tail=20
```

#### Step 5: Cleanup Old ConfigMap (Optional)

After confirming the rollout is successful:

```bash
# Old ConfigMap is no longer referenced by any pods
kubectl delete configmap dawn-config-v1 -n dawn-ns
```

### Rollback Procedure

If the new config causes issues:

```bash
# Rollback deployment (goes back to previous ReplicaSet)
kubectl rollout undo deployment/dawn -n dawn-ns

# What happens:
# 1. Deployment scales up old ReplicaSet (using dawn-config-v1)
# 2. Deployment scales down new ReplicaSet (using dawn-config-v2)
# 3. Pods gradually revert to old configuration
```

### Automation with Scripts

**create-config-version.sh:**
```bash
#!/bin/bash
set -e

NAMESPACE="dawn-ns"
BASE_NAME="dawn-config"
VERSION="$1"

if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 v3"
  exit 1
fi

CONFIG_NAME="${BASE_NAME}-${VERSION}"

echo "Creating ConfigMap: $CONFIG_NAME"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: $CONFIG_NAME
  namespace: $NAMESPACE
  labels:
    app: dawn
    version: $VERSION
immutable: true
data:
  ENVIRONMENT: "production"
  PORT: "8000"
  LOG_LEVEL: "debug"
  SERVICE_NAME: "Dawn"
EOF

echo "✓ ConfigMap created: $CONFIG_NAME"
echo ""
echo "Next steps:"
echo "1. Update deployment: kubectl set env deployment/dawn -n $NAMESPACE --from=configmap/$CONFIG_NAME"
echo "2. Monitor rollout: kubectl rollout status deployment/dawn -n $NAMESPACE"
```

**Usage:**
```bash
chmod +x create-config-version.sh
./create-config-version.sh v3
```

### Advantages

- ✅ **Explicit version control** - Clear which config version is deployed
- ✅ **Atomic rollouts** - All-or-nothing config updates
- ✅ **Easy rollback** - Just rollback the Deployment
- ✅ **No accidents** - Immutable prevents accidental changes
- ✅ **Gradual rollout** - Leverages Deployment's rolling update
- ✅ **Safe** - Old pods keep working during rollout
- ✅ **Auditable** - Clear history of config changes

### Disadvantages

- ❌ **Proliferation of ConfigMaps** - Creates many ConfigMap objects
- ❌ **Manual cleanup** - Need to delete old ConfigMaps
- ❌ **Deployment update required** - Can't update config without changing Deployment

### When to Use

- ✅ Production environments
- ✅ Configs consumed as environment variables
- ✅ Strict change control requirements
- ✅ Need audit trail of config changes
- ✅ Applications that can't reload config at runtime

---

## Strategy 2: Automatic Restart on ConfigMap Change

**Best for:** Development/staging environments, simpler workflows, configs requiring restart

### The Concept

Use a tool that **watches ConfigMaps** and **automatically restarts pods** when they change.

```
┌─────────────────────────────────────────────────────┐
│ Developer updates ConfigMap                          │
│         ↓                                            │
│ Reloader detects change                              │
│         ↓                                            │
│ Reloader triggers Deployment rolling restart         │
│         ↓                                            │
│ Pods gradually restart with new config               │
└─────────────────────────────────────────────────────┘
```

### Option A: Stakater Reloader

**Stakater Reloader** is a popular Kubernetes controller that watches ConfigMaps/Secrets and triggers pod restarts.

#### Installation

```bash
# Add Stakater Helm repo
helm repo add stakater https://stakater.github.io/stakater-charts
helm repo update

# Install Reloader
helm install reloader stakater/reloader \
  --namespace kube-system \
  --set reloader.watchGlobally=true
```

**Verify installation:**
```bash
kubectl get pods -n kube-system -l app=reloader

NAME                       READY   STATUS    RESTARTS   AGE
reloader-xxxxxxxxx-xxxxx   1/1     Running   0          1m
```

#### Usage: Auto-reload Specific Deployments

**Annotate your Deployment:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dawn
  namespace: dawn-ns
  annotations:
    reloader.stakater.com/auto: "true"  # ← Enable auto-reload
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: dawn
        image: dawn:latest
        envFrom:
        - configMapRef:
            name: dawn-config
```

**Apply the annotation:**
```bash
kubectl annotate deployment dawn -n dawn-ns \
  reloader.stakater.com/auto="true"
```

**Now when you update the ConfigMap:**
```bash
kubectl edit configmap dawn-config -n dawn-ns
# Change LOG_LEVEL from "info" to "debug"
```

**Reloader automatically:**
1. Detects ConfigMap change (~5s)
2. Triggers rolling restart of Deployment
3. Pods restart one-by-one (respects `maxSurge` and `maxUnavailable`)
4. New pods pick up new config

#### Usage: Reload on Specific ConfigMaps

**More granular control:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dawn
  namespace: dawn-ns
  annotations:
    # Only reload when these ConfigMaps change
    reloader.stakater.com/match: "true"
    configmap.reloader.stakater.com/reload: "dawn-config,shared-config"
spec:
  # ... rest of deployment
```

#### How It Works

```
┌──────────────────────────────────────────────┐
│ Reloader Controller (in kube-system)         │
│                                              │
│ while True:                                  │
│   for deployment in watched_deployments:     │
│     configmaps = get_referenced_configmaps() │
│     current_hash = compute_hash(configmaps)  │
│                                              │
│     if current_hash != last_known_hash:      │
│       trigger_rolling_restart(deployment)    │
│       last_known_hash = current_hash         │
│                                              │
│   sleep(5)                                   │
└──────────────────────────────────────────────┘
```

**Reloader adds an annotation to pod template:**
```yaml
spec:
  template:
    metadata:
      annotations:
        # Auto-generated by Reloader
        reloader.stakater.com/last-reloaded-from: "2025-11-15T12:30:00Z"
```

This changes the pod template hash → triggers rolling update.

#### Monitor Reloader

```bash
# Check Reloader logs
kubectl logs -n kube-system -l app=reloader --tail=50 -f

# Example output:
time="2025-11-15T12:30:00Z" level=info msg="Changes detected in 'dawn-config' of type 'CONFIGMAP' in namespace 'dawn-ns'"
time="2025-11-15T12:30:00Z" level=info msg="Updated deployment 'dawn' in namespace 'dawn-ns'"
```

### Option B: Manual Restart with Hash Annotation

**DIY approach without installing Reloader:**

Update Deployment's pod template whenever ConfigMap changes.

```bash
# Compute hash of ConfigMap
CONFIG_HASH=$(kubectl get configmap dawn-config -n dawn-ns -o yaml | sha256sum | cut -d ' ' -f1)

# Update Deployment annotation
kubectl patch deployment dawn -n dawn-ns -p \
  "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"configHash\":\"$CONFIG_HASH\"}}}}}"
```

**This triggers a rolling restart because pod template changed.**

**Automation script:**
```bash
#!/bin/bash
NAMESPACE="dawn-ns"
CONFIGMAP="dawn-config"
DEPLOYMENT="dawn"

# Get ConfigMap hash
HASH=$(kubectl get configmap $CONFIGMAP -n $NAMESPACE -o yaml | sha256sum | cut -d' ' -f1)

# Patch deployment
kubectl patch deployment $DEPLOYMENT -n $NAMESPACE -p \
  "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"configmap.hash\":\"$HASH\"}}}}}"

echo "✓ Triggered rolling restart for $DEPLOYMENT"
```

### Option C: Simple Rollout Restart

**Simplest approach:**

```bash
# Update ConfigMap
kubectl edit configmap dawn-config -n dawn-ns

# Manually trigger rolling restart
kubectl rollout restart deployment/dawn -n dawn-ns

# Monitor
kubectl rollout status deployment/dawn -n dawn-ns
```

**Pros:**
- ✅ No additional tools needed
- ✅ Simple and explicit
- ✅ Full control

**Cons:**
- ❌ Manual process
- ❌ Easy to forget
- ❌ Not automated

### Advantages of Auto-Restart Strategy

- ✅ **Simple workflow** - Just edit ConfigMap, pods restart automatically
- ✅ **Single ConfigMap** - No version proliferation
- ✅ **Automated** - No manual intervention needed (with Reloader)
- ✅ **Works with env vars and volumes** - Handles both consumption methods

### Disadvantages

- ❌ **Always causes restart** - Even if app could reload config at runtime
- ❌ **Service disruption** - Brief downtime during rolling restart
- ❌ **Extra dependency** - Need to install and maintain Reloader
- ❌ **Riskier** - Easy to accidentally trigger restarts

### When to Use

- ✅ Development and staging environments
- ✅ Applications that require restart for config changes
- ✅ Teams that prefer simpler workflow over strict version control
- ✅ ConfigMaps consumed as environment variables

---

## Strategy 3: Runtime Configuration Reload

**Best for:** Applications that support hot-reload, high availability requirements, configs as mounted files

### The Concept

ConfigMaps mounted as volumes **automatically update** in pods. Your application watches the files and reloads when they change - **without restarting**.

```
┌────────────────────────────────────────────────┐
│ Update ConfigMap                                │
│         ↓                                       │
│ Kubelet syncs to volume (~60s)                  │
│         ↓                                       │
│ Application detects file change                 │
│         ↓                                       │
│ Application reloads config                      │
│         ↓                                       │
│ ✅ New config active (NO POD RESTART)           │
└────────────────────────────────────────────────┘
```

### How ConfigMap Volume Mounts Work

#### The Mechanism

When you mount a ConfigMap as a volume:

```yaml
volumes:
- name: config
  configMap:
    name: dawn-config
```

Kubernetes creates a **symbolic link chain**:

```bash
# Inside the container at /etc/config

/etc/config/                          # ← Your mount point
  ├── LOG_LEVEL -> ..data/LOG_LEVEL   # ← Symlink to file
  ├── PORT -> ..data/PORT
  └── ..data -> ..2025_11_15_12_30_00  # ← Symlink to timestamped dir
       └── ..2025_11_15_12_30_00/     # ← Actual files
            ├── LOG_LEVEL
            └── PORT
```

**When ConfigMap updates:**
1. Kubelet detects ConfigMap change (polls every ~60s)
2. Creates new timestamped directory with new content
3. **Atomically updates `..data` symlink** to point to new directory
4. Old directory removed after grace period

**Result:** Files appear to update atomically from application's perspective.

### Implementation

#### Step 1: Mount ConfigMap as Volume

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dawn
  namespace: dawn-ns
spec:
  replicas: 2
  selector:
    matchLabels:
      app: dawn
  template:
    metadata:
      labels:
        app: dawn
    spec:
      containers:
      - name: dawn
        image: dawn:latest
        volumeMounts:
        - name: config
          mountPath: /etc/app-config
          readOnly: true
      volumes:
      - name: config
        configMap:
          name: dawn-config
```

**ConfigMap:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: dawn-config
  namespace: dawn-ns
data:
  config.yaml: |
    log_level: info
    feature_flags:
      new_ui: true
      experimental: false
    database:
      pool_size: 10
      timeout: 30s
```

#### Step 2: Application Code to Watch Config Files

**Python example with watchdog:**

```python
import yaml
import time
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

class ConfigReloader(FileSystemEventHandler):
    def __init__(self, config_path):
        self.config_path = config_path
        self.config = self.load_config()

    def load_config(self):
        with open(self.config_path, 'r') as f:
            config = yaml.safe_load(f)
        print(f"Config loaded: {config}")
        return config

    def on_modified(self, event):
        # The actual file path is a symlink, watch the resolved path
        if event.src_path == self.config_path or \
           event.src_path.endswith('..data'):
            print(f"Config file changed, reloading...")
            time.sleep(1)  # Debounce rapid changes
            self.config = self.load_config()
            # Apply new config to running application
            apply_config(self.config)

# Initialize
config_path = '/etc/app-config/config.yaml'
handler = ConfigReloader(config_path)

# Watch for changes
observer = Observer()
observer.schedule(handler, path='/etc/app-config', recursive=False)
observer.start()

print(f"Watching config file: {config_path}")

# Your application runs here
run_application(handler.config)
```

**Go example with fsnotify:**

```go
package main

import (
    "fmt"
    "log"
    "github.com/fsnotify/fsnotify"
    "gopkg.in/yaml.v2"
    "io/ioutil"
    "time"
)

type Config struct {
    LogLevel string `yaml:"log_level"`
    Database struct {
        PoolSize int    `yaml:"pool_size"`
        Timeout  string `yaml:"timeout"`
    } `yaml:"database"`
}

func loadConfig(path string) (*Config, error) {
    data, err := ioutil.ReadFile(path)
    if err != nil {
        return nil, err
    }

    var config Config
    err = yaml.Unmarshal(data, &config)
    return &config, err
}

func watchConfig(path string, reload func(*Config)) {
    watcher, err := fsnotify.NewWatcher()
    if err != nil {
        log.Fatal(err)
    }
    defer watcher.Close()

    // Watch the parent directory (ConfigMap mounts update via symlink)
    err = watcher.Add("/etc/app-config")
    if err != nil {
        log.Fatal(err)
    }

    debounce := time.NewTimer(time.Second)
    debounce.Stop()

    for {
        select {
        case event := <-watcher.Events:
            // ConfigMap updates come as Create events on ..data symlink
            if event.Op&fsnotify.Create == fsnotify.Create {
                debounce.Reset(time.Second)
            }
        case <-debounce.C:
            log.Println("Config changed, reloading...")
            config, err := loadConfig(path)
            if err != nil {
                log.Printf("Error loading config: %v", err)
            } else {
                reload(config)
            }
        case err := <-watcher.Errors:
            log.Printf("Watcher error: %v", err)
        }
    }
}

func main() {
    configPath := "/etc/app-config/config.yaml"

    // Initial load
    config, err := loadConfig(configPath)
    if err != nil {
        log.Fatal(err)
    }

    // Start watching in background
    go watchConfig(configPath, func(newConfig *Config) {
        config = newConfig
        fmt.Printf("New config applied: %+v\n", config)
        // Apply to your running application
    })

    // Run application with config
    runApplication(config)
}
```

**Node.js example with chokidar:**

```javascript
const fs = require('fs');
const yaml = require('js-yaml');
const chokidar = require('chokidar');

class ConfigManager {
  constructor(configPath) {
    this.configPath = configPath;
    this.config = this.loadConfig();
    this.watchConfig();
  }

  loadConfig() {
    const fileContents = fs.readFileSync(this.configPath, 'utf8');
    const config = yaml.load(fileContents);
    console.log('Config loaded:', config);
    return config;
  }

  watchConfig() {
    // Watch the parent directory for changes
    const watcher = chokidar.watch('/etc/app-config', {
      persistent: true,
      ignoreInitial: true,
      awaitWriteFinish: {
        stabilityThreshold: 1000,
        pollInterval: 100
      }
    });

    watcher.on('change', (path) => {
      if (path.includes('..data') || path === this.configPath) {
        console.log('Config file changed, reloading...');
        this.config = this.loadConfig();
        this.applyConfig();
      }
    });
  }

  applyConfig() {
    // Apply configuration to running application
    console.log('Applying new config:', this.config);
    // Update log level, feature flags, etc.
  }

  getConfig() {
    return this.config;
  }
}

// Usage
const configManager = new ConfigManager('/etc/app-config/config.yaml');

// Your application uses configManager.getConfig()
```

#### Step 3: Update ConfigMap and Observe

```bash
# Update ConfigMap
kubectl edit configmap dawn-config -n dawn-ns
# Change: log_level: info → log_level: debug

# Watch application logs
kubectl logs -n dawn-ns -l app=dawn -f

# Expected output:
Config file changed, reloading...
Config loaded: {'log_level': 'debug', ...}
Applying new config: log_level=debug
```

**Timeline:**
```
T+0s:   Update ConfigMap via kubectl
T+1s:   Change persisted to etcd
T+30s:  Kubelet sync period triggers
T+31s:  New config files appear in container
T+32s:  Application's file watcher triggers
T+33s:  Application reloads config
        ✅ New config active, NO RESTART!
```

### Gradual Rollout with Canary Pattern

Even with runtime reload, you may want **gradual rollout** to verify config changes:

#### Strategy: Multiple Deployments

```yaml
# Stable deployment (90% of traffic)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dawn-stable
spec:
  replicas: 9
  selector:
    matchLabels:
      app: dawn
      track: stable
  template:
    spec:
      volumes:
      - name: config
        configMap:
          name: dawn-config-stable  # ← Stable config
```

```yaml
# Canary deployment (10% of traffic)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dawn-canary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dawn
      track: canary
  template:
    spec:
      volumes:
      - name: config
        configMap:
          name: dawn-config-canary  # ← New config
```

**Service routes to both:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: dawn-service
spec:
  selector:
    app: dawn  # ← Matches both stable and canary
```

**Rollout process:**
1. Update `dawn-config-canary` with new config
2. Monitor canary metrics/logs
3. If successful, update `dawn-config-stable`
4. If issues, rollback canary

### Advantages of Runtime Reload

- ✅ **No pod restarts** - Zero downtime for config changes
- ✅ **Fast updates** - Config changes propagate in ~60 seconds
- ✅ **Gradual rollout** - Updates propagate to pods one by one
- ✅ **High availability** - No service interruption
- ✅ **Stateful apps friendly** - No need to restart long-running processes

### Disadvantages

- ❌ **Application complexity** - Need to implement file watching and reload logic
- ❌ **Only works with volumes** - Doesn't help with env vars
- ❌ **Sync delay** - ~60s kubelet sync period
- ❌ **Potential bugs** - Reload logic can be tricky (race conditions, partial updates)
- ❌ **Not all configs can reload** - Some settings require process restart

### When to Use

- ✅ Applications that support hot config reload
- ✅ High availability requirements (can't tolerate pod restarts)
- ✅ Frequent configuration changes
- ✅ Stateful applications with long-running sessions
- ✅ Configuration that doesn't require process restart

---

## Comparison of Strategies

| Aspect | Immutable ConfigMaps | Auto-Restart (Reloader) | Runtime Reload |
|--------|---------------------|------------------------|----------------|
| **Pod Restarts** | ✅ Yes (rolling) | ✅ Yes (rolling) | ❌ No |
| **Downtime** | ⚠️ Brief (rolling) | ⚠️ Brief (rolling) | ✅ Zero |
| **Complexity** | Low | Low | High |
| **Version Control** | ✅ Explicit | ❌ Implicit | ❌ Implicit |
| **Rollback** | ✅ Easy (deployment) | ⚠️ Manual ConfigMap edit | ⚠️ Manual ConfigMap edit |
| **Works with Env Vars** | ✅ Yes | ✅ Yes | ❌ No (volumes only) |
| **Additional Tools** | ❌ None | ⚠️ Reloader | ⚠️ File watcher lib |
| **Update Speed** | Fast (< 30s) | Fast (< 30s) | Medium (~60s) |
| **Audit Trail** | ✅ Clear | ⚠️ ConfigMap history | ⚠️ ConfigMap history |
| **Stateful App Friendly** | ❌ No | ❌ No | ✅ Yes |
| **ConfigMap Proliferation** | ❌ Many versions | ✅ Single ConfigMap | ✅ Single ConfigMap |
| **Best For** | Production | Dev/Staging | HA apps with reload |

### Decision Tree

```
Do you need to update config without pod restart?
│
├─ YES → Can your app reload config at runtime?
│   │
│   ├─ YES → Use Strategy 3 (Runtime Reload)
│   │         Mount ConfigMap as volume, implement file watcher
│   │
│   └─ NO → Not possible, must restart pods
│             Continue to next question
│
└─ NO (pod restart is acceptable)
    │
    ├─ Need strict version control and audit trail?
    │   │
    │   └─ YES → Use Strategy 1 (Immutable ConfigMaps)
    │             Best for production
    │
    └─ Prefer simpler workflow?
        │
        └─ YES → Use Strategy 2 (Auto-Restart with Reloader)
                  Best for dev/staging
```

---

## Hands-On Examples

### Example 1: Immutable ConfigMap Rollout

```bash
# Current state
kubectl get configmap dawn-config -n dawn-ns
kubectl get deployment dawn -n dawn-ns -o jsonpath='{.spec.template.spec.containers[0].envFrom[0].configMapRef.name}'

# Create v2 with new log level
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: dawn-config-v2
  namespace: dawn-ns
immutable: true
data:
  LOG_LEVEL: "debug"
  PORT: "8000"
  ENVIRONMENT: "production"
EOF

# Update deployment to use v2
kubectl set env deployment/dawn -n dawn-ns --from=configmap/dawn-config-v2

# Watch rollout
kubectl rollout status deployment/dawn -n dawn-ns

# Verify
kubectl get pods -n dawn-ns
kubectl exec -n dawn-ns $(kubectl get pod -n dawn-ns -l app=dawn -o jsonpath='{.items[0].metadata.name}') -- env | grep LOG_LEVEL

# Rollback if needed
kubectl rollout undo deployment/dawn -n dawn-ns
```

### Example 2: Reloader Setup

```bash
# Install Reloader
helm repo add stakater https://stakater.github.io/stakater-charts
helm install reloader stakater/reloader -n kube-system

# Annotate deployment
kubectl annotate deployment dawn -n dawn-ns \
  reloader.stakater.com/auto="true"

# Update ConfigMap
kubectl patch configmap dawn-config -n dawn-ns \
  -p '{"data":{"LOG_LEVEL":"warn"}}'

# Watch Reloader trigger restart
kubectl logs -n kube-system -l app=reloader -f

# Watch pods restart
kubectl get pods -n dawn-ns -w
```

### Example 3: Runtime Reload

**Create ConfigMap with config file:**
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: dawn-ns
data:
  config.yaml: |
    log_level: info
    features:
      new_ui: false
    database:
      pool_size: 10
EOF
```

**Update deployment to mount config:**
```bash
kubectl patch deployment dawn -n dawn-ns --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/volumes",
    "value": [{"name": "config", "configMap": {"name": "app-config"}}]
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/volumeMounts",
    "value": [{"name": "config", "mountPath": "/etc/config"}]
  }
]'
```

**Verify mount:**
```bash
POD=$(kubectl get pod -n dawn-ns -l app=dawn -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n dawn-ns $POD -- cat /etc/config/config.yaml
```

**Update ConfigMap:**
```bash
kubectl patch configmap app-config -n dawn-ns --type='merge' -p='
{
  "data": {
    "config.yaml": "log_level: debug\nfeatures:\n  new_ui: true\ndatabase:\n  pool_size: 20\n"
  }
}'
```

**Watch file update in pod (may take up to 60s):**
```bash
kubectl exec -n dawn-ns $POD -- watch -n 2 cat /etc/config/config.yaml
```

---

## Production Best Practices

### 1. Use Immutable ConfigMaps in Production

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-v1-20251115
  namespace: production
  labels:
    app: myapp
    version: v1
    date: "20251115"
immutable: true  # ← Always set this in production
data:
  config: "..."
```

**Benefits:**
- Prevents accidental changes
- Clear version history
- Easier rollback
- Performance improvement (kubelet doesn't watch)

### 2. Version ConfigMaps with Semantic Versioning

```bash
# Bad: Unclear versioning
app-config
app-config-new
app-config-latest
app-config-2

# Good: Clear semantic versioning
app-config-v1.0.0
app-config-v1.1.0
app-config-v2.0.0

# Or timestamp-based
app-config-20251115-120000
app-config-20251115-153000
```

### 3. Automate Cleanup of Old ConfigMaps

```bash
#!/bin/bash
# cleanup-old-configmaps.sh

NAMESPACE="production"
KEEP_COUNT=5  # Keep last 5 versions

# Get all ConfigMaps for app, sorted by creation time
kubectl get configmap -n $NAMESPACE \
  -l app=myapp \
  --sort-by=.metadata.creationTimestamp \
  -o name | head -n -$KEEP_COUNT | xargs -r kubectl delete -n $NAMESPACE
```

**Run via CronJob:**
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cleanup-configmaps
spec:
  schedule: "0 2 * * 0"  # Weekly at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: configmap-cleaner
          containers:
          - name: cleanup
            image: bitnami/kubectl:latest
            command: ["/bin/bash", "/scripts/cleanup-old-configmaps.sh"]
```

### 4. Use ConfigMap Annotations for Metadata

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-v2
  annotations:
    config.version: "2.0.0"
    deployed.by: "jane@example.com"
    deployed.at: "2025-11-15T12:00:00Z"
    rollback.from: "app-config-v1"
    jira.ticket: "PROJ-1234"
    description: "Enable new feature flags for Q4 release"
data:
  config: "..."
```

### 5. Validate ConfigMaps Before Deployment

```bash
#!/bin/bash
# validate-configmap.sh

CONFIG_FILE="$1"

# Check YAML syntax
if ! kubectl apply --dry-run=client -f "$CONFIG_FILE" > /dev/null 2>&1; then
  echo "❌ Invalid YAML syntax"
  exit 1
fi

# Check for required keys
REQUIRED_KEYS="LOG_LEVEL PORT ENVIRONMENT"
for key in $REQUIRED_KEYS; do
  if ! kubectl get -f "$CONFIG_FILE" -o jsonpath="{.data.$key}" > /dev/null 2>&1; then
    echo "❌ Missing required key: $key"
    exit 1
  fi
done

# Validate values
LOG_LEVEL=$(kubectl get -f "$CONFIG_FILE" -o jsonpath='{.data.LOG_LEVEL}')
if [[ ! "$LOG_LEVEL" =~ ^(debug|info|warn|error)$ ]]; then
  echo "❌ Invalid LOG_LEVEL: $LOG_LEVEL"
  exit 1
fi

echo "✅ ConfigMap validation passed"
```

### 6. Use Git as Source of Truth

```
Git Repo (main)
    ↓
  CI/CD Pipeline
    ↓
  1. Validate ConfigMap
  2. Run tests
  3. Create versioned ConfigMap
  4. Update Deployment
    ↓
  Kubernetes Cluster
```

**Example GitHub Actions workflow:**
```yaml
name: Deploy ConfigMap

on:
  push:
    paths:
      - 'k8s/configmaps/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Generate version
        id: version
        run: |
          VERSION="v$(date +%Y%m%d-%H%M%S)"
          echo "version=$VERSION" >> $GITHUB_OUTPUT

      - name: Create versioned ConfigMap
        run: |
          # Replace placeholder with actual version
          sed "s/{{VERSION}}/${{ steps.version.outputs.version }}/g" \
            k8s/configmaps/app-config.yaml > /tmp/config.yaml

      - name: Validate
        run: kubectl apply --dry-run=client -f /tmp/config.yaml

      - name: Deploy
        run: |
          kubectl apply -f /tmp/config.yaml
          kubectl set env deployment/app \
            --from=configmap/app-config-${{ steps.version.outputs.version }}
```

### 7. Separate Configs by Environment

```
k8s/
├── base/
│   └── configmap-template.yaml
├── overlays/
│   ├── dev/
│   │   └── configmap.yaml          # LOG_LEVEL=debug
│   ├── staging/
│   │   └── configmap.yaml          # LOG_LEVEL=info
│   └── production/
│       └── configmap.yaml          # LOG_LEVEL=warn
```

**Using Kustomize:**
```bash
# Deploy to production
kubectl apply -k k8s/overlays/production
```

### 8. Monitor ConfigMap Changes

```yaml
# Prometheus alert
- alert: ConfigMapChanged
  expr: |
    rate(kube_configmap_info[5m]) > 0
  annotations:
    summary: "ConfigMap {{ $labels.configmap }} changed in {{ $labels.namespace }}"
```

### 9. Test Config Changes in Non-Prod First

```
1. Update ConfigMap in dev
2. Deploy to dev cluster
3. Run automated tests
4. Manual QA verification
5. Promote to staging
6. Repeat tests
7. Promote to production
```

### 10. Document Your Strategy

```yaml
# configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-v1
  annotations:
    # IMPORTANT: This ConfigMap uses immutable rollout strategy
    # To update:
    # 1. Create new ConfigMap with incremented version
    # 2. Update Deployment reference: kubectl set env deployment/app --from=configmap/app-config-v2
    # 3. Monitor rollout: kubectl rollout status deployment/app
    # 4. Rollback if needed: kubectl rollout undo deployment/app
    rollout.strategy: "immutable-configmap"
immutable: true
```

---

## Troubleshooting

### ConfigMap Updates Not Appearing in Pods

**Symptom:** Updated ConfigMap, but pods still use old values

**For environment variables:**
```bash
# Check current env vars
kubectl exec -n dawn-ns <pod-name> -- env

# Environment variables NEVER update in running pods
# Solution: Restart pods
kubectl rollout restart deployment/dawn -n dawn-ns
```

**For volume mounts:**
```bash
# Check if files updated
kubectl exec -n dawn-ns <pod-name> -- cat /etc/config/config.yaml

# Files should update within ~60s
# If not updated after 2 minutes:

# 1. Check kubelet sync period
kubectl get --raw /api/v1/nodes/<node-name>/proxy/configz | jq '.kubeletconfig.syncFrequency'

# 2. Check if using subPath (blocks updates!)
kubectl get deployment dawn -n dawn-ns -o yaml | grep subPath
# If using subPath, updates won't propagate - remove it

# 3. Force kubelet sync
kubectl delete pod <pod-name> -n dawn-ns  # Pod will be recreated
```

### SubPath Blocks Updates

**Problem:**
```yaml
volumeMounts:
- name: config
  mountPath: /etc/app/config.yaml
  subPath: config.yaml  # ← This blocks automatic updates!
```

**Why:** `subPath` creates a bind mount of the specific file, not the symlink chain. Updates to ConfigMap won't propagate.

**Solution 1: Mount entire ConfigMap**
```yaml
volumeMounts:
- name: config
  mountPath: /etc/app-config  # ← Mount directory, not specific file
```

**Solution 2: Use init container to copy file**
```yaml
initContainers:
- name: copy-config
  image: busybox
  command: ['sh', '-c', 'cp /tmp/config/* /etc/app/']
  volumeMounts:
  - name: config-source
    mountPath: /tmp/config
  - name: config-dest
    mountPath: /etc/app

volumes:
- name: config-source
  configMap:
    name: app-config
- name: config-dest
  emptyDir: {}
```

### Rolling Update Stuck

**Symptom:** Deployment rollout doesn't complete

```bash
kubectl rollout status deployment/dawn -n dawn-ns
# Waiting for deployment "dawn" rollout to finish: 1 old replicas are pending termination...
```

**Check:**
```bash
# See what's wrong with new pods
kubectl get pods -n dawn-ns
kubectl describe pod <new-pod-name> -n dawn-ns

# Common causes:
# 1. New pods failing readiness probe (bad config)
# 2. PodDisruptionBudget blocking termination
# 3. Insufficient resources for new pods
```

**Solution:**
```bash
# If new config is bad, rollback immediately
kubectl rollout undo deployment/dawn -n dawn-ns

# If PDB is blocking
kubectl get pdb -n dawn-ns
kubectl delete pdb <pdb-name> -n dawn-ns  # Temporarily

# If resource issue
kubectl describe nodes | grep -A 5 "Allocated resources"
```

### Reloader Not Triggering

**Symptom:** ConfigMap updated but Reloader doesn't restart pods

```bash
# Check Reloader is running
kubectl get pods -n kube-system -l app=reloader

# Check Reloader logs
kubectl logs -n kube-system -l app=reloader --tail=100

# Check deployment has correct annotation
kubectl get deployment dawn -n dawn-ns -o jsonpath='{.metadata.annotations}'

# Should see: reloader.stakater.com/auto: "true"
```

**Common issues:**
1. Annotation missing or misspelled
2. Reloader watching wrong namespace
3. RBAC permissions missing

```bash
# Fix: Add annotation
kubectl annotate deployment dawn -n dawn-ns \
  reloader.stakater.com/auto="true" --overwrite

# Verify Reloader RBAC
kubectl get clusterrole reloader -o yaml
```

### Application Not Detecting File Changes

**Symptom:** ConfigMap files updated, but app still uses old config

**Debug:**
```bash
# Check if files actually updated
kubectl exec -n dawn-ns <pod-name> -- ls -la /etc/config/
kubectl exec -n dawn-ns <pod-name> -- cat /etc/config/config.yaml

# Check file watcher logs
kubectl logs -n dawn-ns <pod-name> | grep -i config

# Manually trigger file change to test watcher
kubectl exec -n dawn-ns <pod-name> -- touch /etc/config/config.yaml
```

**Common issues:**
1. Watching wrong path (should watch directory, not file)
2. Not handling symlink updates properly
3. App not responding to file change events

**Fix for symlink handling:**
```python
# Don't watch the symlink directly
# watcher.add('/etc/config/config.yaml')  # ❌ Won't catch updates

# Watch the parent directory
watcher.add('/etc/config')  # ✅ Catches symlink changes
```

### ConfigMap Too Large

**Symptom:** Error: ConfigMap exceeds maximum size

**Limit:** ConfigMaps are limited to **1 MiB** total size

```bash
# Check ConfigMap size
kubectl get configmap large-config -n dawn-ns -o yaml | wc -c
```

**Solutions:**

1. **Split into multiple ConfigMaps:**
```yaml
# app-config-1.yaml
data:
  part1: "..."

# app-config-2.yaml
data:
  part2: "..."
```

2. **Use Secrets for binary data:**
```yaml
# Binary data should go in Secrets
apiVersion: v1
kind: Secret
type: Opaque
data:
  certificate: <base64-encoded-cert>
```

3. **Store large files externally:**
```yaml
data:
  # Instead of embedding 500KB JSON file
  # Store reference
  data_url: "s3://my-bucket/large-data.json"
```

4. **Use ConfigMap per microservice:**
```bash
# Bad: One giant ConfigMap for everything
app-config (1.2 MiB) ❌

# Good: Split by service
auth-service-config (200 KB) ✅
api-service-config (300 KB) ✅
worker-service-config (150 KB) ✅
```

---

## Summary

### Key Takeaways

1. **ConfigMaps don't auto-restart pods** - You must implement a rollout strategy

2. **Three main strategies:**
   - **Immutable ConfigMaps** - Best for production, strict control
   - **Auto-Restart (Reloader)** - Best for dev/staging, simple workflow
   - **Runtime Reload** - Best for HA apps, zero-downtime requirements

3. **Environment variables require pod restart** - No way around this

4. **Volume mounts auto-update** - But app must detect and reload

5. **Gradual rollouts leverage Deployments** - Use rolling update mechanisms

6. **Version control is critical** - Treat config like code

### Decision Matrix

| Your Requirement | Recommended Strategy |
|-----------------|---------------------|
| Production environment with strict change control | Immutable ConfigMaps |
| Zero-downtime for config changes | Runtime Reload |
| Simple dev/staging workflow | Auto-Restart (Reloader) |
| Config consumed as environment variables | Immutable ConfigMaps or Auto-Restart |
| Config consumed as mounted files | Runtime Reload (if app supports) |
| Stateful apps with long-running sessions | Runtime Reload |
| Need clear audit trail | Immutable ConfigMaps |
| Frequent config changes | Runtime Reload or Auto-Restart |

### Best Practices Checklist

- ✅ Use `immutable: true` for production ConfigMaps
- ✅ Version ConfigMaps with clear naming (v1, v2, or timestamps)
- ✅ Automate ConfigMap cleanup (keep last N versions)
- ✅ Validate ConfigMaps before deployment
- ✅ Use Git as source of truth
- ✅ Test config changes in non-prod first
- ✅ Monitor ConfigMap changes
- ✅ Document your rollout strategy
- ✅ Avoid `subPath` if you need automatic updates
- ✅ Set appropriate `maxSurge` and `maxUnavailable` for rolling updates

---

## Further Reading

- [Kubernetes Documentation: ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Kubernetes Documentation: Configure Containers Using ConfigMaps](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/)
- [Stakater Reloader](https://github.com/stakater/Reloader)
- [Kubernetes Documentation: Immutable ConfigMaps and Secrets](https://kubernetes.io/docs/concepts/configuration/configmap/#configmap-immutable)
- [The Twelve-Factor App: Config](https://12factor.net/config)

---

**Related files in this repository:**
- `foundation/k8s/dawn/configmap.yaml` - Example ConfigMap
- `foundation/k8s/day/configmap.yaml` - Example ConfigMap
- `DEPLOYMENT-HIERARCHY.md` - How Deployments create Pods
