# GitHub Actions IAM Policy for Pulumi

This document describes the IAM permissions needed for a GitHub Actions user to run `pulumi up` with our infrastructure code.

## Overview

The Pulumi code creates:
- VPC with subnets, internet gateway, and route tables
- EKS cluster with OIDC provider
- Managed node groups (with spot instances)
- IAM roles and policies for EKS and ALB controller
- Kubernetes resources (ServiceAccount, Helm charts)

## Required IAM Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2VPCNetworking",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc",
        "ec2:DeleteVpc",
        "ec2:DescribeVpcs",
        "ec2:ModifyVpcAttribute",
        "ec2:CreateSubnet",
        "ec2:DeleteSubnet",
        "ec2:DescribeSubnets",
        "ec2:ModifySubnetAttribute",
        "ec2:CreateInternetGateway",
        "ec2:DeleteInternetGateway",
        "ec2:AttachInternetGateway",
        "ec2:DetachInternetGateway",
        "ec2:DescribeInternetGateways",
        "ec2:CreateRouteTable",
        "ec2:DeleteRouteTable",
        "ec2:DescribeRouteTables",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:AssociateRouteTable",
        "ec2:DisassociateRouteTable",
        "ec2:ReplaceRouteTableAssociation",
        "ec2:CreateNatGateway",
        "ec2:DeleteNatGateway",
        "ec2:DescribeNatGateways",
        "ec2:AllocateAddress",
        "ec2:ReleaseAddress",
        "ec2:DescribeAddresses",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSecurityGroupRules",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:DescribeTags",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeAccountAttributes",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeInstances",
        "ec2:DescribeImages"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EKSClusterManagement",
      "Effect": "Allow",
      "Action": [
        "eks:CreateCluster",
        "eks:DeleteCluster",
        "eks:DescribeCluster",
        "eks:ListClusters",
        "eks:UpdateClusterConfig",
        "eks:UpdateClusterVersion",
        "eks:TagResource",
        "eks:UntagResource",
        "eks:ListTagsForResource",
        "eks:CreateNodegroup",
        "eks:DeleteNodegroup",
        "eks:DescribeNodegroup",
        "eks:UpdateNodegroupConfig",
        "eks:UpdateNodegroupVersion",
        "eks:ListNodegroups",
        "eks:CreateAddon",
        "eks:DeleteAddon",
        "eks:DescribeAddon",
        "eks:UpdateAddon",
        "eks:ListAddons",
        "eks:AssociateIdentityProviderConfig",
        "eks:DisassociateIdentityProviderConfig",
        "eks:DescribeIdentityProviderConfig"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMRoleAndPolicyManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:ListRoles",
        "iam:UpdateRole",
        "iam:UpdateAssumeRolePolicy",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:ListRoleTags",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicies",
        "iam:ListPolicyVersions",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:TagPolicy",
        "iam:UntagPolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListRolePolicies",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:PassRole",
        "iam:CreateOpenIDConnectProvider",
        "iam:DeleteOpenIDConnectProvider",
        "iam:GetOpenIDConnectProvider",
        "iam:TagOpenIDConnectProvider",
        "iam:UntagOpenIDConnectProvider",
        "iam:ListOpenIDConnectProviders",
        "iam:CreateServiceLinkedRole",
        "iam:GetServerCertificate",
        "iam:ListServerCertificates"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AutoScalingForNodeGroups",
      "Effect": "Allow",
      "Action": [
        "autoscaling:CreateAutoScalingGroup",
        "autoscaling:DeleteAutoScalingGroup",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:CreateOrUpdateTags",
        "autoscaling:DeleteTags",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2LaunchTemplates",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateLaunchTemplate",
        "ec2:DeleteLaunchTemplate",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:CreateLaunchTemplateVersion",
        "ec2:DeleteLaunchTemplateVersions",
        "ec2:ModifyLaunchTemplate"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudFormationForPulumi",
      "Effect": "Allow",
      "Action": [
        "cloudformation:CreateStack",
        "cloudformation:DeleteStack",
        "cloudformation:DescribeStacks",
        "cloudformation:DescribeStackEvents",
        "cloudformation:DescribeStackResources",
        "cloudformation:GetTemplate",
        "cloudformation:UpdateStack",
        "cloudformation:ListStacks",
        "cloudformation:ListStackResources",
        "cloudformation:ValidateTemplate"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ELBForALBControllerPolicy",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeLoadBalancerAttributes",
        "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:DescribeListenerCertificates",
        "elasticloadbalancing:DescribeRules",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetGroupAttributes",
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:DescribeTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "LogsForEKS",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:ListTagsLogGroup",
        "logs:PutRetentionPolicy",
        "logs:TagLogGroup",
        "logs:UntagLogGroup"
      ],
      "Resource": "*"
    },
    {
      "Sid": "STSForAssumeRole",
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

## Setup Instructions

### Option 1: Create IAM User (Recommended for GitHub Actions)

1. **Create IAM User**:
   ```bash
   aws iam create-user --user-name github-actions-pulumi
   ```

2. **Create and attach policy**:
   ```bash
   # Save the JSON policy above to a file: pulumi-github-actions-policy.json
   aws iam create-policy \
     --policy-name PulumiGitHubActionsPolicy \
     --policy-document file://pulumi-github-actions-policy.json

   # Attach to user
   aws iam attach-user-policy \
     --user-name github-actions-pulumi \
     --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/PulumiGitHubActionsPolicy
   ```

3. **Create access keys**:
   ```bash
   aws iam create-access-key --user-name github-actions-pulumi
   ```

4. **Add to GitHub Secrets**:
   - Go to your repository → Settings → Secrets and variables → Actions
   - Add secrets:
     - `AWS_ACCESS_KEY_ID`: From step 3
     - `AWS_SECRET_ACCESS_KEY`: From step 3
     - `AWS_REGION`: `us-east-1`
     - `PULUMI_ACCESS_TOKEN`: From Pulumi Cloud (https://app.pulumi.com)

### Option 2: Use OIDC (More Secure, No Long-lived Credentials)

If you want to avoid long-lived credentials, you can use GitHub's OIDC provider with AWS:

1. **Create OIDC provider in AWS**:
   ```bash
   aws iam create-open-id-connect-provider \
     --url https://token.actions.githubusercontent.com \
     --client-id-list sts.amazonaws.com \
     --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
   ```

2. **Create IAM role with trust policy**:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": {
             "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
           },
           "StringLike": {
             "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_ORG/YOUR_REPO:*"
           }
         }
       }
     ]
   }
   ```

3. **Attach the Pulumi policy to this role**

4. **Update GitHub Actions workflow** to use OIDC:
   ```yaml
   permissions:
     id-token: write
     contents: read

   - name: Configure AWS Credentials
     uses: aws-actions/configure-aws-credentials@v4
     with:
       role-to-assume: arn:aws:iam::YOUR_ACCOUNT_ID:role/github-actions-pulumi-role
       aws-region: us-east-1
   ```

## Security Considerations

### Current Policy Scope
The policy above uses `"Resource": "*"` for simplicity. For production, consider:

1. **Limit by region**:
   ```json
   "Condition": {
     "StringEquals": {
       "aws:RequestedRegion": "us-east-1"
     }
   }
   ```

2. **Limit by tags** (resource-based):
   ```json
   "Condition": {
     "StringEquals": {
       "aws:ResourceTag/ManagedBy": "Pulumi",
       "aws:ResourceTag/Project": "service-infrastructure"
     }
   }
   ```

3. **Separate policies** for different stacks (day vs dusk)

### Minimum Permissions Approach

If you want to start with minimal permissions and add as needed:

1. Start with the policy above
2. Run `pulumi preview` or `pulumi up`
3. Check CloudTrail for `AccessDenied` errors
4. Add only the specific permissions that failed
5. Iterate until successful

### Monitoring

Set up CloudTrail to monitor API calls:
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=github-actions-pulumi \
  --max-results 50
```

