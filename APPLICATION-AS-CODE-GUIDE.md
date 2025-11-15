# Managing Kubernetes Applications as Code (Not YAML)

## The Question

"I want to manage my Deployments, ConfigMaps, HPAs, and Services using **code** (Python, TypeScript, Go) instead of YAML/JSON manifests. How do I do this?"

## TL;DR - Your Options

```
┌─────────────────────────────────────────────────────────┐
│ OPTION 1: Separate Pulumi Program (Recommended)        │
│ - Same tool as infrastructure, different repo/stack    │
│ - Python/TypeScript/Go/C#                              │
│ - Best for teams already using Pulumi                  │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ OPTION 2: CDK8s (Cloud Development Kit for Kubernetes) │
│ - TypeScript/Python/Java/Go                            │
│ - Generates YAML, then kubectl apply                   │
│ - Best for those who want K8s-native workflow          │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ OPTION 3: Helm + Code Generation                       │
│ - Generate values.yaml from code                       │
│ - Best for existing Helm ecosystem                     │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ OPTION 4: Client Libraries (client-go, Kubernetes SDK) │
│ - Direct API calls from Go/Python/Java                 │
│ - Best for custom controllers/operators                │
└─────────────────────────────────────────────────────────┘
```

## The Architecture: Separation Still Matters

Even when using code for everything, maintain separation:

```
┌──────────────────────────────────────────────────────────┐
│ Infrastructure Pulumi Program                            │
│ Repository: infrastructure/                              │
│ Stack: production-cluster                                │
│                                                          │
│ import pulumi_aws as aws                                 │
│ import pulumi_eks as eks                                 │
│                                                          │
│ cluster = eks.Cluster("my-cluster", ...)                 │
│ node_group = aws.eks.NodeGroup(...)                      │
└──────────────────────────────────────────────────────────┘
                         ↓ Outputs cluster config
┌──────────────────────────────────────────────────────────┐
│ Application Pulumi Program (Separate!)                   │
│ Repository: applications/day-service/                    │
│ Stack: day-production                                    │
│                                                          │
│ import pulumi_kubernetes as k8s                          │
│                                                          │
│ deployment = k8s.apps.v1.Deployment("day", ...)          │
│ configmap = k8s.core.v1.ConfigMap("config", ...)         │
│ hpa = k8s.autoscaling.v2.HorizontalPodAutoscaler(...)    │
└──────────────────────────────────────────────────────────┘
```

## Option 1: Separate Pulumi Program (Recommended)

### Project Structure
```
your-organization/
├── infrastructure/          # Infrastructure Pulumi program
│   └── pulumi/
│       └── __main__.py     # EKS, VPC, Node Groups
│
└── applications/           # Application Pulumi programs
    ├── day-service/
    │   ├── __main__.py     # Day service K8s resources
    │   ├── Pulumi.yaml
    │   └── requirements.txt
    └── dusk-service/
        ├── __main__.py     # Dusk service K8s resources
        ├── Pulumi.yaml
        └── requirements.txt
```

### Example: Day Service Application

