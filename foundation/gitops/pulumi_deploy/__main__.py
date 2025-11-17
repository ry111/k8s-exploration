"""
Day Service Application Resources

This Pulumi program manages the Kubernetes application resources for the Day service.
It is SEPARATE from the infrastructure Pulumi program that manages the EKS cluster.

Manages:
- Deployment
- Service (ClusterIP)
- ConfigMap
- HorizontalPodAutoscaler
- Ingress

Separation of Concerns:
- Infrastructure team manages: foundation/provisioning/pulumi/ (EKS, VPC, nodes)
- Application team manages: foundation/gitops/pulumi_deploy/ (this file)
"""

import pulumi
import pulumi_kubernetes as k8s

# ============================================================================
# Kubernetes Provider Setup - Get kubeconfig from infrastructure stack
# ============================================================================

config = pulumi.Config()

# Option 1: Use stack reference to get kubeconfig from infrastructure stack
# This is the recommended approach for production/CI-CD
use_stack_reference = config.get_bool("use_stack_reference")
if use_stack_reference is None:
    use_stack_reference = True  # Default to using stack reference

if use_stack_reference:
    # Get the infrastructure stack name from config
    infra_stack_name = config.get("infra_stack_name") or "ry111/foundation/day"

    # Create stack reference to infrastructure stack
    infra_stack = pulumi.StackReference(infra_stack_name)

    # Get kubeconfig output from infrastructure stack
    kubeconfig = infra_stack.require_output("kubeconfig")

    # Create explicit Kubernetes provider using the kubeconfig from infra stack
    k8s_provider = k8s.Provider(
        "k8s-provider",
        kubeconfig=kubeconfig,
    )

    # Use this provider for all resources
    provider_opts = pulumi.ResourceOptions(provider=k8s_provider)
else:
    # Option 2: Use default kubeconfig (local development)
    # Will use ~/.kube/config or KUBECONFIG environment variable
    provider_opts = None

# ============================================================================
# Configuration
# ============================================================================

# Base service name
service_name = "day"

# Namespace configuration
namespace = config.get("namespace") or "production"

# Determine tier based on namespace
tier = "rc" if "rc" in namespace else "production"

# Resource naming (matches manual deploy pattern)
# Production: day, day-service, day-ingress, day-config, day-hpa
# RC: day-rc, day-rc-service, day-rc-ingress, day-rc-config, day-rc-hpa
deployment_name = f"{service_name}-{tier}" if tier == "rc" else service_name
service_resource_name = f"{service_name}-{tier}-service" if tier == "rc" else f"{service_name}-service"
ingress_name = f"{service_name}-{tier}-ingress" if tier == "rc" else f"{service_name}-ingress"
configmap_name = f"{service_name}-{tier}-config" if tier == "rc" else f"{service_name}-config"
hpa_name = f"{service_name}-{tier}-hpa" if tier == "rc" else f"{service_name}-hpa"

# Ingress host configuration
ingress_host = f"{service_name}-{tier}.example.com" if tier == "rc" else f"{service_name}.example.com"

# Image configuration
image_registry = config.get("image_registry") or "your-registry"
image_tag = config.get("image_tag") or "latest"
image_name = config.get("image_name") or service_name  # ECR repository name

# Deployment settings
replicas = config.get_int("replicas") or 3

# Autoscaling settings
min_replicas = config.get_int("min_replicas") or 2
max_replicas = config.get_int("max_replicas") or 10
cpu_target = config.get_int("cpu_target") or 70
memory_target = config.get_int("memory_target") or 80

# Resource settings
cpu_request = config.get("cpu_request") or "100m"
memory_request = config.get("memory_request") or "128Mi"
cpu_limit = config.get("cpu_limit") or "500m"
memory_limit = config.get("memory_limit") or "512Mi"

# Application configuration (environment variables)
log_level = config.get("log_level") or "INFO"
database_host = config.get("database_host") or "postgres.production.svc.cluster.local"
cache_ttl = config.get("cache_ttl") or "300"
feature_new_ui = config.get_bool("feature_new_ui") or True