## Existing Workflows

Your current workflows (`.github/workflows/pulumi-preview.yml` and `pulumi-up.yml`) already expect these secrets:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `PULUMI_ACCESS_TOKEN`

Make sure these are configured in your GitHub repository secrets before running the workflows.

## Testing

To test the permissions locally before setting up GitHub Actions:

1. Create a test IAM user with the policy
2. Configure AWS CLI with those credentials
3. Run:
   ```bash
   cd foundation/pulumi
   pulumi preview --stack day
   ```

If the preview succeeds, the permissions are sufficient for GitHub Actions.

## Common Issues

### "AccessDenied" for PassRole
If you see errors about `iam:PassRole`, ensure the policy includes:
```json
"iam:PassRole"
```
This is needed when creating EKS clusters and node groups.

### "AccessDenied" for CreateOpenIDConnectProvider
The OIDC provider creation requires:
```json
"iam:CreateOpenIDConnectProvider"
```

### CloudFormation permissions
Pulumi may use CloudFormation under the hood, so ensure CloudFormation permissions are included.

## Cost Implications

This policy allows creating resources that incur costs:
- EKS clusters: ~$0.10/hour per cluster
- EC2 spot instances: ~$0.0062/hour for t3.small (varies)
- NAT Gateways: ~$0.045/hour + data transfer
- Elastic IPs: Free when attached, $0.005/hour when not

Consider adding budget alerts in AWS Budgets.
