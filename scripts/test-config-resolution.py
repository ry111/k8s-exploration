#!/usr/bin/env python3
"""
Test to see what the kubernetes:kubeconfig config actually resolves to.
Run from: foundation/gitops/day/
"""

import pulumi

# Test what the config value actually is
k8s_config = pulumi.Config("kubernetes")
kubeconfig_value = k8s_config.get("kubeconfig")

print("=" * 60)
print("Config Resolution Test")
print("=" * 60)
print(f"Type: {type(kubeconfig_value)}")
print(f"Value: {kubeconfig_value}")
print("=" * 60)

# If it's a dict or string, the fn::stackReference isn't being resolved
if isinstance(kubeconfig_value, dict):
    print("⚠️  Config returned a dict - fn::stackReference NOT auto-resolved")
    print("    You need to use StackReference in code instead!")
elif isinstance(kubeconfig_value, str):
    print("⚠️  Config returned a string - fn::stackReference NOT auto-resolved")
elif kubeconfig_value is None:
    print("✅ Config is None - provider will use default kubeconfig sources")
else:
    print(f"🤔 Unexpected type: {type(kubeconfig_value)}")
