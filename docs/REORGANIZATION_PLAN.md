# Documentation Reorganization Plan

## Current State Analysis

### Existing Documentation (18 files)
1. **Quick Starts**: quickstart-dawn.md, quickstart-dawn-ci.md
2. **Fundamentals**: kubernetes-fundamentals.md, foundation-overview.md
3. **Pulumi/IaC**: pulumi-setup.md, deploy-day-cluster.md, pulumi-resource-strategy.md, application-as-code-guide.md
4. **CI/CD**: ci-setup.md, cicd-image-deployment.md
5. **Deep Dives**: deployment-hierarchy.md, configmap-relationships.md, rolling-update-mechanism.md, namespace-management-strategy.md
6. **Operations**: health-checks.md
7. **Troubleshooting**: stack-reference-fix.md, eks-github-actions-auth-fix.md
8. **Index**: README.md

### Problems Identified

#### 1. Lack of Cohesive Learning Flow
- No clear progression from beginner to advanced
- Docs created iteratively without overall structure
- Redundant content across multiple files
- Missing connections between concepts

#### 2. Architecture Anti-Patterns (for Production)
⚠️ **These are acceptable for learning, but need clear warnings:**

- **One cluster per service** - Production should use namespaces within clusters
- **`:latest` tag in deployments** - Should use immutable tags (git SHA)
- **"RC" terminology** - Industry uses "staging", "canary", or "pre-prod"
- **Shared state files** - Need better guidance on team collaboration

#### 3. Missing Critical Topics
- ❌ Pod Security Standards (PSS/PSP)
- ❌ Network Policies
- ❌ RBAC configuration
- ❌ Secrets management (using Kubernetes Secrets, not ConfigMaps)
- ❌ Resource Quotas and LimitRanges
- ❌ Image scanning and security
- ❌ Disaster recovery / backup strategies
- ❌ Multi-region considerations
- ❌ Service mesh introduction
- ❌ Observability (structured logging, metrics, tracing)

#### 4. Best Practice Gaps

**Image Management:**
```yaml
# ❌ CURRENT (anti-pattern for production)
image: dawn:latest

# ✅ SHOULD BE
image: 123456789.dkr.ecr.us-east-1.amazonaws.com/dawn:sha-a1b2c3d4
# With proper CI/CD tagging strategy
```

**Cluster Architecture:**
```
# ❌ CURRENT (learning pattern)
dawn-service → dawn-cluster
day-service → day-cluster
dusk-service → dusk-cluster

# ✅ PRODUCTION PATTERN
shared-cluster
  ├── dawn-ns (namespace)
  ├── day-ns (namespace)
  └── dusk-ns (namespace)
```

**Deployment Strategy:**
- Missing canary deployments
- Missing blue/green deployments
- No mention of progressive delivery
- No automated rollback strategies

---

## Proposed New Structure

### Learning Path Philosophy

**Progressive Complexity:**
1. **Learn** - Understand concepts
2. **Do** - Hands-on manual work
3. **Automate** - Infrastructure as Code
4. **Scale** - CI/CD and production practices
5. **Master** - Advanced patterns

### New Documentation Organization

