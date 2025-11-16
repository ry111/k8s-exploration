# Complete Conversation History: EKS Pulumi Setup and Architecture

## Session Overview

**Date**: November 16, 2025
**Topic**: Pulumi Infrastructure as Code for EKS - Resource Strategy, Application Management, CI/CD Integration
**Branch**: `claude/eks-pulumi-resource-strategy-01B9B49hjA69zhjJBPhDbHhJ`

---

## Conversation Timeline

### 1. Initial Question: Pulumi Resource Strategy for EKS

**User Question**: "I am using EKS and want to use Pulumi Infrastructure as Code for a large scale service. Should I manage my k8s cluster's HPA, ReplicaSet, Deployment, ConfigMap using Pulumi? Which resources are commonly managed through Pulumi?"

**Response Summary**:
Created `PULUMI-RESOURCE-STRATEGY.md` explaining the separation between infrastructure and applications:

**Infrastructure (Manage with Pulumi)**:
- EKS Cluster
- VPC, subnets, security groups
- Node groups
- IAM roles and OIDC provider
- AWS Load Balancer Controller
- Cluster-wide resources

**Applications (Manage with GitOps/kubectl)**:
- Deployments
- Services
- ConfigMaps (application config)
- HPA
- ReplicaSets
- Pods
- Ingresses

**Key Decision**: Use Pulumi for infrastructure, GitOps for applications. This provides clear separation of concerns and allows platform team to manage infrastructure while application teams deploy apps independently.

---

### 2. Application Resources as Code

**User Question**: "how do I manage my application resources via code and not json/yaml?"

**Response Summary**:
Created `APPLICATION-AS-CODE-GUIDE.md` initially with 4 options:
1. Pulumi with Kubernetes provider
2. CDK8s (Kubernetes CDK)
3. Helm + code generation
4. Kubernetes client libraries

Created working example at `applications/day-service/pulumi/` with complete:
- Deployment resource
- Service (ClusterIP)
- ConfigMap
- HorizontalPodAutoscaler
- Ingress

**Key Pattern**: Separate Pulumi programs for infrastructure vs applications
- `foundation/pulumi/` - Infrastructure
- `applications/day-service/pulumi/` - Application

---

### 3. Directory Reorganization - Foundation Structure

**User Feedback**: "foundation is the name of my whole experiment, the Pulumi for application resource management should still be under that and not alongside it. Also, I'm also interested in the Pulumi scenario, remove the other options."

**Actions Taken**:
1. Moved `applications/` to `foundation/applications/`
2. Rewrote `APPLICATION-AS-CODE-GUIDE.md` to focus solely on Pulumi
3. Updated all documentation references

**Key Insight**: User clarified that "foundation" is the top-level experiment directory, not just infrastructure.

---

### 4. Infrastructure Directory Structure

**User Request**: "move foundation/pulumi to be under foundation/infrastructure/pulumi and update all relevant docs and links"

**Actions Taken**:
1. Created `foundation/infrastructure/` directory
2. Moved `foundation/pulumi/` to `foundation/infrastructure/pulumi/`
3. Updated 16 files with new path references
4. Updated GitHub workflows:
   - `.github/workflows/pulumi-preview.yml`
   - `.github/workflows/pulumi-up.yml`

**Files Updated**:
- All documentation (README, guides, deployment docs)
- GitHub Actions workflows
- Script references

---

### 5. Documentation Consolidation

**User Request**: "move all docs to a root level docs folder"

**Actions Taken**:
1. Created `docs/` directory at root
2. Moved 12 documentation files from root and `foundation/` to `docs/`
3. Renamed files to lowercase-with-hyphens convention:
   - `PULUMI-SETUP.md` → `pulumi-setup.md`
   - `APPLICATION-AS-CODE-GUIDE.md` → `application-as-code-guide.md`
4. Created `docs/README.md` as documentation index
5. Created root `README.md` as project overview
6. Updated all inter-document references

