# From Learning to Production

This project uses simplified patterns optimized for **learning**. This guide explains how production systems differ and how to migrate your knowledge.

---

## What This Project Taught You

Congratulations! By working through this project, you've learned:

✅ **Kubernetes Fundamentals**
- Pods, Deployments, ReplicaSets
- Services (ClusterIP, LoadBalancer)
- Ingress for external access
- ConfigMaps for configuration
- HorizontalPodAutoscaler for scaling
- Health checks (readiness, liveness)

✅ **AWS EKS**
- Managed Kubernetes control plane
- Worker node groups (EC2 and spot instances)
- VPC networking for EKS
- IAM integration (IRSA)
- AWS Load Balancer Controller

✅ **Infrastructure as Code**
- Pulumi for managing infrastructure as code
- Two-tier architecture (infrastructure vs application)
- Stack references for cross-stack communication
- State management

✅ **CI/CD**
- GitHub Actions workflows
- Automated image builds
- Container registry (ECR)
- Image tagging strategies

✅ **DevOps Practices**
- Namespaces for environment separation
- Rolling updates for zero-downtime deployments
- Auto-scaling based on metrics
- Monitoring and logging

---

## Learning Patterns vs Production Patterns

### 1. Configuration Approaches and CD Strategies

#### Learning (This Project)

This project demonstrates **two configuration approaches** (YAML and IaC) with different CD strategies:

| Service | Cluster | Configuration Approach | CD Strategy | Why This Approach |
|---------|---------|------------------------|-------------|-------------------|
| **Dawn** | Trantor | YAML (kubectl) | GitHub Actions (push-based) | Learn Kubernetes fundamentals hands-on |
| **Day** | Trantor | IaC (Pulumi) | GitHub Actions (push-based) | Understand application-as-code |
| **Dusk** | Terminus | TBD | TBD | Explore deployment strategies on Pulumi infrastructure |

**Why this progression:**
- **Pedagogical** - Each approach builds on the previous
- **Realistic** - Shows two ways to configure resources and different CD strategies
- **Comparative** - Easy to see trade-offs between YAML vs IaC and push-based vs pull-based CD
- **Practical** - All patterns are used in production systems

### 2. Cluster Architecture

#### Learning (This Project)

```
Trantor cluster (manually provisioned)
├── dawn-service (dawn-ns, dawn-rc-ns) - kubectl (via GitHub Actions)
└── day-service (day-ns, day-rc-ns) - Pulumi IaC (via GitHub Actions)

Terminus cluster (Pulumi-managed)
└── dusk-service (dusk-ns, dusk-rc-ns) - TBD deployment approach
```

**Why we use this decoupled architecture:**
- **Demonstrates real-world patterns** - Multiple services sharing a cluster
- **Cost-effective** - 2 clusters instead of 3 (~$147/month vs $220/month)
- **Learn namespace isolation** - Services isolated by namespaces, not clusters
- **Two provisioning methods** - Manual (Trantor) vs IaC (Terminus)
- **Two configuration approaches** - YAML (kubectl) and Pulumi IaC
- **Exploring CD strategies** - Currently using push-based (GitHub Actions), exploring options
- **Safe to experiment** - Can still delete entire cluster if needed

**Cost:** ~$147/month (2 clusters × $0.10/hour control plane)

#### Production

```
shared-prod-cluster
├── dawn-ns (namespace)
├── day-ns (namespace)
└── dusk-ns (namespace)

OR multiple clusters for different purposes:
prod-apps-cluster
├── dawn-ns
├── day-ns
└── dusk-ns

prod-data-cluster
├── postgres-ns
└── redis-ns
```

**Why production uses this:**
- **Cost-effective** - One control plane ($73/month) instead of three ($220/month)
- **Better resource utilization** - Share node capacity across services
- **Centralized management** - One place to manage policies, monitoring
- **Easier upgrades** - Upgrade cluster once, all services benefit