**`applications/day-service/__main__.py`:**
```python
"""
Day Service Application Resources
Manages: Deployment, Service, ConfigMap, HPA, Ingress
"""

import pulumi
import pulumi_kubernetes as k8s

# Configuration
config = pulumi.Config()
app_name = "day-service"
namespace = config.get("namespace") or "production"
image_tag = config.get("image_tag") or "latest"
replicas = config.get_int("replicas") or 3
min_replicas = config.get_int("min_replicas") or 2
max_replicas = config.get_int("max_replicas") or 10

# Get cluster info from infrastructure stack
infra_stack = pulumi.StackReference(f"organization/infrastructure/production")
cluster_name = infra_stack.get_output("cluster_name")

# Labels for all resources
labels = {
    "app": app_name,
    "managed-by": "pulumi",
    "team": "day-team",
}

# ConfigMap for application configuration
config_map = k8s.core.v1.ConfigMap(
    f"{app_name}-config",
    metadata=k8s.meta.v1.ObjectMetaArgs(
        name=f"{app_name}-config",
        namespace=namespace,
        labels=labels,
    ),
    data={
        "LOG_LEVEL": config.get("log_level") or "INFO",
        "DATABASE_HOST": config.get("database_host") or "postgres.production.svc",
        "CACHE_TTL": config.get("cache_ttl") or "300",
        "FEATURE_FLAG_NEW_UI": config.get("feature_new_ui") or "true",
    },
)

# Deployment
deployment = k8s.apps.v1.Deployment(
    app_name,
    metadata=k8s.meta.v1.ObjectMetaArgs(
        name=app_name,
        namespace=namespace,
        labels=labels,
    ),
    spec=k8s.apps.v1.DeploymentSpecArgs(
        replicas=replicas,
        selector=k8s.meta.v1.LabelSelectorArgs(
            match_labels={"app": app_name},
        ),
        template=k8s.core.v1.PodTemplateSpecArgs(
            metadata=k8s.meta.v1.ObjectMetaArgs(
                labels=labels,
            ),
            spec=k8s.core.v1.PodSpecArgs(
                containers=[
                    k8s.core.v1.ContainerArgs(
                        name=app_name,
                        image=f"your-registry/{app_name}:{image_tag}",
                        ports=[
                            k8s.core.v1.ContainerPortArgs(
                                container_port=8080,
                                name="http",
                            )
                        ],
                        env_from=[
                            k8s.core.v1.EnvFromSourceArgs(
                                config_map_ref=k8s.core.v1.ConfigMapEnvSourceArgs(
                                    name=config_map.metadata["name"],
                                )
                            )
                        ],
                        resources=k8s.core.v1.ResourceRequirementsArgs(
                            requests={
                                "cpu": "100m",
                                "memory": "128Mi",
                            },
                            limits={
                                "cpu": "500m",
                                "memory": "512Mi",
                            },
                        ),
                        liveness_probe=k8s.core.v1.ProbeArgs(
                            http_get=k8s.core.v1.HTTPGetActionArgs(
                                path="/health",
                                port=8080,
                            ),
                            initial_delay_seconds=30,
                            period_seconds=10,
                        ),
                        readiness_probe=k8s.core.v1.ProbeArgs(
                            http_get=k8s.core.v1.HTTPGetActionArgs(
                                path="/ready",
                                port=8080,
                            ),
                            initial_delay_seconds=5,
                            period_seconds=5,
                        ),
                    )
                ],
            ),
        ),
    ),
)

# Service
service = k8s.core.v1.Service(
    app_name,
    metadata=k8s.meta.v1.ObjectMetaArgs(
        name=app_name,
        namespace=namespace,
        labels=labels,
    ),
    spec=k8s.core.v1.ServiceSpecArgs(
        type="ClusterIP",
        selector={"app": app_name},
        ports=[
            k8s.core.v1.ServicePortArgs(
                port=80,
                target_port=8080,
                protocol="TCP",
                name="http",
            )
        ],
    ),
)

# HorizontalPodAutoscaler
hpa = k8s.autoscaling.v2.HorizontalPodAutoscaler(
    f"{app_name}-hpa",
    metadata=k8s.meta.v1.ObjectMetaArgs(
        name=f"{app_name}-hpa",
        namespace=namespace,
        labels=labels,
    ),
    spec=k8s.autoscaling.v2.HorizontalPodAutoscalerSpecArgs(
        scale_target_ref=k8s.autoscaling.v2.CrossVersionObjectReferenceArgs(
            api_version="apps/v1",
            kind="Deployment",
            name=app_name,
        ),
        min_replicas=min_replicas,
        max_replicas=max_replicas,
        metrics=[
            k8s.autoscaling.v2.MetricSpecArgs(
                type="Resource",
                resource=k8s.autoscaling.v2.ResourceMetricSourceArgs(
                    name="cpu",
                    target=k8s.autoscaling.v2.MetricTargetArgs(
                        type="Utilization",
                        average_utilization=70,
                    ),
                ),
            ),
            k8s.autoscaling.v2.MetricSpecArgs(
                type="Resource",
                resource=k8s.autoscaling.v2.ResourceMetricSourceArgs(
                    name="memory",
                    target=k8s.autoscaling.v2.MetricTargetArgs(
                        type="Utilization",
                        average_utilization=80,
                    ),
                ),
            ),
        ],
    ),
)

# Ingress
ingress = k8s.networking.v1.Ingress(
    app_name,
    metadata=k8s.meta.v1.ObjectMetaArgs(
        name=app_name,
        namespace=namespace,
        labels=labels,
        annotations={
            "alb.ingress.kubernetes.io/scheme": "internet-facing",
            "alb.ingress.kubernetes.io/target-type": "ip",
            "alb.ingress.kubernetes.io/healthcheck-path": "/health",
        },
    ),
    spec=k8s.networking.v1.IngressSpecArgs(
        ingress_class_name="alb",
        rules=[
            k8s.networking.v1.IngressRuleArgs(
                http=k8s.networking.v1.HTTPIngressRuleValueArgs(
                    paths=[
                        k8s.networking.v1.HTTPIngressPathArgs(
                            path="/",
                            path_type="Prefix",
                            backend=k8s.networking.v1.IngressBackendArgs(
                                service=k8s.networking.v1.IngressServiceBackendArgs(
                                    name=app_name,
                                    port=k8s.networking.v1.ServiceBackendPortArgs(
                                        number=80,
                                    ),
                                ),
                            ),
                        )
                    ],
                ),
            )
        ],
    ),
)

# Exports
pulumi.export("deployment_name", deployment.metadata["name"])
pulumi.export("service_name", service.metadata["name"])
pulumi.export("hpa_name", hpa.metadata["name"])
pulumi.export("ingress_name", ingress.metadata["name"])
pulumi.export("replicas", replicas)
```