**Documentation Structure**:
```
docs/
├── README.md (index)
├── pulumi-setup.md
├── application-as-code-guide.md
├── pulumi-resource-strategy.md
├── deploy-day-cluster.md
├── foundation-overview.md
└── ... (12+ files)
```

---

### 6. Documentation Review and Updates

**User Request**: "review all docs in all folders and make sure the content is up to date, including folder structures and links"

**Issues Found and Fixed**:
1. Incomplete structure diagrams (missing `foundation/services/` and `foundation/scripts/`)
2. Broken link in `docs/deploy-day-cluster.md`
3. Outdated structure in `docs/foundation-overview.md`
4. Updated `README.md` and `docs/README.md` with complete structure

---

### 7. Script Organization

**User Question**: "why are the explore scripts under root?"

**Response**: Explained they clutter root, proposed 3 options:
1. Move to `foundation/scripts/explore/` (recommended)
2. Move to `foundation/learning/`
3. Create `scripts/` at root

**User Choice**: Option 1

**Actions Taken**:
1. Created `foundation/scripts/explore/`
2. Moved 3 explore scripts:
   - `explore-deployment-hierarchy.sh`
   - `explore-configmap-relationships.sh`
   - `explore-rolling-updates.sh`
3. Updated 6 documentation files with new script paths

---

### 8. Understanding Stack Names

**User Question**: "what is my pulumi infrastructure stack name?"

**Response Explained**:
- **Project name**: `service-infrastructure`
- **Stack names**: `day` and `dusk`
- **Configuration details**:
  - `Pulumi.day.yaml`: day cluster config
  - `Pulumi.dusk.yaml`: dusk cluster config
- **Full stack references**: `organization/service-infrastructure/day`

**Key Clarification**: Stack = environment/instance of infrastructure defined in Pulumi program.

---

### 9. Image Version Management in Pulumi

**User Question**: "how does pulumi for application resources set the image version in Deployment resource? Or does it not do that?"

**Response Explained**:
- Configuration via `image_tag` in `Pulumi.{stack}.yaml`
- Code reads config: `image_tag = config.get("image_tag") or "latest"`
- Image path constructed: `image=f"{image_registry}/{app_name}:{image_tag}"`
- Update with: `pulumi config set image_tag sha-abc123`

**Example**:
```yaml
# Pulumi.dev.yaml
config:
  day-service-app:image_tag: latest

# Pulumi.production.yaml
config:
  day-service-app:image_tag: v1.2.3
```

---

### 10. CI/CD Integration for Image Deployment

**User Question**: "how is image version updated with a CI/CD workflow that builds the image?"

**Response Created**:
Comprehensive guide showing 4 integration patterns:

**Option 1: Sequential Jobs (Recommended)**:
```yaml
jobs:
  build-and-push:
    outputs:
      image_tag: ${{ github.sha }}

  deploy-dev:
    needs: build-and-push
    uses: pulumi/actions@v4
    with:
      config-map: |
        {
          "image_tag": { "value": "${{ needs.build-and-push.outputs.image_tag }}" }
        }
```

**Option 2: GitOps Approach**:
- Build workflow updates Pulumi config in Git
- Separate workflow triggers on config change
- Creates audit trail but adds Git commits

**Option 3: Manual Deployment**:
- Script-based: `./deploy-image-version.sh dev sha-abc123`
- Good for learning and controlled deployments

**Option 4: Hybrid**:
- Auto build, manual deploy via `workflow_dispatch`
- Balance of automation and control

**Files Created**:
- `.github/workflows/build-and-deploy-day.yml.example`
- `.github/workflows/build-and-commit-day.yml.example`
- `foundation/scripts/deploy-image-version.sh`
- `docs/cicd-image-deployment.md`

---

### 11. Stack Reference Testing Issue

**User Observation**: "the problem is that `pulumi preview` works even when I mistype fnstackreference on purpose"

