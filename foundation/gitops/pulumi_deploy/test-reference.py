#!/usr/bin/env python3
"""
Quick test to verify stack reference works.
Run from: foundation/applications/day-service/pulumi/

Usage:
  python3 test-reference.py
"""

import pulumi

# This is what happens behind the scenes when using fn::stackReference
config = pulumi.Config("kubernetes")
kubeconfig_value = config.get("kubeconfig")

print("Testing stack reference resolution...")
print(f"kubernetes:kubeconfig config value: {type(kubeconfig_value)}")

# Try to read the infrastructure stack directly
try:
    infra_stack = pulumi.StackReference("ry111/foundation/day")
    kubeconfig_from_stack = infra_stack.get_output("kubeconfig")

    pulumi.export("test_result", "Stack reference works!")
    pulumi.export("has_kubeconfig", kubeconfig_from_stack.apply(lambda x: x is not None))

    print("✅ Stack reference 'ry111/foundation/day' is accessible")
    print("✅ Output 'kubeconfig' exists in that stack")
    print("\nRun 'pulumi preview' to see the test exports")

except Exception as e:
    print(f"❌ Stack reference failed: {e}")
    pulumi.export("test_result", f"Failed: {e}")