**When to use multiple clusters in production:**
- **Compliance** - Different security/regulatory requirements
- **Blast radius** - Isolate critical vs non-critical workloads
- **Multi-region** - Cluster per region for low latency
- **Multi-tenant** - Separate clusters for different customers

#### Migration Path

```bash
# You already know namespaces from this project!
# Just deploy multiple services to one cluster:

# Create namespaces
kubectl create namespace dawn
kubectl create namespace day
kubectl create namespace dusk

# Deploy services to different namespaces
kubectl apply -f dawn-deployment.yaml -n dawn
kubectl apply -f day-deployment.yaml -n day
kubectl apply -f dusk-deployment.yaml -n dusk

# Services still isolated by namespace
# But share the same cluster infrastructure
```

---

### 2. Image Tagging

#### Learning (This Project)

```yaml
# Uses mutable tags
image: 123456789.dkr.ecr.us-east-1.amazonaws.com/dawn:latest
image: 123456789.dkr.ecr.us-east-1.amazonaws.com/dawn:rc
```

**Why we do this:**
- **Simple to understand** - "latest" is self-explanatory
- **Easy deployment flow** - Push code → Build latest → Deploy latest
- **Matches tutorials** - Most getting-started guides use :latest

**Problem:**
- Can't easily rollback to specific version
- Don't know which code is deployed
- Cache issues (Kubernetes might not pull updated :latest)

#### Production

```yaml
# Uses immutable tags (git SHA or semantic version)
image: 123456789.dkr.ecr.us-east-1.amazonaws.com/dawn:sha-a1b2c3d
image: 123456789.dkr.ecr.us-east-1.amazonaws.com/dawn:v1.2.3
```

**Why production uses this:**
- **Guaranteed consistency** - SHA never changes
- **Easy rollback** - Just deploy previous SHA
- **Clear deployment history** - Know exactly which code is running
- **Audit trail** - Can trace deployments to commits

#### Migration Path

**Your GitHub Actions workflows already create SHA tags!** Just use them:

```bash
# Get the current commit SHA
SHA=$(git rev-parse --short HEAD)

# Deploy with specific SHA
kubectl set image deployment/dawn \
  dawn=123456789.dkr.ecr.us-east-1.amazonaws.com/dawn:sha-$SHA \
  -n dawn-ns

# Or update Pulumi config
pulumi config set image_tag sha-$SHA
pulumi up
```

**Semantic versioning workflow:**

```bash
# Tag a release
git tag v1.2.3
git push --tags

# GitHub Actions builds and tags: dawn:v1.2.3

# Deploy
kubectl set image deployment/dawn \
  dawn=123456789.dkr.ecr.us-east-1.amazonaws.com/dawn:v1.2.3 \
  -n dawn-ns
```

---

### 3. Environment Terminology

#### Learning (This Project)

```
dawn-ns    (production tier)
dawn-rc-ns (RC tier - "Release Candidate")
```

**Why we use "RC":**
- Simple two-tier setup
- RC → Prod promotion is clear

#### Production

```
dawn-dev     (development)
dawn-staging (staging / pre-production)
dawn-prod    (production)

OR:
dawn-canary  (canary deployment - 5% of traffic)
dawn-prod    (production - 95% of traffic)
```

**Industry standard terms:**
- **Development/Dev** - Active development, unstable
- **Staging/Pre-prod** - Production-like environment for final testing
- **Production/Prod** - Live environment serving users
- **Canary** - Small % of traffic to test new version

#### Migration Path

Just rename namespaces to match industry terms:

```bash
# Create standard namespaces
kubectl create namespace dawn-dev
kubectl create namespace dawn-staging
kubectl create namespace dawn-prod

# Deploy to appropriate environment based on branch/tag
```

---

### 4. Deployment Strategy

#### Learning (This Project)

```yaml
# Rolling update (default)
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
```

**What you learned:**
- Zero-downtime deployments
- Gradual rollout of new versions
- Automatic rollback on health check failure

#### Production Adds

**Blue/Green Deployment:**
```yaml
# Deploy to "green" environment
# Test green thoroughly
# Switch traffic from "blue" to "green"
# Keep blue around for instant rollback
```