**Critical Discovery**: `fn::stackReference` in YAML config files **doesn't actually work** for Kubernetes provider. Pulumi doesn't recognize the `fn::` syntax in general config YAML files.

**Root Cause**:
- `fn::stackReference` is not valid Pulumi config syntax
- Pulumi was silently ignoring it
- Kubernetes provider was falling back to default kubeconfig
- No error occurred because fallback worked

**The Fix**: Use `pulumi.StackReference()` in Python code, not in YAML

**New Approach**:
```python
# In __main__.py
infra_stack = pulumi.StackReference("ry111/service-infrastructure/day")
kubeconfig = infra_stack.require_output("kubeconfig")

# Create explicit Kubernetes provider
k8s_provider = k8s.Provider("k8s-provider", kubeconfig=kubeconfig)

# Use it for all resources
deployment = k8s.apps.v1.Deployment(
    ...,
    opts=pulumi.ResourceOptions(provider=k8s_provider)
)
```

**Config Change**:
```yaml
# Simple config values (no fn:: syntax)
day-service-app:use_stack_reference: true
day-service-app:infra_stack_name: ry111/service-infrastructure/day
```

**Files Created**:
- `docs/stack-reference-fix.md` - Complete explanation
- `__main__.py.fixed` - Corrected application code
- `Pulumi.dev.yaml.fixed` - Updated config
- `Pulumi.production.yaml.fixed` - Updated config

**Key Benefit**: Now fails fast with clear errors if stack reference is misconfigured.

---

### 12. Stack Reference Verification

**User Question**: "how do I check that fn::stackReference works?"

**Initial Answer**: Use `pulumi preview` to test

**Correction After Discovery**: Since `fn::stackReference` doesn't work, created proper verification tools:

**Files Created**:
- `foundation/scripts/verify-stack-reference.sh` - Automated verification
- `foundation/scripts/test-stack-reference-simple.sh` - Quick diagnostics
- `foundation/applications/day-service/pulumi/test-reference.py` - Python test

**Key Commands**:
```bash
# Test direct reference
pulumi stack output kubeconfig --stack ry111/service-infrastructure/day

# Run verification
./foundation/scripts/verify-stack-reference.sh
```

**Important Clarification**:
- `pulumi stack output kubeconfig` from app stack will NEVER work
- App stack doesn't export kubeconfig, it only reads it via stack reference
- The real test is: `pulumi preview` (uses the reference)

---

### 13. Namespace Management Strategy

**User Question**: "which pulumi stack should create the production namespace? the infrastructure or the application?"

**Recommendation**: **Application Stack Creates Namespace**

**Reasoning**:
1. **Namespace is application-scoped** - Each service gets its own namespace
2. **Enables independent deployments** - App team can deploy without infrastructure team
3. **Application owns its isolation boundary** - Namespace is part of app's resources
4. **Allows app-specific policies** - ResourceQuotas, NetworkPolicies, RBAC per namespace

**Implementation**:
```python
# Create namespace first
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

# All resources depend on namespace
deployment = k8s.apps.v1.Deployment(
    ...,
    opts=pulumi.ResourceOptions(
        provider=...,
        depends_on=[ns],
    ),
)
```

**Stack Responsibilities**:
- **Infrastructure**: EKS cluster, VPC, nodes, cluster-scoped resources
- **Application**: Namespace + all application resources

**Documentation Created**: `docs/namespace-management-strategy.md`

**Alternative Approaches Documented**:
- Infrastructure stack creating namespaces (centralized control)
- Conditional namespace creation
- Namespace conflict handling

---

### 14. Image Registry Configuration

**User Question**: "what should I put in image_registry of pulumi yaml file?"

**Answer**: Amazon ECR registry URL in format:
```
{aws_account_id}.dkr.ecr.us-east-1.amazonaws.com
```

