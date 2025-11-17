#!/usr/bin/env python3
"""
Test script to verify stack reference works.
Run this in the application Pulumi directory.

Usage:
  cd foundation/gitops/pulumi_deploy
  python3 ../../../scripts/test-stack-reference.py
"""

import pulumi

# Test reading from infrastructure stack
infra_stack = pulumi.StackReference("foundation/day")

# Try to read the kubeconfig output
kubeconfig = infra_stack.get_output("kubeconfig")

# Export it to verify it works
pulumi.export("test_kubeconfig_from_infra", kubeconfig)

print("✅ Stack reference test successful!")
print("Run 'pulumi preview' to see if kubeconfig was retrieved")