**`applications/day-service/Pulumi.yaml`:**
```yaml
name: day-service-app
runtime: python
description: Day service Kubernetes application resources

config:
  namespace:
    default: production
  image_tag:
    default: latest
  replicas:
    default: 3
  min_replicas:
    default: 2
  max_replicas:
    default: 10
```

**`applications/day-service/Pulumi.production.yaml`:**
```yaml
config:
  day-service-app:namespace: production
  day-service-app:image_tag: v1.2.3
  day-service-app:replicas: 5
  day-service-app:min_replicas: 3
  day-service-app:max_replicas: 20
  day-service-app:log_level: INFO
  day-service-app:database_host: postgres.production.svc.cluster.local

  # Reference to infrastructure stack
  pulumi:kubeconfig:
    fn::stackReference:
      name: organization/infrastructure/production
      output: kubeconfig
```

### Deployment Workflow

```bash
# 1. Deploy infrastructure (if not already done)
cd infrastructure/pulumi
pulumi stack select production-cluster
pulumi up

# 2. Deploy application
cd ../../applications/day-service
pulumi stack select production
pulumi preview  # See what will change
pulumi up       # Deploy

# 3. Update application (e.g., new image)
pulumi config set image_tag v1.2.4
pulumi up       # Rolling update

# 4. Scale application
pulumi config set replicas 10
pulumi up       # Scale to 10 replicas
```

### Benefits of Separate Pulumi Programs

✅ **Type safety** - Catch errors at development time
✅ **Code reuse** - Functions, classes, modules
✅ **Testing** - Unit test your infrastructure
✅ **Refactoring** - IDE support for renaming, finding references
✅ **Abstraction** - Hide complexity behind functions
✅ **Same tool** - Teams already know Pulumi

### Example: Reusable Components