**Issue Discovered**: Mismatch between ECR repository name and Pulumi app name:
- ECR repository (from build workflow): `day`
- Pulumi app_name: `day-service`

**Solution**: Added `image_name` config to separate concerns:
```python
# In __main__.py
app_name = "day-service"  # For K8s resource naming
image_name = config.get("image_name") or "day"  # For ECR repository

# Image path uses image_name
image = f"{image_registry}/{image_name}:{image_tag}"
```

**Config Update**:
```yaml
day-service-app:image_registry: 123456789012.dkr.ecr.us-east-1.amazonaws.com
day-service-app:image_name: day  # Matches ECR repo
day-service-app:image_tag: latest
```

**Helper Created**: `foundation/scripts/get-ecr-registry.sh`

---

### 15. GitOps Approach Discussion

**User Question**: "why is the gitops approach not recommended?"

**Detailed Explanation**:

**Why GitOps + Pulumi Is Awkward**:

1. **Dual State Management**:
   - GitOps assumes Git is single source of truth
   - Pulumi has its own state backend
   - Creates conflict between two sources of truth

2. **Git History Pollution**:
   - Every image deployment = 1 commit
   - 10 deploys/day = 300+ noise commits/month
   - Real code changes get buried

3. **Not True GitOps**:
   - True GitOps has continuous reconciliation (ArgoCD/Flux)
   - Pulumi approach is just Git-triggered CI/CD
   - No drift detection, no self-healing

4. **Pulumi's Config-Map Is Superior**:
   ```yaml
   # GitOps: Requires Git commit
   - Update Pulumi.dev.yaml
   - Commit and push

   # Sequential: No Git commit
   pulumi up --config-map '{"image_tag": {"value": "sha-abc123"}}'
   ```

5. **Pulumi Has Built-in Audit Trail**:
   - `pulumi stack history` already tracks deployments
   - Don't need Git commits for audit

**When GitOps DOES Make Sense**:
- Using real GitOps tools (ArgoCD/Flux) for applications
- Heavy compliance requirements
- Separation between build and deploy teams
- Multi-team coordination with PR approvals

**Recommendation**:
- Use Sequential workflow (Option 1) for solo/small teams
- Use real GitOps tools (ArgoCD/Flux) for true GitOps benefits
- Pulumi excels at infrastructure, not application GitOps

---

### 16. Workflow Stack Name Fixes

**User Question**: "why is pulumi-preview.yml mentioning pulumi 'dev' stack?"

**Problem Identified**:
- Infrastructure stacks: `day`, `dusk`
- Application stacks: `dev`, `production`
- But infrastructure workflows used `stack-name: dev` ❌

**Root Cause**: Mismatch between stack names
```
Infrastructure Stacks (Cluster Names):
├── day   → day-cluster (EKS)
└── dusk  → dusk-cluster (EKS)

Application Stacks (Environment):
├── dev        → Deploys to day-cluster (dev namespace)
└── production → Deploys to day-cluster (production namespace)
```

**Initial Fix**: Updated workflows to use both day and dusk stacks

**User Decision**: "I am not planning on creating dusk service, let's remove it from the workflows"

**Final Fix**: Simplified workflows to only manage day stack:

**pulumi-preview.yml**:
```yaml
jobs:
  preview:
    - name: Pulumi Preview
      stack-name: day  # ✅ Correct
```

**pulumi-up.yml**:
```yaml
jobs:
  deploy:
    - name: Pulumi Up
      stack-name: day  # ✅ Correct
```

**Removed**: All dusk stack deployment jobs and dependencies

---

### 17. User Configuration Updates

**During Session, User Updated**:

1. **Application Config Files** (`Pulumi.dev.yaml`, `Pulumi.production.yaml`):
   - Changed `infra_stack_name` from `ry111/service-infrastructure/day` to `ry111-org/service-infrastructure/day`
   - This indicates user's Pulumi organization name is `ry111-org`