# ============================================================================
# Labels and Metadata
# ============================================================================

# Pod labels (include all labels for identification)
pod_labels = {
    "app": service_name,
    "tier": tier,
    "cluster": "trantor",
}

# Resource metadata labels (for deployments, services, etc.)
labels = {
    "app": service_name,
    "managed-by": "pulumi",
    "environment": namespace,
    "tier": tier,
    "cluster": "trantor",
}

# ============================================================================
# Namespace
# ============================================================================
# Create the namespace if it doesn't exist
# This allows the application stack to be self-contained

ns = k8s.core.v1.Namespace(
    f"{namespace}-namespace",
    metadata={
        "name": namespace,
        "labels": {
            "name": namespace,
            "managed-by": "pulumi",
            "app": service_name,
            "tier": tier,
            "cluster": "trantor",
            "environment": "production" if tier == "production" else "rc",
        },
    },
    opts=provider_opts,
)

# ============================================================================
# ConfigMap
# ============================================================================

config_map = k8s.core.v1.ConfigMap(
    f"{configmap_name}-configmap",
    metadata={
        "name": configmap_name,
        "namespace": namespace,
        "labels": labels,
    },
    data={
        "LOG_LEVEL": log_level,
        "DATABASE_HOST": database_host,
        "CACHE_TTL": cache_ttl,
        "FEATURE_NEW_UI": str(feature_new_ui).lower(),
    },
    opts=pulumi.ResourceOptions(
        provider=provider_opts.provider if provider_opts else None,
        depends_on=[ns],  # Wait for namespace to be created
    ),
)

# ============================================================================
# Deployment
# ============================================================================

# Deployment selector (matches manual deploy pattern)
# Production: only app label
# RC: app + tier labels
deployment_selector = {"app": service_name}
if tier == "rc":
    deployment_selector["tier"] = tier

deployment = k8s.apps.v1.Deployment(
    f"{deployment_name}-deployment",
    metadata={
        "name": deployment_name,
        "namespace": namespace,
        "labels": labels,
    },
    spec={
        # "replicas": replicas,  # Commented out to allow HPA to manage replicas
        "selector": {
            "match_labels": deployment_selector,
        },
        "template": {
            "metadata": {
                "labels": pod_labels,
            },
            "spec": {
                "containers": [{
                    "name": service_name,
                    "image": f"{image_registry}/{image_name}:{image_tag}",
                    "ports": [{
                        "container_port": 8001,  # Match Dockerfile EXPOSE port
                        "name": "http",
                    }],
                    "env_from": [{
                        "config_map_ref": {
                            "name": config_map.metadata["name"],
                        },
                    }],
                    "resources": {
                        "requests": {
                            "cpu": cpu_request,
                            "memory": memory_request,
                        },
                        "limits": {
                            "cpu": cpu_limit,
                            "memory": memory_limit,
                        },
                    },
                    "liveness_probe": {
                        "http_get": {
                            "path": "/health",
                            "port": 8001,  # Match service port
                        },
                        "initial_delay_seconds": 30,
                        "period_seconds": 10,
                    },
                    "readiness_probe": {
                        "http_get": {
                            "path": "/health",  # Use /health instead of /ready
                            "port": 8001,  # Match service port
                        },
                        "initial_delay_seconds": 5,
                        "period_seconds": 5,
                    },
                }],
            },
        },
    },
    opts=pulumi.ResourceOptions(
        provider=provider_opts.provider if provider_opts else None,
        depends_on=[ns],  # Wait for namespace to be created
    ),
)

# ============================================================================
# Service
# ============================================================================

# Service selector (matches manual deploy pattern and deployment selector)
# Production: only app label
# RC: app + tier labels
service_selector = {"app": service_name}
if tier == "rc":
    service_selector["tier"] = tier