```python
# shared/microservice.py
"""Reusable microservice component"""

import pulumi
import pulumi_kubernetes as k8s
from typing import Dict, Optional

class MicroserviceArgs:
    def __init__(
        self,
        name: str,
        namespace: str,
        image: str,
        port: int,
        replicas: int = 3,
        env_vars: Optional[Dict[str, str]] = None,
        min_replicas: int = 2,
        max_replicas: int = 10,
    ):
        self.name = name
        self.namespace = namespace
        self.image = image
        self.port = port
        self.replicas = replicas
        self.env_vars = env_vars or {}
        self.min_replicas = min_replicas
        self.max_replicas = max_replicas

class Microservice(pulumi.ComponentResource):
    """Complete microservice with Deployment, Service, HPA, Ingress"""

    def __init__(self, name: str, args: MicroserviceArgs, opts=None):
        super().__init__("custom:app:Microservice", name, {}, opts)

        labels = {"app": args.name}

        # ConfigMap
        self.config_map = k8s.core.v1.ConfigMap(
            f"{args.name}-config",
            metadata={"name": f"{args.name}-config", "namespace": args.namespace},
            data=args.env_vars,
            opts=pulumi.ResourceOptions(parent=self),
        )

        # Deployment
        self.deployment = k8s.apps.v1.Deployment(
            args.name,
            metadata={"name": args.name, "namespace": args.namespace},
            spec={
                "replicas": args.replicas,
                "selector": {"matchLabels": labels},
                "template": {
                    "metadata": {"labels": labels},
                    "spec": {
                        "containers": [{
                            "name": args.name,
                            "image": args.image,
                            "ports": [{"containerPort": args.port}],
                            "envFrom": [{
                                "configMapRef": {"name": self.config_map.metadata["name"]}
                            }],
                        }],
                    },
                },
            },
            opts=pulumi.ResourceOptions(parent=self),
        )

        # Service
        self.service = k8s.core.v1.Service(
            args.name,
            metadata={"name": args.name, "namespace": args.namespace},
            spec={
                "selector": labels,
                "ports": [{"port": 80, "targetPort": args.port}],
            },
            opts=pulumi.ResourceOptions(parent=self),
        )

        # HPA
        self.hpa = k8s.autoscaling.v2.HorizontalPodAutoscaler(
            f"{args.name}-hpa",
            metadata={"name": f"{args.name}-hpa", "namespace": args.namespace},
            spec={
                "scaleTargetRef": {
                    "apiVersion": "apps/v1",
                    "kind": "Deployment",
                    "name": args.name,
                },
                "minReplicas": args.min_replicas,
                "maxReplicas": args.max_replicas,
                "metrics": [{
                    "type": "Resource",
                    "resource": {
                        "name": "cpu",
                        "target": {"type": "Utilization", "averageUtilization": 70},
                    },
                }],
            },
            opts=pulumi.ResourceOptions(parent=self),
        )

        self.register_outputs({})

# Usage in __main__.py
from shared.microservice import Microservice, MicroserviceArgs

day_service = Microservice(
    "day-service",
    MicroserviceArgs(
        name="day-service",
        namespace="production",
        image="your-registry/day:v1.2.3",
        port=8080,
        replicas=5,
        env_vars={
            "LOG_LEVEL": "INFO",
            "DATABASE_URL": "postgres://...",
        },
        min_replicas=3,
        max_replicas=20,
    ),
)
```

## Option 2: CDK8s (Kubernetes CDK)

CDK8s generates Kubernetes YAML from code, then you apply it with kubectl or GitOps.

### Installation
```bash
npm install -g cdk8s-cli
cdk8s init python-app
```

### Example: Day Service with CDK8s

**`day-service/main.py`:**
```python
#!/usr/bin/env python
from constructs import Construct
from cdk8s import App, Chart
from imports import k8s

class DayServiceChart(Chart):
    def __init__(self, scope: Construct, id: str):
        super().__init__(scope, id)

        label = {"app": "day-service"}

        # ConfigMap
        k8s.KubeConfigMap(
            self, "config",
            metadata=k8s.ObjectMeta(name="day-config"),
            data={
                "LOG_LEVEL": "INFO",
                "DATABASE_URL": "postgres://...",
            },
        )

        # Deployment
        k8s.KubeDeployment(
            self, "deployment",
            metadata=k8s.ObjectMeta(name="day-service"),
            spec=k8s.DeploymentSpec(
                replicas=3,
                selector=k8s.LabelSelector(match_labels=label),
                template=k8s.PodTemplateSpec(
                    metadata=k8s.ObjectMeta(labels=label),
                    spec=k8s.PodSpec(
                        containers=[
                            k8s.Container(
                                name="day",
                                image="day-service:v1.2.3",
                                ports=[k8s.ContainerPort(container_port=8080)],
                                env_from=[
                                    k8s.EnvFromSource(
                                        config_map_ref=k8s.ConfigMapEnvSource(
                                            name="day-config"
                                        )
                                    )
                                ],
                            )
                        ],
                    ),
                ),
            ),
        )

        # Service
        k8s.KubeService(
            self, "service",
            metadata=k8s.ObjectMeta(name="day-service"),
            spec=k8s.ServiceSpec(
                type="ClusterIP",
                selector=label,
                ports=[k8s.ServicePort(port=80, target_port=k8s.IntOrString.from_number(8080))],
            ),
        )

        # HPA
        k8s.KubeHorizontalPodAutoscalerV2(
            self, "hpa",
            metadata=k8s.ObjectMeta(name="day-hpa"),
            spec=k8s.HorizontalPodAutoscalerSpec(
                scale_target_ref=k8s.CrossVersionObjectReference(
                    api_version="apps/v1",
                    kind="Deployment",
                    name="day-service",
                ),
                min_replicas=2,
                max_replicas=10,
                metrics=[
                    k8s.MetricSpec(
                        type="Resource",
                        resource=k8s.ResourceMetricSource(
                            name="cpu",
                            target=k8s.MetricTarget(
                                type="Utilization",
                                average_utilization=70,
                            ),
                        ),
                    )
                ],
            ),
        )

app = App()
DayServiceChart(app, "day-service")
app.synth()
```