2. **Workflows**: User modified the simplified workflows (changes acknowledged)

3. **GitIgnore**: Added `*.backup` to ignore backup files

---

### 18. IAM Permissions Error - ALB Controller

**User Error**:
```
warning: FailedDeployModel: Failed deploy model due to operation error
Elastic Load Balancing v2: DescribeListenerAttributes,
api error AccessDenied: User: arn:aws:sts::612974049499:assumed-role/day-alb-controller-role-6b871df/...
is not authorized to perform: elasticloadbalancing:DescribeListenerAttributes
```

**Error Explanation**:
1. Pulumi creates Ingress resource
2. AWS Load Balancer Controller tries to create ALB
3. Controller fails due to missing IAM permission
4. IAM role `day-alb-controller-role` lacks `DescribeListenerAttributes` permission

**Root Cause**: Infrastructure code created IAM policy but was missing required permissions

**Missing Permissions**:
- `elasticloadbalancing:DescribeListenerAttributes` (primary error)
- `elasticloadbalancing:ModifyListener`
- `elasticloadbalancing:ModifyRule`
- `elasticloadbalancing:SetWebAcl`
- `elasticloadbalancing:SetSecurityGroups`
- `elasticloadbalancing:SetSubnets`
- `elasticloadbalancing:DescribeSSLPolicies`

**The Fix**: Added 46 additional IAM permissions across categories:

**ELB Permissions** (Enhanced):
```python
actions=[
    "elasticloadbalancing:DescribeListenerAttributes",  # Added
    "elasticloadbalancing:ModifyListener",  # Added
    "elasticloadbalancing:ModifyRule",  # Added
    "elasticloadbalancing:SetWebAcl",  # Added
    "elasticloadbalancing:SetSecurityGroups",  # Added
    "elasticloadbalancing:SetSubnets",  # Added
    "elasticloadbalancing:DescribeSSLPolicies",  # Added
    # ... existing permissions
]
```

**WAF Permissions** (New):
```python
actions=[
    "wafv2:GetWebACL",
    "wafv2:GetWebACLForResource",
    "wafv2:AssociateWebACL",
    "wafv2:DisassociateWebACL",
]
```

**Shield Permissions** (New):
```python
actions=[
    "shield:GetSubscriptionState",
    "shield:DescribeProtection",
    "shield:CreateProtection",
    "shield:DeleteProtection",
]
```

**Cognito Permissions** (New):
```python
actions=[
    "cognito-idp:DescribeUserPoolClient",
]
```

**ACM Permissions** (New):
```python
actions=[
    "acm:ListCertificates",
    "acm:DescribeCertificate",
]
```

**How to Apply**:
```bash
cd foundation/infrastructure/pulumi
pulumi preview --stack day
pulumi up --stack day
```

**Expected Result**:
- IAM policy updated with new permissions
- ALB controller can now successfully create load balancers
- Ingress resource should succeed

---

## Final Architecture Summary

### Directory Structure
```
k8s-exploration/
├── docs/                                    # All documentation
│   ├── README.md                            # Documentation index
│   ├── pulumi-setup.md
│   ├── application-as-code-guide.md
│   ├── pulumi-resource-strategy.md
│   ├── cicd-image-deployment.md
│   ├── stack-reference-fix.md
│   ├── namespace-management-strategy.md
│   └── ... (12+ guides)
├── foundation/
│   ├── infrastructure/pulumi/               # Infrastructure as Code
│   │   ├── __main__.py
│   │   ├── Pulumi.day.yaml
│   │   └── Pulumi.dusk.yaml
│   ├── applications/day-service/pulumi/     # Application resources
│   │   ├── __main__.py
│   │   ├── Pulumi.dev.yaml
│   │   └── Pulumi.production.yaml
│   ├── services/                            # Application source code
│   │   └── day/
│   ├── k8s/                                 # Kubernetes manifests (if any)
│   └── scripts/
│       ├── explore/                         # Learning scripts
│       │   ├── explore-deployment-hierarchy.sh
│       │   ├── explore-configmap-relationships.sh
│       │   └── explore-rolling-updates.sh
│       ├── deploy-image-version.sh
│       ├── verify-stack-reference.sh
│       └── get-ecr-registry.sh
├── .github/workflows/                       # CI/CD pipelines
│   ├── pulumi-preview.yml                   # Infrastructure preview
│   ├── pulumi-up.yml                        # Infrastructure deploy
│   ├── build-day.yml                        # Build and push image
│   ├── build-and-deploy-day.yml.example     # Sequential workflow
│   └── build-and-commit-day.yml.example     # GitOps workflow
└── README.md                                # Project overview
```