**Tools:** ArgoCD, Flagger

**Canary Deployment:**
```yaml
# Deploy new version to canary (5% traffic)
# Monitor metrics (error rate, latency)
# Gradually increase canary traffic: 5% → 25% → 50% → 100%
# Automatic rollback if metrics degrade
```

**Tools:** Flagger, Argo Rollouts

**Feature Flags:**
```python
if feature_flags.is_enabled("new_checkout_flow"):
    return new_checkout()
else:
    return old_checkout()
```

**Tools:** LaunchDarkly, Unleash, custom solution

#### Migration Path

1. **Start with what you have** - Rolling updates work for most cases!
2. **Add canary for critical services** - Use Flagger with your existing Ingress
3. **Add feature flags** - Decouple deployment from feature release
4. **Consider blue/green for large changes** - Database migrations, API changes

---

### 5. Configuration Management

#### Learning (This Project)

```yaml
# ConfigMaps for all configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: dawn-config
data:
  LOG_LEVEL: "INFO"
  DATABASE_URL: "postgres://..."  # ❌ Sensitive data in ConfigMap!
```

**What you learned:**
- Separate config from code
- Environment variables from ConfigMaps
- Config updates without rebuilding images

#### Production

```yaml
# ConfigMaps for non-sensitive data ONLY
apiVersion: v1
kind: ConfigMap
metadata:
  name: dawn-config
data:
  LOG_LEVEL: "INFO"
  CACHE_TTL: "300"

---
# Kubernetes Secrets for sensitive data
apiVersion: v1
kind: Secret
type: Opaque
stringData:
  DATABASE_PASSWORD: "supersecret"  # Base64 encoded

---
# External Secrets Operator (BEST)
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: dawn-secrets
spec:
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: dawn-secrets
  data:
  - secretKey: DATABASE_PASSWORD
    remoteRef:
      key: prod/dawn/db-password
```

**Why External Secrets:**
- Secrets stored in AWS Secrets Manager (encrypted, rotated, audited)
- Not committed to Git
- Centralized secret management
- Automatic rotation support

#### Migration Path

1. **Move secrets from ConfigMaps to Secrets**
   ```bash
   kubectl create secret generic db-creds \
     --from-literal=password=supersecret \
     -n dawn-ns
   ```

2. **Update deployment to use Secrets**
   ```yaml
   env:
   - name: DB_PASSWORD
     valueFrom:
       secretKeyRef:
         name: db-creds
         key: password
   ```

3. **Install External Secrets Operator**
   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm install external-secrets external-secrets/external-secrets -n external-secrets-system --create-namespace
   ```

4. **Migrate to AWS Secrets Manager**

---

## What's Missing (Intentionally)

This project focuses on core concepts. Production systems typically add:

### Security

**Pod Security Standards:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

**Network Policies:**
```yaml
# Default deny all traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

**RBAC (Role-Based Access Control):**
```yaml
# Don't use default ServiceAccount
# Create specific roles with minimal permissions
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
```

### Observability

**Centralized Logging:**
- FluentBit → CloudWatch Logs
- FluentBit → Elasticsearch
- Structured JSON logs

**Metrics:**
- Prometheus for metrics collection
- Grafana for visualization
- CloudWatch Container Insights
- Custom application metrics

**Distributed Tracing:**
- AWS X-Ray
- Jaeger
- OpenTelemetry

**Alerting:**
- Prometheus Alertmanager
- CloudWatch Alarms
- PagerDuty integration

### Reliability

**Resource Quotas and Limits:**
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: prod-quota
  namespace: production
spec:
  hard:
    requests.cpu: "100"
    requests.memory: 200Gi
    limits.cpu: "200"
    limits.memory: 400Gi
```

**Pod Disruption Budgets:**
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: dawn-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: dawn
```

**Multi-AZ Distribution:**
```yaml
spec:
  topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
```

**Disaster Recovery:**
- Velero for backup and restore
- Multi-region deployments
- RTO/RPO planning