### Workflow
```bash
# Generate YAML
cdk8s synth

# Review generated YAML
cat dist/day-service.k8s.yaml

# Apply with kubectl
kubectl apply -f dist/day-service.k8s.yaml

# Or commit to Git for ArgoCD to pick up
git add dist/day-service.k8s.yaml
git commit -m "Update day service to v1.2.3"
git push
```

### Benefits of CDK8s

✅ **Kubernetes-native** - Generates standard YAML
✅ **GitOps friendly** - Commit generated YAML to Git
✅ **No runtime dependencies** - Just kubectl needed
✅ **Multi-language** - TypeScript, Python, Java, Go

## Option 3: Hybrid - Helm with Code-Generated Values

Generate Helm `values.yaml` from code, then use Helm for deployment.

**`generate_values.py`:**
```python
#!/usr/bin/env python3
import yaml
import sys

def generate_values(environment: str, version: str):
    """Generate Helm values from code"""

    # Logic in code, not YAML
    if environment == "production":
        replicas = 5
        min_replicas = 3
        max_replicas = 20
        cpu_limit = "1000m"
        memory_limit = "1Gi"
    elif environment == "staging":
        replicas = 2
        min_replicas = 1
        max_replicas = 5
        cpu_limit = "500m"
        memory_limit = "512Mi"
    else:  # dev
        replicas = 1
        min_replicas = 1
        max_replicas = 2
        cpu_limit = "200m"
        memory_limit = "256Mi"

    values = {
        "replicaCount": replicas,
        "image": {
            "repository": "your-registry/day-service",
            "tag": version,
            "pullPolicy": "IfNotPresent",
        },
        "autoscaling": {
            "enabled": True,
            "minReplicas": min_replicas,
            "maxReplicas": max_replicas,
            "targetCPUUtilizationPercentage": 70,
        },
        "resources": {
            "limits": {
                "cpu": cpu_limit,
                "memory": memory_limit,
            },
            "requests": {
                "cpu": "100m",
                "memory": "128Mi",
            },
        },
        "configMap": {
            "LOG_LEVEL": "INFO" if environment == "production" else "DEBUG",
            "FEATURE_NEW_UI": "true",
        },
    }

    return values

if __name__ == "__main__":
    env = sys.argv[1] if len(sys.argv) > 1 else "dev"
    version = sys.argv[2] if len(sys.argv) > 2 else "latest"

    values = generate_values(env, version)
    print(yaml.dump(values, default_flow_style=False))
```

**Workflow:**
```bash
# Generate values
python generate_values.py production v1.2.3 > values-production.yaml

# Deploy with Helm
helm upgrade --install day-service ./charts/day-service \
  -f values-production.yaml \
  --namespace production
```

## Option 4: Client Libraries (For Advanced Use Cases)

Use Kubernetes client libraries directly (e.g., for operators).