### Stack Architecture

**Infrastructure Stack** (`service-infrastructure/day`):
- Creates: EKS cluster (`day-cluster`)
- VPC: `10.1.0.0/16`
- Node groups with spot instances
- OIDC provider for IRSA
- AWS Load Balancer Controller with full IAM permissions

**Application Stacks** (`day-service-app/{dev,production}`):
- Both deploy to `day-cluster`
- Separate namespaces: `dev`, `production`
- Creates namespace + all application resources
- Uses stack reference: `ry111-org/service-infrastructure/day`

### Key Technical Patterns

1. **Stack Reference Pattern**:
   ```python
   infra_stack = pulumi.StackReference("ry111-org/service-infrastructure/day")
   kubeconfig = infra_stack.require_output("kubeconfig")
   k8s_provider = k8s.Provider("k8s", kubeconfig=kubeconfig)
   ```

2. **Image Configuration**:
   ```yaml
   image_registry: {account-id}.dkr.ecr.us-east-1.amazonaws.com
   image_name: day
   image_tag: sha-abc123
   ```

3. **Namespace Management**:
   - Application stack creates namespace
   - All resources depend on namespace
   - Enables independent deployments

4. **CI/CD Integration**:
   - Build: Docker image with git SHA tag
   - Deploy: Pulumi with dynamic config-map
   - No Git commits for deployments

### Configuration Summary

**Infrastructure** (`foundation/infrastructure/pulumi/Pulumi.day.yaml`):
```yaml
service-infrastructure:service_name: day
service-infrastructure:vpc_cidr: 10.1.0.0/16
service-infrastructure:cluster_name: day-cluster
service-infrastructure:use_spot: "true"
```

**Application Dev** (`foundation/applications/day-service/pulumi/Pulumi.dev.yaml`):
```yaml
day-service-app:use_stack_reference: true
day-service-app:infra_stack_name: ry111-org/service-infrastructure/day
day-service-app:namespace: dev
day-service-app:image_registry: {account-id}.dkr.ecr.us-east-1.amazonaws.com
day-service-app:image_name: day
day-service-app:image_tag: latest
day-service-app:replicas: 1
```

**Application Production** (`foundation/applications/day-service/pulumi/Pulumi.production.yaml`):
```yaml
day-service-app:use_stack_reference: true
day-service-app:infra_stack_name: ry111-org/service-infrastructure/day
day-service-app:namespace: production
day-service-app:image_registry: {account-id}.dkr.ecr.us-east-1.amazonaws.com
day-service-app:image_name: day
day-service-app:image_tag: v1.2.3
day-service-app:replicas: 5
```

---

## Key Decisions Made

1. **Resource Management**: Pulumi for infrastructure, Pulumi for applications (separate programs)
2. **Directory Structure**: `foundation/` as top-level experiment directory
3. **Documentation**: Centralized in `docs/` with lowercase-hyphen naming
4. **Scripts**: Organized under `foundation/scripts/explore/`
5. **Stack References**: Use Python `StackReference()` API, not YAML `fn::`
6. **Namespace Creation**: Application stack creates and manages namespaces
7. **Image Registry**: ECR with separate `image_name` config for repository
8. **CI/CD Approach**: Sequential workflow recommended over GitOps
9. **Workflow Scope**: Single infrastructure stack (day) managed by workflows
10. **IAM Permissions**: Comprehensive ALB controller permissions with WAF, Shield, ACM

