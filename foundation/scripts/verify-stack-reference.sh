#!/bin/bash
# Verify stack reference connectivity between infrastructure and application stacks
# Usage: ./verify-stack-reference.sh [infrastructure-stack] [application-stack]

set -e

INFRA_STACK="${1:-day}"
APP_STACK="${2:-production}"
INFRA_PROJECT="service-infrastructure"
APP_PROJECT="day-service-app"

echo "🔍 Verifying Stack Reference Configuration"
echo "==========================================="
echo ""

# Step 1: Check infrastructure stack exists and has outputs
echo "📦 Step 1: Checking infrastructure stack '${INFRA_PROJECT}/${INFRA_STACK}'..."
cd "$(dirname "$0")/../../provisioning/pulumi"

if ! pulumi stack ls | grep -q "${INFRA_STACK}"; then
    echo "❌ Infrastructure stack '${INFRA_STACK}' not found!"
    echo "   Available stacks:"
    pulumi stack ls
    exit 1
fi

pulumi stack select "${INFRA_STACK}" &>/dev/null
echo "   ✅ Stack exists"

# Step 2: Check kubeconfig output exists
echo "📤 Step 2: Checking 'kubeconfig' output..."
if ! pulumi stack output kubeconfig &>/dev/null; then
    echo "❌ 'kubeconfig' output not found!"
    echo "   Available outputs:"
    pulumi stack output
    echo ""
    echo "   💡 Deploy the infrastructure stack first:"
    echo "      cd foundation/provisioning/pulumi"
    echo "      pulumi up --stack ${INFRA_STACK}"
    exit 1
fi
echo "   ✅ 'kubeconfig' output exists"

# Step 3: Determine backend type and correct stack reference format
echo "🔗 Step 3: Determining correct stack reference format..."
PULUMI_USER=$(pulumi whoami 2>/dev/null || echo "local")

if [[ "${PULUMI_USER}" == file://* ]]; then
    STACK_REF="${INFRA_PROJECT}/${INFRA_STACK}"
    echo "   📁 Using local backend"
else
    STACK_REF="${PULUMI_USER}/${INFRA_PROJECT}/${INFRA_STACK}"
    echo "   ☁️  Using Pulumi Cloud (${PULUMI_USER})"
fi
echo "   Stack reference format: ${STACK_REF}"

# Step 4: Test stack reference from application directory
echo "🎯 Step 4: Testing stack reference from application stack..."
cd ../../gitops/day

if ! pulumi stack ls | grep -q "${APP_STACK}"; then
    echo "❌ Application stack '${APP_STACK}' not found!"
    echo "   Available stacks:"
    pulumi stack ls
    exit 1
fi

pulumi stack select "${APP_STACK}" &>/dev/null

# Try to read the output using stack reference
if pulumi stack output kubeconfig --stack "${STACK_REF}" &>/dev/null; then
    echo "   ✅ Stack reference works!"
else
    echo "❌ Cannot read from stack reference '${STACK_REF}'"
    echo "   Try:"
    echo "     pulumi stack output kubeconfig --stack ${STACK_REF}"
    exit 1
fi

# Step 5: Check Pulumi config file
echo "📝 Step 5: Checking Pulumi.${APP_STACK}.yaml configuration..."
CONFIG_FILE="Pulumi.${APP_STACK}.yaml"

if ! test -f "${CONFIG_FILE}"; then
    echo "❌ ${CONFIG_FILE} not found!"
    exit 1
fi

if grep -q "fn::stackReference" "${CONFIG_FILE}"; then
    echo "   ✅ fn::stackReference is configured"

    # Extract configured stack name
    CONFIGURED_REF=$(grep -A 1 "fn::stackReference" "${CONFIG_FILE}" | grep "name:" | awk '{print $2}')

    if [[ "${CONFIGURED_REF}" == "${STACK_REF}" ]]; then
        echo "   ✅ Stack reference format matches: ${CONFIGURED_REF}"
    else
        echo "   ⚠️  Stack reference mismatch!"
        echo "      Configured: ${CONFIGURED_REF}"
        echo "      Should be:  ${STACK_REF}"
        echo ""
        echo "   💡 Update ${CONFIG_FILE} to use:"
        echo "      fn::stackReference:"
        echo "        name: ${STACK_REF}"
        echo "        output: kubeconfig"
    fi
else
    echo "   ⚠️  fn::stackReference is commented out"
    echo ""
    echo "   💡 To enable stack reference, uncomment in ${CONFIG_FILE}:"
    echo "      kubernetes:kubeconfig:"
    echo "        fn::stackReference:"
    echo "          name: ${STACK_REF}"
    echo "          output: kubeconfig"
fi

echo ""
echo "✅ Verification Complete!"
echo ""
echo "To use stack reference:"
echo "  1. Uncomment fn::stackReference in ${CONFIG_FILE}"
echo "  2. Use: name: ${STACK_REF}"
echo "  3. Run: pulumi preview --stack ${APP_STACK}"