**`deploy.py` (using Python client):**
```python
from kubernetes import client, config
from kubernetes.client.rest import ApiException

# Load kubeconfig
config.load_kube_config()

apps_v1 = client.AppsV1Api()
core_v1 = client.CoreV1Api()
autoscaling_v2 = client.AutoscalingV2Api()

namespace = "production"

# Create ConfigMap
config_map = client.V1ConfigMap(
    metadata=client.V1ObjectMeta(name="day-config"),
    data={
        "LOG_LEVEL": "INFO",
        "DATABASE_URL": "postgres://...",
    },
)

try:
    core_v1.create_namespaced_config_map(namespace, config_map)
    print("ConfigMap created")
except ApiException as e:
    if e.status == 409:
        core_v1.patch_namespaced_config_map("day-config", namespace, config_map)
        print("ConfigMap updated")

# Create Deployment
deployment = client.V1Deployment(
    metadata=client.V1ObjectMeta(name="day-service"),
    spec=client.V1DeploymentSpec(
        replicas=3,
        selector=client.V1LabelSelector(match_labels={"app": "day"}),
        template=client.V1PodTemplateSpec(
            metadata=client.V1ObjectMeta(labels={"app": "day"}),
            spec=client.V1PodSpec(
                containers=[
                    client.V1Container(
                        name="day",
                        image="day-service:v1.2.3",
                        ports=[client.V1ContainerPort(container_port=8080)],
                        env_from=[
                            client.V1EnvFromSource(
                                config_map_ref=client.V1ConfigMapEnvSource(
                                    name="day-config"
                                )
                            )
                        ],
                    )
                ],
            ),
        ),
    ),
)

try:
    apps_v1.create_namespaced_deployment(namespace, deployment)
    print("Deployment created")
except ApiException as e:
    if e.status == 409:
        apps_v1.patch_namespaced_deployment("day-service", namespace, deployment)
        print("Deployment updated")
```

**When to use:**
- Custom Kubernetes operators
- Dynamic resource generation
- Complex orchestration logic
- Integration with external systems

## Comparison Table

| Approach | Language | Learning Curve | K8s Native | State Management | GitOps Friendly |
|----------|----------|---------------|------------|------------------|-----------------|
| **Pulumi (Separate)** | Python/TS/Go | Medium | ✅ | Pulumi State | ✅ (via CI/CD) |
| **CDK8s** | Python/TS/Go | Low | ✅✅ | Git (YAML) | ✅✅ |
| **Helm + Code** | Any + YAML | Low | ✅✅ | Git (values) | ✅✅ |
| **Client Libraries** | Python/Go/Java | High | ✅ | None/Custom | ❌ |
| **YAML** | N/A | Very Low | ✅✅ | Git | ✅✅ |

## Recommended Approach for Your Use Case

Based on your existing setup with Pulumi for infrastructure:

### **Option 1: Separate Pulumi Programs** ✅

**Project Structure:**
```
k8s-exploration/
├── foundation/
│   └── pulumi/              # Infrastructure (existing)
│       └── __main__.py      # EKS, VPC, Node Groups
│
└── applications/
    ├── day-service/
    │   ├── pulumi/          # Day app resources (NEW)
    │   │   ├── __main__.py  # Deployment, Service, HPA
    │   │   ├── Pulumi.yaml
    │   │   └── Pulumi.production.yaml
    │   └── src/             # Application code
    │
    └── dusk-service/
        ├── pulumi/          # Dusk app resources (NEW)
        └── src/
```

**Why this works:**
- ✅ Same tooling (team already knows Pulumi)
- ✅ Type-safe Python/TypeScript
- ✅ Separate stacks = separate lifecycles
- ✅ Can reference infrastructure outputs
- ✅ Preview changes before deployment
- ✅ Integrates with your existing CI/CD

### CI/CD Integration

**`.github/workflows/deploy-day-app.yml`:**
```yaml
name: Deploy Day Service Application

on:
  push:
    branches: [main]
    paths:
      - 'applications/day-service/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Setup Pulumi
        uses: pulumi/actions@v4

      - name: Deploy Application
        run: |
          cd applications/day-service/pulumi
          pulumi stack select production
          pulumi up --yes
        env:
          PULUMI_ACCESS_TOKEN: ${{ secrets.PULUMI_ACCESS_TOKEN }}
```

## Next Steps

1. **Choose your approach** (I recommend separate Pulumi programs)
2. **Create application directory structure**
3. **Write first application as code**
4. **Set up separate CI/CD pipeline**
5. **Document workflow for team**

Would you like me to create a working example of the separate Pulumi program for your Day service?