service = k8s.core.v1.Service(
    f"{service_resource_name}-k8s-service",
    metadata={
        "name": service_resource_name,
        "namespace": namespace,
        "labels": labels,
    },
    spec={
        "type": "ClusterIP",
        "selector": service_selector,
        "ports": [{
            "port": 80,
            "target_port": 8001,  # Match container port
            "protocol": "TCP",
            "name": "http",
        }],
    },
    opts=pulumi.ResourceOptions(
        provider=provider_opts.provider if provider_opts else None,
        depends_on=[ns],  # Wait for namespace to be created
    ),
)

# ============================================================================
# HorizontalPodAutoscaler
# ============================================================================

hpa = k8s.autoscaling.v2.HorizontalPodAutoscaler(
    f"{hpa_name}-resource",
    metadata={
        "name": hpa_name,
        "namespace": namespace,
        "labels": labels,
    },
    spec={
        "scale_target_ref": {
            "api_version": "apps/v1",
            "kind": "Deployment",
            "name": deployment_name,
        },
        "min_replicas": min_replicas,
        "max_replicas": max_replicas,
        "metrics": [
            {
                "type": "Resource",
                "resource": {
                    "name": "cpu",
                    "target": {
                        "type": "Utilization",
                        "average_utilization": cpu_target,
                    },
                },
            },
            {
                "type": "Resource",
                "resource": {
                    "name": "memory",
                    "target": {
                        "type": "Utilization",
                        "average_utilization": memory_target,
                    },
                },
            },
        ],
    },
    opts=pulumi.ResourceOptions(
        provider=provider_opts.provider if provider_opts else None,
        depends_on=[ns],  # Wait for namespace to be created
    ),
)

# ============================================================================
# Ingress
# ============================================================================

ingress = k8s.networking.v1.Ingress(
    f"{ingress_name}-resource",
    metadata={
        "name": ingress_name,
        "namespace": namespace,
        "labels": labels,
        "annotations": {
            # AWS Load Balancer Controller annotations
            "kubernetes.io/ingress.class": "alb",
            "alb.ingress.kubernetes.io/group.name": "trantor-cluster",
            "alb.ingress.kubernetes.io/scheme": "internet-facing",
            "alb.ingress.kubernetes.io/target-type": "ip",
            "alb.ingress.kubernetes.io/healthcheck-path": "/health",
        },
    },
    spec={
        "rules": [{
            "host": ingress_host,  # CRITICAL: Add host for shared ALB routing
            "http": {
                "paths": [{
                    "path": "/",
                    "path_type": "Prefix",
                    "backend": {
                        "service": {
                            "name": service_resource_name,
                            "port": {
                                "number": 80,
                            },
                        },
                    },
                }],
            },
        }],
    },
    opts=pulumi.ResourceOptions(
        provider=provider_opts.provider if provider_opts else None,
        depends_on=[ns],  # Wait for namespace to be created
    ),
)

# ============================================================================
# Outputs
# ============================================================================

pulumi.export("deployment_name", deployment.metadata["name"])
pulumi.export("service_name", service.metadata["name"])
pulumi.export("hpa_name", hpa.metadata["name"])
pulumi.export("ingress_name", ingress.metadata["name"])
pulumi.export("configmap_name", config_map.metadata["name"])
pulumi.export("namespace", namespace)
pulumi.export("tier", tier)
pulumi.export("replicas", replicas)
pulumi.export("image", f"{image_registry}/{image_name}:{image_tag}")
pulumi.export("ingress_host", ingress_host)

# Export ALB hostname once ingress is created
pulumi.export("alb_hostname", ingress.status.apply(
    lambda status: status.load_balancer.ingress[0].hostname
    if status and status.load_balancer and status.load_balancer.ingress
    else "pending"
))

# Export which provider mode is being used
pulumi.export("using_stack_reference", use_stack_reference)
if use_stack_reference:
    pulumi.export("infra_stack_referenced", infra_stack_name)