```
docs/
├── README.md                          # Learning paths and navigation
│
├── learning-path/                     # Structured learning sequence
│   ├── 01-kubernetes-fundamentals.md  # RENAMED from kubernetes-fundamentals.md
│   ├── 02-eks-deep-dive.md           # NEW: EKS specifics, AWS integration
│   ├── 03-hands-on-first-deploy.md   # MERGED: quickstart-dawn.md + exploration
│   ├── 04-kubernetes-internals.md    # MERGED: deployment-hierarchy + configmap + rolling-updates
│   ├── 05-infrastructure-as-code.md  # MERGED: pulumi-setup + deploy-day-cluster
│   ├── 06-application-as-code.md     # ENHANCED: application-as-code-guide.md
│   ├── 07-cicd-automation.md         # MERGED: ci-setup + cicd-image-deployment + quickstart-dawn-ci
│   └── 08-production-ready.md        # NEW: Security, RBAC, monitoring, DR
│
├── concepts/                          # Deep dives into specific topics
│   ├── architecture-decisions.md     # Why this project uses certain patterns
│   ├── two-tier-pulumi.md           # RENAMED: pulumi-resource-strategy.md
│   ├── namespace-strategies.md       # ENHANCED: namespace-management-strategy.md
│   ├── image-lifecycle.md           # NEW: Building, scanning, signing, deploying
│   ├── deployment-strategies.md      # NEW: Rolling, blue/green, canary
│   └── observability.md             # NEW: Logs, metrics, traces
│
├── how-to/                           # Task-based guides
│   ├── setup-environment.md         # NEW: Tool installation and setup
│   ├── deploy-with-eksctl.md        # EXTRACTED from quickstart-dawn.md
│   ├── deploy-with-pulumi.md        # EXTRACTED from deploy-day-cluster.md
│   ├── setup-github-actions.md      # EXTRACTED from ci-setup.md
│   ├── manage-secrets.md            # NEW: Kubernetes Secrets, External Secrets Operator
│   ├── configure-autoscaling.md     # NEW: HPA, VPA, Cluster Autoscaler
│   ├── setup-monitoring.md          # NEW: Prometheus, Grafana
│   └── disaster-recovery.md         # NEW: Velero, backups
│
├── reference/                        # Reference material
│   ├── project-structure.md         # RENAMED: foundation-overview.md
│   ├── health-monitoring.md         # RENAMED: health-checks.md
│   ├── troubleshooting.md           # MERGED: stack-reference-fix + eks-github-actions-auth-fix
│   ├── kubectl-cheatsheet.md        # NEW
│   ├── pulumi-cheatsheet.md         # NEW
│   └── aws-resources.md             # NEW: What AWS resources are created
│
└── archive/                          # Historical/deprecated docs
    └── [existing conversation histories]
```

---

## Content Enhancements & Corrections

### 1. Learning Path Documents

#### 01-kubernetes-fundamentals.md
**Status**: RENAME + ENHANCE existing kubernetes-fundamentals.md

**Add:**
- Clear learning objectives
- Hands-on exercises
- "What you learned" checklist
- Links to next steps

**Review for accuracy:**
- ✅ Control plane components - GOOD
- ✅ Node components - GOOD
- ⚠️ Add: Pod Security Standards (replacing deprecated PSP)
- ⚠️ Add: Container Runtime Interface (CRI) evolution

---

#### 02-eks-deep-dive.md
**Status**: NEW

**Content:**
```markdown
# EKS Deep Dive: Managed Kubernetes on AWS

## What EKS Manages vs What You Manage

### AWS Manages
- Control plane (API server, etcd, scheduler, controller manager)
- Control plane upgrades and patching
- Control plane HA across multiple AZs
- etcd backups

### You Manage
- Worker nodes (EC2 instances or Fargate)
- Node OS patching
- Node scaling
- Application deployments
- Network policies
- Security policies

## Key EKS Features

### 1. VPC CNI Plugin
- Pods get real VPC IP addresses
- Direct pod-to-pod networking
- Security groups for pods
- IP address management considerations

### 2. IAM Roles for Service Accounts (IRSA)
- No hardcoded credentials
- Fine-grained permissions per pod
- OIDC provider integration
- Best practices

### 3. AWS Integration
- Load Balancer Controller (ALB/NLB)
- EBS CSI Driver for persistent storage
- EFS CSI Driver for shared storage
- CloudWatch Container Insights

### 4. Node Groups
- Managed node groups vs self-managed
- Spot instances vs On-Demand
- Mixed instance types
- Capacity considerations

## EKS Best Practices

[Content from AWS EKS Best Practices Guide]
```

---

#### 03-hands-on-first-deploy.md
**Status**: MERGE quickstart-dawn.md + add exploration