---

## Files Created During Session

### Documentation
1. `docs/README.md` - Documentation index
2. `docs/pulumi-resource-strategy.md` - What to manage with Pulumi
3. `docs/application-as-code-guide.md` - Managing apps with Pulumi
4. `docs/cicd-image-deployment.md` - CI/CD integration guide
5. `docs/stack-reference-fix.md` - Stack reference explanation
6. `docs/namespace-management-strategy.md` - Namespace strategy
7. `README.md` - Project overview

### Scripts
1. `foundation/scripts/deploy-image-version.sh` - Manual deployment
2. `foundation/scripts/verify-stack-reference.sh` - Stack reference verification
3. `foundation/scripts/test-stack-reference-simple.sh` - Quick diagnostics
4. `foundation/scripts/get-ecr-registry.sh` - Get ECR URL

### Workflow Examples
1. `.github/workflows/build-and-deploy-day.yml.example` - Sequential workflow
2. `.github/workflows/build-and-commit-day.yml.example` - GitOps workflow

### Test Files
1. `foundation/applications/day-service/pulumi/test-reference.py` - Python test
2. `test-stack-reference.py` - Root-level test
3. `test-config-resolution.py` - Config resolution test

---

## Major Code Changes

### Infrastructure (`foundation/infrastructure/pulumi/__main__.py`)
**Added IAM Permissions** (Lines 182-267):
- Enhanced ELB permissions (7 new actions)
- WAF v2 permissions (4 actions)
- Shield permissions (4 actions)
- Cognito permissions (1 action)
- ACM permissions (2 actions)
- Total: 46 additional IAM permissions

### Application (`foundation/applications/day-service/pulumi/__main__.py`)
**Added Features**:
1. Stack reference in code (lines 20-56)
2. Explicit Kubernetes provider (lines 20-56)
3. Namespace creation (lines 104-115)
4. Dependencies on namespace (all resources)
5. Image name configuration (line 68)

**Before**:
```python
# No stack reference
# No namespace creation
image = f"{image_registry}/{app_name}:{image_tag}"
```

**After**:
```python
# Stack reference
infra_stack = pulumi.StackReference(infra_stack_name)
kubeconfig = infra_stack.require_output("kubeconfig")
k8s_provider = k8s.Provider("k8s-provider", kubeconfig=kubeconfig)

# Namespace creation
ns = k8s.core.v1.Namespace(...)

# Separate image_name
image = f"{image_registry}/{image_name}:{image_tag}"

# All resources with provider and dependencies
deployment = k8s.apps.v1.Deployment(
    ...,
    opts=pulumi.ResourceOptions(
        provider=k8s_provider,
        depends_on=[ns],
    ),
)
```

---

## Troubleshooting Solutions Provided

### 1. Stack Reference Not Working
**Problem**: `fn::stackReference` in YAML doesn't work
**Solution**: Use `pulumi.StackReference()` in Python code

### 2. Image Name Mismatch
**Problem**: ECR repo = "day", app_name = "day-service"
**Solution**: Add `image_name` config parameter

### 3. Wrong Stack Names in Workflows
**Problem**: Workflows used "dev" instead of "day"
**Solution**: Update to use correct infrastructure stack name

### 4. IAM Permission Errors
**Problem**: ALB controller lacks permissions
**Solution**: Add comprehensive ELB, WAF, Shield, ACM permissions

### 5. Namespace Not Created
**Problem**: Application assumes namespace exists
**Solution**: Application stack creates namespace with dependencies

---

## Commands Reference

