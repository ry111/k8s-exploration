# Namespace Management Strategy

## Decision: Application Stack Creates Namespaces

**Recommendation:** The **application Pulumi stack** should create its namespace, not the infrastructure stack.

## Why Application Stack?

### 1. **Namespace is Application-Scoped**
- Each application/service gets its own namespace
- Namespace is part of the application's resource boundary
- Tightly coupled to application lifecycle

### 2. **Enables Independent Deployments**
- Application team can deploy without infrastructure team involvement
- No cross-stack coordination needed for namespace creation
- Application stack is self-contained and portable

### 3. **Application Owns Its Isolation**
- Namespace provides security and resource isolation
- Application team can manage:
  - ResourceQuotas for the namespace
  - NetworkPolicies for the namespace
  - RBAC (RoleBindings) within the namespace
  - LimitRanges for the namespace

### 4. **Better Separation of Concerns**
| Layer | Responsibility | Example Resources |
|-------|----------------|-------------------|
| **Infrastructure** | Cluster-wide resources | EKS cluster, VPC, nodes, cluster-scoped RBAC |
| **Application** | Application resources | Namespace, Deployment, Service, ConfigMap |

## Implementation

In `foundation/gitops/day/pulumi/__main__.py.fixed`:

```python
# Create namespace as first resource
ns = k8s.core.v1.Namespace(
    f"{namespace}-namespace",
    metadata={
        "name": namespace,
        "labels": {
            "name": namespace,
            "managed-by": "pulumi",
            "app": app_name,
        },
    },
    opts=provider_opts,
)

# All other resources depend on namespace
deployment = k8s.apps.v1.Deployment(
    "app-deployment",
    metadata={"namespace": namespace, ...},
    opts=pulumi.ResourceOptions(
        provider=provider_opts.provider if provider_opts else None,
        depends_on=[ns],  # ← Wait for namespace creation
    ),
)
```

## Benefits

### ✅ **Self-Contained Stack**
```bash
# Deploy complete application (namespace + resources) in one command
cd foundation/gitops/day/pulumi
pulumi up

# Everything is created:
# 1. Namespace (dev or production)
# 2. ConfigMap
# 3. Deployment
# 4. Service
# 5. HPA
# 6. Ingress
```

### ✅ **Multi-Environment Support**
```yaml
# Pulumi.dev.yaml - creates "dev" namespace
day-service-app:namespace: dev

# Pulumi.production.yaml - creates "production" namespace
day-service-app:namespace: production
```

### ✅ **Resource Quotas (Optional)**
You can add namespace-level resource management:

```python
# Optional: Add ResourceQuota to namespace
quota = k8s.core.v1.ResourceQuota(
    f"{namespace}-quota",
    metadata={"namespace": namespace},
    spec={
        "hard": {
            "requests.cpu": "10",
            "requests.memory": "20Gi",
            "pods": "50",
        }
    },
    opts=pulumi.ResourceOptions(
        provider=provider_opts.provider if provider_opts else None,
        depends_on=[ns],
    ),
)
```

### ✅ **Network Policies (Optional)**
Control network traffic at namespace level:

```python
# Optional: Default deny ingress
network_policy = k8s.networking.v1.NetworkPolicy(
    f"{namespace}-default-deny",
    metadata={"namespace": namespace},
    spec={
        "pod_selector": {},
        "policy_types": ["Ingress"],
    },
    opts=pulumi.ResourceOptions(
        provider=provider_opts.provider if provider_opts else None,
        depends_on=[ns],
    ),
)
```

## Alternative: Infrastructure Stack Creates Namespaces

Some teams prefer infrastructure stack creates namespaces. This works if:

### When to Use Infrastructure Stack for Namespaces:

1. **Centralized Control**: Platform team controls all namespaces
2. **Pre-configured Policies**: All namespaces need same ResourceQuotas, NetworkPolicies, RBAC
3. **Multi-Tenancy**: Many teams share one cluster, platform team manages isolation

### Example Infrastructure Stack Approach:

```python
# foundation/infrastructure/pulumi/__main__.py
namespaces = ["dev", "staging", "production"]

for ns_name in namespaces:
    ns = k8s.core.v1.Namespace(
        f"{ns_name}-namespace",
        metadata={"name": ns_name},
        opts=pulumi.ResourceOptions(provider=k8s_provider),
    )

    # Apply organization-wide policies
    k8s.core.v1.ResourceQuota(
        f"{ns_name}-quota",
        metadata={"namespace": ns_name},
        spec={...},
        opts=pulumi.ResourceOptions(provider=k8s_provider, depends_on=[ns]),
    )
```

**Pros:**
- Consistent policies across all namespaces
- Centralized namespace management
- Can enforce organizational standards

**Cons:**
- Application stack must coordinate with infrastructure stack
- Less flexibility for application teams
- Infrastructure stack becomes more complex

## Recommended Approach for Your Setup

**Use application stack to create namespaces** because:

1. ✅ You have separate application stacks per service
2. ✅ Enables true application independence
3. ✅ Simpler architecture - no cross-stack namespace dependency
4. ✅ Application owns its complete resource boundary

## Common Namespace Patterns

### Pattern 1: Namespace Per Environment (Current)
```
dev/             ← One namespace for all dev services
production/      ← One namespace for all production services
```

**Config:**
```yaml
# Pulumi.dev.yaml
day-service-app:namespace: dev

# Pulumi.production.yaml
day-service-app:namespace: production
```

### Pattern 2: Namespace Per Service Per Environment
```
day-service-dev/
day-service-production/
dusk-service-dev/
dusk-service-production/
```

**Config:**
```python
# In __main__.py
namespace = config.get("namespace") or f"{app_name}-production"

# Pulumi.dev.yaml
day-service-app:namespace: day-service-dev

# Pulumi.production.yaml
day-service-app:namespace: day-service-production
```

### Pattern 3: Team-Based Namespaces
```
team-backend-dev/
team-backend-prod/
team-frontend-dev/
team-frontend-prod/
```

## Handling Namespace Conflicts

If multiple applications might try to create the same namespace:

### Option A: Use Pulumi's Protect Option
```python
ns = k8s.core.v1.Namespace(
    f"{namespace}-namespace",
    metadata={"name": namespace},
    opts=pulumi.ResourceOptions(
        provider=provider_opts.provider if provider_opts else None,
        protect=True,  # Prevent deletion
    ),
)
```

### Option B: Use `get` Instead of Create
```python
# Get existing namespace instead of creating
ns = k8s.core.v1.Namespace.get(
    f"{namespace}-namespace",
    id=namespace,  # Namespace name
    opts=pulumi.ResourceOptions(provider=provider_opts.provider if provider_opts else None),
)
```

### Option C: Conditional Creation
```python
create_namespace = config.get_bool("create_namespace")
if create_namespace is None:
    create_namespace = True  # Default to creating

if create_namespace:
    ns = k8s.core.v1.Namespace(...)
else:
    # Assume namespace exists
    ns = None

# For resources, use depends_on only if namespace was created
deployment_opts = pulumi.ResourceOptions(
    provider=provider_opts.provider if provider_opts else None,
    depends_on=[ns] if ns else [],
)
```

## Migration Path

If you later decide to move namespace management to infrastructure stack:

1. Export namespace name from infrastructure stack:
```python
# infrastructure/__main__.py
pulumi.export("app_namespace", "production")
```

2. Read it in application stack:
```python
# application/__main__.py
infra_stack = pulumi.StackReference("ry111/service-infrastructure/day")
namespace = infra_stack.require_output("app_namespace")

# Don't create namespace, just use the name
# (namespace created by infrastructure stack)
```

## Summary

**For your EKS + Pulumi setup:**

✅ **Recommended:** Application stack creates namespace
- Location: `foundation/gitops/day/pulumi/__main__.py`
- Creates: Namespace + all application resources
- Benefits: Self-contained, independent, flexible

**Config:**
```yaml
day-service-app:namespace: dev  # or production
```

**Code:**
```python
ns = k8s.core.v1.Namespace(
    f"{namespace}-namespace",
    metadata={"name": namespace},
    opts=provider_opts,
)

# All resources depend on namespace
deployment = k8s.apps.v1.Deployment(
    ...,
    opts=pulumi.ResourceOptions(depends_on=[ns], ...),
)
```

This approach gives you maximum flexibility and follows cloud-native best practices for application ownership.