### CI/CD Enhancements

**Image Scanning:**
```yaml
# In GitHub Actions
- name: Scan image
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ env.IMAGE }}
    severity: 'CRITICAL,HIGH'
```

**Image Signing:**
```bash
# Sign images with Cosign
cosign sign $IMAGE
```

**SBOM Generation:**
```bash
# Generate Software Bill of Materials
syft $IMAGE -o spdx > sbom.spdx
```

**Automated Testing:**
- Unit tests before build
- Integration tests before deploy
- Smoke tests after deploy
- Performance tests in staging

---

## Recommended Learning Path

### 1. Deepen Kubernetes Knowledge

**Read:**
- [AWS EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [Kubernetes in Production](https://kubernetes.io/docs/setup/production-environment/)

**Practice:**
- Deploy multiple services to one cluster
- Implement NetworkPolicies
- Set up ResourceQuotas

### 2. Add Security

**Start with:**
1. Pod Security Standards (easiest, built-in)
2. Move secrets from ConfigMaps to Secrets
3. Implement basic RBAC

**Then add:**
4. Network Policies
5. External Secrets Operator
6. Image scanning in CI/CD

### 3. Improve Observability

**Start with:**
1. CloudWatch Container Insights (AWS-native)
2. Structured logging in applications
3. Basic CloudWatch dashboards

**Then add:**
4. Prometheus + Grafana
5. Distributed tracing
6. Alerting and on-call

### 4. Advanced Deployment Strategies

**Start with:**
1. Keep rolling updates (they work!)
2. Add automated rollback on health check failure

**Then add:**
3. Canary deployments with Flagger
4. Feature flags for gradual rollout
5. Blue/Green for major changes

### 5. Explore GitOps

**Instead of `kubectl apply` or `pulumi up`, use:**
- **ArgoCD** - Syncs cluster state with Git
- **Flux** - Similar to ArgoCD, more Git-native

**Benefits:**
- Git as single source of truth
- Automatic deployment on Git changes
- Easy rollback (just revert Git commit)
- Full audit trail

---

## Production Deployment Checklist

Before going to production, ensure:

**Security:**
- [ ] Pod Security Standards enforced
- [ ] Network Policies configured
- [ ] RBAC configured (no default ServiceAccount usage)
- [ ] Secrets externalized (AWS Secrets Manager, not ConfigMaps)
- [ ] Images scanned for vulnerabilities
- [ ] Images signed and verified

**Reliability:**
- [ ] Resource requests and limits set
- [ ] Health checks configured (readiness, liveness, startup)
- [ ] HPA configured for auto-scaling
- [ ] PDB configured for high availability
- [ ] Multi-AZ node distribution
- [ ] Backup strategy in place (Velero)

**Observability:**
- [ ] Centralized logging configured
- [ ] Metrics collection (Prometheus or CloudWatch)
- [ ] Dashboards created
- [ ] Alerts configured
- [ ] On-call rotation established

**CI/CD:**
- [ ] Automated testing in pipeline
- [ ] Image scanning in pipeline
- [ ] Immutable image tags (SHA or semver)
- [ ] Automated rollback on failure
- [ ] Deployment requires approval

**Infrastructure:**
- [ ] Infrastructure as Code (all resources)
- [ ] Multiple environments (dev, staging, prod)
- [ ] Disaster recovery plan
- [ ] RTO/RPO defined and tested

---

## Summary

**What you built:** A solid foundation for understanding Kubernetes, EKS, IaC, and CI/CD.

**What's different in production:** More focus on security, reliability, observability, and compliance.

**The good news:** The fundamentals you learned transfer directly! You just add layers of production-readiness on top.

**Next steps:** Pick one area (security, observability, or deployment strategies) and go deeper. Don't try to implement everything at once!

---

## Additional Resources

- [Recommended Resources](./recommended-resources.md) - Curated learning materials
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Kubernetes Production Patterns](https://k8spatterns.io/)
- [The Twelve-Factor App](https://12factor.net/)