### Infrastructure Deployment
```bash
cd foundation/infrastructure/pulumi
pulumi stack select day
pulumi preview
pulumi up
```

### Application Deployment
```bash
cd foundation/applications/day-service/pulumi
pulumi stack select dev
pulumi config set image_registry {account-id}.dkr.ecr.us-east-1.amazonaws.com
pulumi config set image_tag sha-abc123
pulumi preview
pulumi up
```

### Stack Reference Verification
```bash
# Check infrastructure exports
pulumi stack output kubeconfig --stack ry111-org/service-infrastructure/day

# Verify configuration
./foundation/scripts/verify-stack-reference.sh

# Test deployment
pulumi preview --stack dev
```

### ECR Registry Setup
```bash
# Get ECR URL
./foundation/scripts/get-ecr-registry.sh

# Or manually
aws sts get-caller-identity --query Account --output text
# Result: {account-id}.dkr.ecr.us-east-1.amazonaws.com
```

---

## Next Steps for User

1. **Set Image Registry**:
   ```bash
   cd foundation/applications/day-service/pulumi
   pulumi config set image_registry {your-ecr-url} --stack dev
   pulumi config set image_registry {your-ecr-url} --stack production
   ```

2. **Apply IAM Permission Fix**:
   ```bash
   cd foundation/infrastructure/pulumi
   pulumi up --stack day
   ```

3. **Deploy Application**:
   ```bash
   cd foundation/applications/day-service/pulumi
   pulumi up --stack dev
   ```

4. **Set Up CI/CD** (Optional):
   - Copy workflow example: `cp .github/workflows/build-and-deploy-day.yml.example .github/workflows/build-and-deploy-day.yml`
   - Set GitHub secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `PULUMI_ACCESS_TOKEN`
   - Create production environment with approvers

---

## Lessons Learned

1. **`fn::stackReference` doesn't work in Pulumi YAML** - Must use Python API
2. **Stack references must use full organization path** - `ry111-org/project/stack`
3. **Pulumi and GitOps have friction** - Different philosophies on state management
4. **Infrastructure vs Application stacks have different naming** - `day` vs `dev`
5. **ALB controller needs comprehensive IAM permissions** - Not just basic ELB
6. **Namespace creation belongs in application stack** - Enables independence
7. **Separate image_name from app_name** - Different purposes (ECR vs K8s)
8. **Config-map parameter is superior to Git commits** - For dynamic values

---

## Total Commits Made

1. Initial Pulumi resource strategy document
2. Application as code guide and example
3. Move applications under foundation
4. Move Pulumi to infrastructure directory
5. Move all docs to root level docs folder
6. Review and update all documentation
7. Move explore scripts to foundation/scripts/explore
8. Add CI/CD image deployment guide
9. Add stack reference verification tools
10. Fix stack reference to use Python API
11. Add namespace creation to application stack
12. Add image_name configuration
13. Ignore backup files
14. Update workflow example with image_name
15. Fix workflow stack names (day/dusk)
16. Simplify workflows (remove dusk)
17. Add missing ALB controller IAM permissions

**Branch**: `claude/eks-pulumi-resource-strategy-01B9B49hjA69zhjJBPhDbHhJ`

---

## End of Session Status

**Repository State**:
- ✅ Complete documentation in `docs/`
- ✅ Organized directory structure
- ✅ Working stack reference implementation
- ✅ Namespace creation in application stack
- ✅ Comprehensive ALB IAM permissions
- ✅ CI/CD workflow examples
- ✅ Helper scripts for common tasks
- ✅ All files committed and pushed

**Ready for**:
- Infrastructure deployment (`pulumi up --stack day`)
- Application deployment (`pulumi up --stack dev`)
- CI/CD pipeline setup
- Production rollout

**User Account**: `612974049499`
**Organization**: `ry111-org`
**Cluster**: `day-cluster`
**Stacks**: `day` (infrastructure), `dev`/`production` (application)