**Structure:**
```markdown
# Hands-On: Your First Kubernetes Deployment

## Learning Objectives
- Create an EKS cluster
- Deploy a containerized application
- Expose it via Load Balancer
- Understand each component's role
- Explore Kubernetes objects

## Prerequisites
[Tool installation - link to how-to/setup-environment.md]

## Part 1: Create Cluster
[From quickstart-dawn.md]

## Part 2: Deploy Application
[Step by step with explanations]

## Part 3: Explore What You Built
### Interactive Exploration
```bash
# Explore deployment hierarchy
./foundation/scripts/explore/explore-deployment-hierarchy.sh

# Explore ConfigMap relationships
./foundation/scripts/explore/explore-configmap-relationships.sh
```

## Part 4: Make Changes
- Update the application
- Watch rolling update
- Scale replicas
- View logs

## What You Learned
- ✅ EKS cluster creation with eksctl
- ✅ Container image management with ECR
- ✅ Kubernetes Deployments
- ✅ Services and LoadBalancer
- ✅ Ingress and ALB
- ✅ ConfigMaps for configuration

## Next Steps
→ Dive deeper into [Kubernetes Internals](04-kubernetes-internals.md)
→ Automate this with [Infrastructure as Code](05-infrastructure-as-code.md)
```

---

#### 04-kubernetes-internals.md
**Status**: MERGE deployment-hierarchy + configmap-relationships + rolling-update-mechanism

**Better explain:**
- How Deployments create ReplicaSets
- How ReplicaSets create Pods
- ConfigMap injection patterns
- Rolling update mechanics
- Health checks (readiness, liveness, startup)

---

#### 05-infrastructure-as-code.md
**Status**: MERGE pulumi-setup + deploy-day-cluster

**Add best practices:**
- Why IaC matters
- Pulumi vs other tools (Terraform, CloudFormation)
- State management strategies
- Team collaboration patterns
- Testing infrastructure code
- Policy as code (Pulumi CrossGuard)

**Fix:**
- Explain S3 backend vs Pulumi Cloud
- State locking mechanisms
- Secrets in Pulumi stacks

---

#### 06-application-as-code.md
**Status**: ENHANCE existing application-as-code-guide.md

**Add:**
- Two-tier architecture deep dive
- Stack references as contracts
- When to use Pulumi vs kubectl/Helm
- GitOps comparison (ArgoCD/Flux)
- Migration strategies

**Critical fix:**
```python
# ❌ WRONG
deployment = k8s.apps.v1.Deployment(
    ...
    spec=k8s.apps.v1.DeploymentSpecArgs(
        template=k8s.core.v1.PodTemplateSpecArgs(
            spec=k8s.core.v1.PodSpecArgs(
                containers=[k8s.core.v1.ContainerArgs(
                    image="dawn:latest",  # ❌ MUTABLE TAG
                )]
            )
        )
    )
)

# ✅ RIGHT
image_tag = config.require("image_tag")  # e.g., "sha-a1b2c3d4"
deployment = k8s.apps.v1.Deployment(
    ...
    spec=k8s.apps.v1.DeploymentSpecArgs(
        template=k8s.core.v1.PodTemplateSpecArgs(
            spec=k8s.core.v1.PodSpecArgs(
                containers=[k8s.core.v1.ContainerArgs(
                    image=f"123456789.dkr.ecr.us-east-1.amazonaws.com/dawn:{image_tag}",
                )]
            )
        )
    )
)
```

---

#### 07-cicd-automation.md
**Status**: MERGE ci-setup + cicd-image-deployment + quickstart-dawn-ci

**Add:**
- Image tagging strategies
- Image scanning (Trivy, Snyk)
- Image signing (Cosign, Sigstore)
- SBOM generation
- Deployment automation
- Automated rollback strategies
- Progressive delivery (Flagger, Argo Rollouts)

