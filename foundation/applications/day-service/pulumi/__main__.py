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
- Infrastructure team manages: foundation/infrastructure/pulumi/ (EKS, VPC, nodes)
- Application team manages: foundation/applications/day-service/pulumi/ (this file)
"""

import pulumi
import pulumi_kubernetes as k8s

# ============================================================================
# Configuration
# ============================================================================

config = pulumi.Config()

# Application settings
app_name = "day-service"
namespace = config.get("namespace") or "production"
image_registry = config.get("image_registry") or "your-registry"
image_tag = config.get("image_tag") or "latest"

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

labels = {
    "app": app_name,
    "team": "day-team",
    "managed-by": "pulumi",
    "version": image_tag,
}

# ============================================================================
# ConfigMap - Application Configuration
# ============================================================================

config_map = k8s.core.v1.ConfigMap(
    f"{app_name}-config",
    metadata=k8s.meta.v1.ObjectMetaArgs(
        name=f"{app_name}-config",
        namespace=namespace,
        labels=labels,
    ),
    data={
        "LOG_LEVEL": log_level,
        "DATABASE_HOST": database_host,
        "CACHE_TTL": cache_ttl,
        "FEATURE_FLAG_NEW_UI": str(feature_new_ui).lower(),
        "SERVICE_NAME": app_name,
        "NAMESPACE": namespace,
    },
)

# ============================================================================
# Deployment - Application Pods
# ============================================================================

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
                        image=f"{image_registry}/{app_name}:{image_tag}",
                        ports=[
                            k8s.core.v1.ContainerPortArgs(
                                name="http",
                                container_port=8080,
                                protocol="TCP",
                            )
                        ],
                        # Inject ConfigMap as environment variables
                        env_from=[
                            k8s.core.v1.EnvFromSourceArgs(
                                config_map_ref=k8s.core.v1.ConfigMapEnvSourceArgs(
                                    name=config_map.metadata["name"],
                                )
                            )
                        ],
                        # Resource requests and limits
                        resources=k8s.core.v1.ResourceRequirementsArgs(
                            requests={
                                "cpu": cpu_request,
                                "memory": memory_request,
                            },
                            limits={
                                "cpu": cpu_limit,
                                "memory": memory_limit,
                            },
                        ),
                        # Liveness probe (is the container running?)
                        liveness_probe=k8s.core.v1.ProbeArgs(
                            http_get=k8s.core.v1.HTTPGetActionArgs(
                                path="/health",
                                port=8080,
                                scheme="HTTP",
                            ),
                            initial_delay_seconds=30,
                            period_seconds=10,
                            timeout_seconds=5,
                            failure_threshold=3,
                        ),
                        # Readiness probe (is the container ready to serve traffic?)
                        readiness_probe=k8s.core.v1.ProbeArgs(
                            http_get=k8s.core.v1.HTTPGetActionArgs(
                                path="/ready",
                                port=8080,
                                scheme="HTTP",
                            ),
                            initial_delay_seconds=5,
                            period_seconds=5,
                            timeout_seconds=3,
                            failure_threshold=3,
                        ),
                    )
                ],
                # Graceful shutdown
                termination_grace_period_seconds=30,
            ),
        ),
        # Rolling update strategy
        strategy=k8s.apps.v1.DeploymentStrategyArgs(
            type="RollingUpdate",
            rolling_update=k8s.apps.v1.RollingUpdateDeploymentArgs(
                max_unavailable=1,
                max_surge=1,
            ),
        ),
    ),
)

# ============================================================================
# Service - Internal Load Balancing
# ============================================================================

service = k8s.core.v1.Service(
    app_name,
    metadata=k8s.meta.v1.ObjectMetaArgs(
        name=app_name,
        namespace=namespace,
        labels=labels,
    ),
    spec=k8s.core.v1.ServiceSpecArgs(
        type="ClusterIP",  # Internal service
        selector={"app": app_name},  # Route to pods with this label
        ports=[
            k8s.core.v1.ServicePortArgs(
                name="http",
                port=80,  # Service port
                target_port=8080,  # Container port
                protocol="TCP",
            )
        ],
        session_affinity="None",
    ),
)

# ============================================================================
# HorizontalPodAutoscaler - Automatic Scaling
# ============================================================================

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
            # Scale based on CPU usage
            k8s.autoscaling.v2.MetricSpecArgs(
                type="Resource",
                resource=k8s.autoscaling.v2.ResourceMetricSourceArgs(
                    name="cpu",
                    target=k8s.autoscaling.v2.MetricTargetArgs(
                        type="Utilization",
                        average_utilization=cpu_target,
                    ),
                ),
            ),
            # Scale based on memory usage
            k8s.autoscaling.v2.MetricSpecArgs(
                type="Resource",
                resource=k8s.autoscaling.v2.ResourceMetricSourceArgs(
                    name="memory",
                    target=k8s.autoscaling.v2.MetricTargetArgs(
                        type="Utilization",
                        average_utilization=memory_target,
                    ),
                ),
            ),
        ],
        # Scaling behavior (optional - prevent thrashing)
        behavior=k8s.autoscaling.v2.HorizontalPodAutoscalerBehaviorArgs(
            scale_down=k8s.autoscaling.v2.HPAScalingRulesArgs(
                stabilization_window_seconds=300,  # Wait 5 min before scaling down
                policies=[
                    k8s.autoscaling.v2.HPAScalingPolicyArgs(
                        type="Percent",
                        value=50,  # Scale down max 50% of pods
                        period_seconds=60,
                    ),
                ],
            ),
        ),
    ),
)

# ============================================================================
# Ingress - External Access via ALB
# ============================================================================

ingress = k8s.networking.v1.Ingress(
    app_name,
    metadata=k8s.meta.v1.ObjectMetaArgs(
        name=app_name,
        namespace=namespace,
        labels=labels,
        annotations={
            # AWS ALB Controller annotations
            "alb.ingress.kubernetes.io/scheme": "internet-facing",
            "alb.ingress.kubernetes.io/target-type": "ip",
            "alb.ingress.kubernetes.io/healthcheck-path": "/health",
            "alb.ingress.kubernetes.io/healthcheck-interval-seconds": "15",
            "alb.ingress.kubernetes.io/healthcheck-timeout-seconds": "5",
            "alb.ingress.kubernetes.io/healthy-threshold-count": "2",
            "alb.ingress.kubernetes.io/unhealthy-threshold-count": "2",
            # Optional: SSL/TLS
            # "alb.ingress.kubernetes.io/certificate-arn": "arn:aws:acm:...",
            # "alb.ingress.kubernetes.io/listen-ports": '[{"HTTP": 80}, {"HTTPS": 443}]',
        },
    ),
    spec=k8s.networking.v1.IngressSpecArgs(
        ingress_class_name="alb",  # Use AWS ALB
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

# ============================================================================
# Exports - Useful outputs for reference
# ============================================================================

pulumi.export("deployment_name", deployment.metadata["name"])
pulumi.export("service_name", service.metadata["name"])
pulumi.export("hpa_name", hpa.metadata["name"])
pulumi.export("ingress_name", ingress.metadata["name"])
pulumi.export("namespace", namespace)
pulumi.export("replicas", replicas)
pulumi.export("image", f"{image_registry}/{app_name}:{image_tag}")

# Get the ALB hostname once the Ingress is created
pulumi.export("alb_hostname", ingress.status.apply(
    lambda status: status.load_balancer.ingress[0].hostname
    if status and status.load_balancer and status.load_balancer.ingress
    else "pending..."
))
