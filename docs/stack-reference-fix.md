# Stack Reference Fix: Using StackReference in Code

## The Problem

You discovered that `pulumi preview` works even when `fn::stackReference` is mistyped in the YAML config file. This reveals that **`fn::stackReference` syntax in Pulumi YAML config files doesn't work** for Kubernetes provider configuration.

### Why It Didn't Fail

When you had this in `Pulumi.dev.yaml`:
```yaml
kubernetes:kubeconfig:
  fn::stackReference:
    name: ry111/service-infrastructure/day
    output: kubeconfig
```

Pulumi **doesn't recognize** the `fn::` syntax in regular config YAML files. The `fn::` syntax is specific to certain cloud providers (like AWS CloudFormation) but not supported in Pulumi's general configuration system.

As a result:
- Pulumi ignores or misinterprets the value
- The Kubernetes provider falls back to default kubeconfig sources
- No error occurs because the provider can still work (just not using stack reference)

## The Solution

**Use `pulumi.StackReference()` in your Python code**, not in YAML config.

### Code Changes Required

The fixed `__main__.py` (see `__main__.py.fixed`) now:

1. **Reads config to determine if stack reference should be used**:
```python
use_stack_reference = config.get_bool("use_stack_reference")
infra_stack_name = config.get("infra_stack_name") or "ry111/service-infrastructure/day"
```

2. **Creates a StackReference object in code**:
```python
if use_stack_reference:
    # Create stack reference to infrastructure stack
    infra_stack = pulumi.StackReference(infra_stack_name)

    # Get kubeconfig output from infrastructure stack
    kubeconfig = infra_stack.require_output("kubeconfig")

    # Create explicit Kubernetes provider
    k8s_provider = k8s.Provider("k8s-provider", kubeconfig=kubeconfig)

    provider_opts = pulumi.ResourceOptions(provider=k8s_provider)
```

3. **Uses the provider for all resources**:
```python
deployment = k8s.apps.v1.Deployment(
    f"{app_name}-deployment",
    metadata={...},
    spec={...},
    opts=provider_opts,  # ← Pass provider to every resource
)
```

### Config Changes Required

The fixed config files (see `Pulumi.*.yaml.fixed`) now use simple config values instead of `fn::`:

```yaml
config:
  # Simple boolean and string configs - no fn:: syntax
  day-service-app:use_stack_reference: true
  day-service-app:infra_stack_name: ry111/service-infrastructure/day

  # Rest of config...
  day-service-app:namespace: dev
  day-service-app:image_tag: latest
```

## How to Apply the Fix

1. **Backup current files**:
```bash
cd foundation/applications/day-service/pulumi
cp __main__.py __main__.py.backup
cp Pulumi.dev.yaml Pulumi.dev.yaml.backup
cp Pulumi.production.yaml Pulumi.production.yaml.backup
```

2. **Replace with fixed versions**:
```bash
mv __main__.py.fixed __main__.py
mv Pulumi.dev.yaml.fixed Pulumi.dev.yaml
mv Pulumi.production.yaml.fixed Pulumi.production.yaml
```

3. **Test the fix**:
```bash
pulumi stack select dev

# This will now FAIL if stack reference is misconfigured
pulumi preview
```

## How to Verify It Works

### Test 1: Stack Reference Should Be Required

```bash
# Temporarily change infra_stack_name to invalid value
pulumi config set infra_stack_name invalid/stack/name

# This should FAIL with clear error
pulumi preview
# Expected error: "failed to resolve stack reference 'invalid/stack/name'"

# Fix it back
pulumi config set infra_stack_name ry111/service-infrastructure/day
```

### Test 2: Check Outputs

```bash
pulumi preview

# Should show in outputs:
# using_stack_reference: true
# infra_stack_referenced: ry111/service-infrastructure/day
```

### Test 3: Disable Stack Reference (Use Local Kubeconfig)

```bash
# For local development, you can disable stack reference
pulumi config set use_stack_reference false

# Now it will use local kubeconfig instead
pulumi preview
```

## Key Differences

| Aspect | Before (Broken) | After (Fixed) |
|--------|----------------|---------------|
| **Stack Reference Location** | YAML config file (`fn::stackReference`) | Python code (`pulumi.StackReference()`) |
| **Error on Misconfiguration** | ❌ Silent failure, falls back | ✅ Explicit error |
| **Verifiable** | ❌ Hard to test | ✅ Clear outputs and errors |
| **Provider Setup** | Implicit (doesn't work) | Explicit Provider object |
| **Resource Opts** | None | `opts=provider_opts` on every resource |

## Why This Approach Works

1. **`pulumi.StackReference()` is the official Python API** for referencing other stacks
2. **Creates an explicit Provider object** that Kubernetes resources can use
3. **`require_output()` will fail immediately** if the stack or output doesn't exist
4. **Every resource explicitly uses the provider**, no implicit fallbacks
5. **Exports show which mode is active** for debugging

## Production Usage

For CI/CD, your workflow stays the same:

```yaml
# GitHub Actions workflow
- name: Deploy to Dev
  uses: pulumi/actions@v4
  with:
    work-dir: foundation/applications/day-service/pulumi
    stack-name: dev
    command: up
    config-map: |
      {
        "image_tag": { "value": "${{ github.sha }}" }
      }
```

The stack reference happens automatically in the code.

## Switching Between Stack Reference and Local Kubeconfig

```bash
# Use stack reference (production/CI-CD)
pulumi config set use_stack_reference true
pulumi config set infra_stack_name ry111/service-infrastructure/day

# Use local kubeconfig (development)
pulumi config set use_stack_reference false
# Make sure you have valid kubeconfig:
aws eks update-kubeconfig --name day-cluster
```

## Summary

**The `fn::stackReference` syntax in YAML config doesn't work.** Instead:
- ✅ Use `pulumi.StackReference()` in Python code
- ✅ Create explicit `k8s.Provider()` with the kubeconfig
- ✅ Pass `opts=provider_opts` to every resource
- ✅ Use simple config values to control behavior

This approach is:
- More explicit
- Easier to debug
- Fails fast with clear errors
- Standard Pulumi best practice