**Fix image tagging:**
```yaml
# ❌ CURRENT
tags: |
  type=raw,value=latest
  type=raw,value=rc
  type=sha

# ✅ BETTER
tags: |
  type=sha,prefix=sha-
  type=semver,pattern={{version}}
  type=ref,event=branch

# Deployment uses: image:sha-a1b2c3d4 (immutable)
```

---

#### 08-production-ready.md
**Status**: NEW

**Content:**
```markdown
# Production-Ready Kubernetes on EKS

## Security

### 1. Pod Security Standards
```yaml
# Enforce baseline security
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### 2. Network Policies
```yaml
# Default deny all traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### 3. RBAC
- Principle of least privilege
- ServiceAccounts per application
- RoleBindings vs ClusterRoleBindings
- Audit logging

### 4. Secrets Management
```yaml
# ❌ DON'T: Store secrets in ConfigMaps
apiVersion: v1
kind: ConfigMap
data:
  DB_PASSWORD: "supersecret"  # ❌ WRONG

# ✅ DO: Use Kubernetes Secrets + encryption at rest
apiVersion: v1
kind: Secret
type: Opaque
stringData:
  DB_PASSWORD: "supersecret"  # Better, but...

# ✅ BEST: External Secrets Operator
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-secrets
spec:
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: app-secrets
  data:
  - secretKey: DB_PASSWORD
    remoteRef:
      key: prod/app/db-password
```

## Resource Management

### Resource Quotas
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    requests.cpu: "100"
    requests.memory: 200Gi
    limits.cpu: "200"
    limits.memory: 400Gi
    persistentvolumeclaims: "10"
```

### LimitRanges
```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: resource-limits
  namespace: production
spec:
  limits:
  - max:
      cpu: "2"
      memory: "4Gi"
    min:
      cpu: "100m"
      memory: "128Mi"
    default:
      cpu: "500m"
      memory: "512Mi"
    defaultRequest:
      cpu: "200m"
      memory: "256Mi"
    type: Container
```

## High Availability

### Multi-AZ Node Groups
### Pod Disruption Budgets
### Topology Spread Constraints

## Observability

### Structured Logging
### Metrics (Prometheus)
### Distributed Tracing
### Alerting

## Disaster Recovery

### Backup Strategies (Velero)
### Multi-Region Considerations
### RTO/RPO Planning

## Production Deployment Checklist
- [ ] Pod Security Standards enforced
- [ ] Network Policies configured
- [ ] RBAC configured (no default ServiceAccount)
- [ ] Secrets externalized (no hardcoded credentials)
- [ ] Resource requests/limits set
- [ ] Health checks configured (readiness, liveness, startup)
- [ ] HPA configured
- [ ] PDB configured
- [ ] Monitoring and alerting set up
- [ ] Logging centralized
- [ ] Backup strategy in place
- [ ] Disaster recovery tested
- [ ] Image scanning in CI/CD
- [ ] Images signed and verified
- [ ] Immutable image tags
```

---

### 2. Concepts Documents

#### concepts/architecture-decisions.md
**Status**: NEW

**Explain:**
- Why this project uses one cluster per service (LEARNING isolation)
- Why production should use namespaces instead
- Trade-offs and considerations
- When to use multiple clusters (compliance, blast radius, etc.)

---

#### concepts/two-tier-pulumi.md
**Status**: RENAME + ENHANCE pulumi-resource-strategy.md

**Already good, add:**
- Testing strategies
- Stack dependencies
- Version compatibility
- Migration patterns

---

#### concepts/deployment-strategies.md
**Status**: NEW

**Content:**
- Rolling updates (default)
- Blue/Green deployments
- Canary deployments
- Feature flags
- Progressive delivery tools (Flagger, Argo Rollouts)

---

### 3. How-To Guides

Task-based, step-by-step instructions for specific operations.

#### how-to/manage-secrets.md
**Critical addition:**

```markdown
# How to Manage Secrets

## ❌ Anti-Patterns

### Don't use ConfigMaps for secrets
```yaml
# ❌ NEVER DO THIS
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  DATABASE_URL: "postgres://user:password@host/db"  # ❌ EXPOSED
```

### Don't commit secrets to Git
```yaml
# ❌ NEVER DO THIS
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
stringData:
  api-key: "sk_live_abc123"  # ❌ IN VERSION CONTROL
```

## ✅ Best Practices

### 1. Kubernetes Secrets (minimum)
```bash
# Create secret from literal
kubectl create secret generic db-password \
  --from-literal=password=supersecret \
  --namespace production

# Use in deployment
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: app
    env:
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-password
          key: password
```

### 2. External Secrets Operator (recommended)
[Install and configure ESO with AWS Secrets Manager]

### 3. Sealed Secrets (GitOps)
[For ArgoCD/Flux workflows]

## EKS-Specific: IRSA for AWS Credentials
[Instead of hardcoded AWS keys]
```

---

## Migration Plan

### Phase 1: Planning (Current)
- ✅ Audit existing documentation
- ✅ Identify problems and gaps
- ✅ Design new structure
- → Get stakeholder approval

### Phase 2: Core Learning Path (Week 1)
1. Create `learning-path/` directory
2. Rename `kubernetes-fundamentals.md` → `01-kubernetes-fundamentals.md`
3. Create `02-eks-deep-dive.md` (NEW)
4. Merge quickstarts → `03-hands-on-first-deploy.md`
5. Merge internals → `04-kubernetes-internals.md`
6. Merge Pulumi guides → `05-infrastructure-as-code.md`
7. Enhance → `06-application-as-code.md`
8. Merge CI/CD → `07-cicd-automation.md`
9. Create → `08-production-ready.md` (NEW)

### Phase 3: Supporting Content (Week 2)
1. Create `concepts/` directory
2. Move and enhance concept docs
3. Create `how-to/` directory
4. Extract how-to guides from existing docs
5. Create `reference/` directory
6. Organize reference material

### Phase 4: Polish (Week 3)
1. Update all cross-references
2. Rewrite `docs/README.md` with new structure
3. Add learning checkpoints and exercises
4. Create navigation aids
5. Archive old docs

### Phase 5: Validation
1. Walk through each learning path step
2. Verify all commands work
3. Test on clean environment
4. Get user feedback
5. Iterate

---

## Success Criteria

### Learning Experience
- [ ] Clear progression from beginner to advanced
- [ ] Each document builds on previous knowledge
- [ ] Hands-on exercises at each stage
- [ ] Learning checkpoints to verify understanding

### Content Quality
- [ ] Technically accurate (reviewed by K8s expert)
- [ ] Follows industry best practices
- [ ] Security considerations throughout
- [ ] Production-ready patterns shown

### Navigation
- [ ] Easy to find information
- [ ] Clear next steps from each document
- [ ] Cross-references work correctly
- [ ] Table of contents helpful

### Completeness
- [ ] All critical topics covered
- [ ] Security not an afterthought
- [ ] Production patterns explained
- [ ] Both Pulumi and traditional paths shown

---

## Open Questions

1. **Keep or remove one-cluster-per-service pattern?**
   - Keep for learning (simplicity, isolation)
   - But add prominent warnings and show production pattern

2. **Level of Pulumi vs traditional YAML?**
   - Show both approaches
   - Let users choose their path
   - Explain trade-offs

3. **Depth of security coverage?**
   - Comprehensive in 08-production-ready.md
   - References to detailed security guides
   - How-to for specific security tasks

4. **GitOps (ArgoCD) coverage?**
   - Mention as alternative to Pulumi for apps
   - Show in concepts/
   - Full how-to guide?

---

## Next Steps

**Immediate:**
1. Review this plan with stakeholders
2. Get approval on structure
3. Prioritize missing content

**After Approval:**
1. Start Phase 2: Core Learning Path
2. Create new documents
3. Merge existing content
4. Update cross-references

**Questions for Review:**
- Does the learning path make sense?
- Are we missing any critical topics?
- Should we add/remove/reorganize anything?
- What's the priority order for new content?
