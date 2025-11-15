"""
Pulumi program to create EKS cluster with spot instances.

This creates:
- VPC with public/private subnets
- EKS cluster with OIDC provider
- Managed node group using spot instances (t3.small)
- ALB controller using Helm

Supports Day and Dusk services via stack configuration.
Note: Dawn cluster is managed manually via eksctl scripts.
"""

import pulumi
import pulumi_aws as aws
import pulumi_eks as eks
import pulumi_kubernetes as k8s

# Configuration
config = pulumi.Config()
aws_config = pulumi.Config("aws")
region = aws_config.get("region") or "us-east-1"

# Service-specific configuration
service_name = config.require("service_name")  # e.g., "dawn", "day", "dusk"
cluster_name = config.get("cluster_name") or f"{service_name}-cluster"
vpc_cidr = config.get("vpc_cidr") or "10.0.0.0/16"  # Different for each service
min_nodes = config.get_int("min_nodes") or 1
max_nodes = config.get_int("max_nodes") or 3
desired_nodes = config.get_int("desired_nodes") or 2
instance_type = config.get("instance_type") or "t3.small"
use_spot = config.get_bool("use_spot") or True

project_name = pulumi.get_project()
stack_name = pulumi.get_stack()

# Tags for all resources
common_tags = {
    "Project": project_name,
    "Stack": stack_name,
    "ManagedBy": "Pulumi",
    "Service": service_name.capitalize(),
}

# Create VPC for EKS cluster
vpc = aws.ec2.Vpc(
    f"{service_name}-vpc",
    cidr_block=vpc_cidr,
    enable_dns_hostnames=True,
    enable_dns_support=True,
    tags={**common_tags, "Name": f"{service_name}-vpc-{stack_name}"},
)

# Internet Gateway
igw = aws.ec2.InternetGateway(
    f"{service_name}-igw",
    vpc_id=vpc.id,
    tags={**common_tags, "Name": f"{service_name}-igw-{stack_name}"},
)

# Calculate subnet CIDRs from VPC CIDR
# For 10.x.0.0/16, subnets will be 10.x.1.0/24 and 10.x.2.0/24
vpc_cidr_parts = vpc_cidr.split('.')
subnet_1_cidr = f"{vpc_cidr_parts[0]}.{vpc_cidr_parts[1]}.1.0/24"
subnet_2_cidr = f"{vpc_cidr_parts[0]}.{vpc_cidr_parts[1]}.2.0/24"

# Public subnets for ALB
public_subnet_1 = aws.ec2.Subnet(
    f"{service_name}-public-subnet-1",
    vpc_id=vpc.id,
    cidr_block=subnet_1_cidr,
    availability_zone=f"{region}a",
    map_public_ip_on_launch=True,
    tags={
        **common_tags,
        "Name": f"{service_name}-public-subnet-1-{stack_name}",
        "kubernetes.io/role/elb": "1",  # Required for ALB
    },
)

public_subnet_2 = aws.ec2.Subnet(
    f"{service_name}-public-subnet-2",
    vpc_id=vpc.id,
    cidr_block=subnet_2_cidr,
    availability_zone=f"{region}b",
    map_public_ip_on_launch=True,
    tags={
        **common_tags,
        "Name": f"{service_name}-public-subnet-2-{stack_name}",
        "kubernetes.io/role/elb": "1",
    },
)

# Route table for public subnets
public_route_table = aws.ec2.RouteTable(
    f"{service_name}-public-rt",
    vpc_id=vpc.id,
    routes=[
        aws.ec2.RouteTableRouteArgs(
            cidr_block="0.0.0.0/0",
            gateway_id=igw.id,
        )
    ],
    tags={**common_tags, "Name": f"{service_name}-public-rt-{stack_name}"},
)

public_rt_association_1 = aws.ec2.RouteTableAssociation(
    f"{service_name}-public-rt-assoc-1",
    subnet_id=public_subnet_1.id,
    route_table_id=public_route_table.id,
)

public_rt_association_2 = aws.ec2.RouteTableAssociation(
    f"{service_name}-public-rt-assoc-2",
    subnet_id=public_subnet_2.id,
    route_table_id=public_route_table.id,
)

# Create EKS cluster
cluster_args = {
    "vpc_id": vpc.id,
    "subnet_ids": [public_subnet_1.id, public_subnet_2.id],
    "instance_type": instance_type,
    "desired_capacity": desired_nodes,
    "min_size": min_nodes,
    "max_size": max_nodes,
    "node_associate_public_ip_address": True,
    "create_oidc_provider": True,  # Required for ALB controller
    "tags": {**common_tags, "Name": cluster_name},
}

# Add spot price if using spot instances
if use_spot:
    cluster_args["spot_price"] = "0.0104"  # t3.small spot price (~70% savings)

cluster = eks.Cluster(
    f"{service_name}-cluster",
    **cluster_args,
)

# Create Kubernetes provider using the cluster's kubeconfig
k8s_provider = k8s.Provider(
    f"{service_name}-k8s",
    kubeconfig=cluster.kubeconfig,
)

# Get the OIDC provider URL and ARN for ALB controller IAM role
oidc_provider_url = cluster.core.oidc_provider.url
oidc_provider_arn = cluster.core.oidc_provider.arn

# Create IAM policy for ALB controller
# This policy allows the controller to manage ALBs
alb_policy_doc = aws.iam.get_policy_document(
    statements=[
        # EC2 permissions
        aws.iam.GetPolicyDocumentStatementArgs(
            effect="Allow",
            actions=[
                "ec2:DescribeAccountAttributes",
                "ec2:DescribeAddresses",
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeInternetGateways",
                "ec2:DescribeVpcs",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeInstances",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeTags",
                "ec2:CreateTags",
                "ec2:DeleteTags",
                "ec2:CreateSecurityGroup",
                "ec2:DeleteSecurityGroup",
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress",
            ],
            resources=["*"],
        ),
        # ELB permissions
        aws.iam.GetPolicyDocumentStatementArgs(
            effect="Allow",
            actions=[
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:DescribeLoadBalancerAttributes",
                "elasticloadbalancing:DescribeListeners",
                "elasticloadbalancing:DescribeListenerCertificates",
                "elasticloadbalancing:DescribeRules",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DescribeTargetGroupAttributes",
                "elasticloadbalancing:DescribeTargetHealth",
                "elasticloadbalancing:DescribeTags",
                "elasticloadbalancing:CreateLoadBalancer",
                "elasticloadbalancing:CreateListener",
                "elasticloadbalancing:CreateRule",
                "elasticloadbalancing:CreateTargetGroup",
                "elasticloadbalancing:ModifyLoadBalancerAttributes",
                "elasticloadbalancing:ModifyTargetGroupAttributes",
                "elasticloadbalancing:RegisterTargets",
                "elasticloadbalancing:DeregisterTargets",
                "elasticloadbalancing:DeleteLoadBalancer",
                "elasticloadbalancing:DeleteListener",
                "elasticloadbalancing:DeleteRule",
                "elasticloadbalancing:DeleteTargetGroup",
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:RemoveTags",
            ],
            resources=["*"],
        ),
        # IAM permissions
        aws.iam.GetPolicyDocumentStatementArgs(
            effect="Allow",
            actions=[
                "iam:CreateServiceLinkedRole",
                "iam:GetServerCertificate",
                "iam:ListServerCertificates",
            ],
            resources=["*"],
        ),
    ]
)

alb_policy = aws.iam.Policy(
    f"{service_name}-alb-controller-policy",
    policy=alb_policy_doc.json,
    tags=common_tags,
)

# Create IAM role for ALB controller with IRSA (IAM Roles for Service Accounts)
alb_role_assume_policy = pulumi.Output.all(oidc_provider_url, oidc_provider_arn).apply(
    lambda args: aws.iam.get_policy_document(
        statements=[
            aws.iam.GetPolicyDocumentStatementArgs(
                effect="Allow",
                principals=[
                    aws.iam.GetPolicyDocumentStatementPrincipalArgs(
                        type="Federated",
                        identifiers=[args[1]],
                    )
                ],
                actions=["sts:AssumeRoleWithWebIdentity"],
                conditions=[
                    aws.iam.GetPolicyDocumentStatementConditionArgs(
                        test="StringEquals",
                        variable=f"{args[0].replace('https://', '')}:sub",
                        values=["system:serviceaccount:kube-system:aws-load-balancer-controller"],
                    )
                ],
            )
        ]
    ).json
)

alb_role = aws.iam.Role(
    f"{service_name}-alb-controller-role",
    assume_role_policy=alb_role_assume_policy,
    tags=common_tags,
)

alb_role_policy_attachment = aws.iam.RolePolicyAttachment(
    f"{service_name}-alb-controller-policy-attachment",
    role=alb_role.name,
    policy_arn=alb_policy.arn,
)

# Create service account for ALB controller
alb_service_account = k8s.core.v1.ServiceAccount(
    "aws-load-balancer-controller",
    metadata=k8s.meta.v1.ObjectMetaArgs(
        name="aws-load-balancer-controller",
        namespace="kube-system",
        annotations={
            "eks.amazonaws.com/role-arn": alb_role.arn,
        },
    ),
    opts=pulumi.ResourceOptions(
        provider=k8s_provider,
        depends_on=[cluster],
    ),
)

# Install ALB controller using Helm
alb_controller = k8s.helm.v3.Release(
    "aws-load-balancer-controller",
    k8s.helm.v3.ReleaseArgs(
        chart="aws-load-balancer-controller",
        repository_opts=k8s.helm.v3.RepositoryOptsArgs(
            repo="https://aws.github.io/eks-charts",
        ),
        namespace="kube-system",
        values={
            "clusterName": cluster.eks_cluster.name,
            "serviceAccount": {
                "create": False,
                "name": "aws-load-balancer-controller",
            },
            "region": region,
            "vpcId": vpc.id,
        },
    ),
    opts=pulumi.ResourceOptions(
        provider=k8s_provider,
        depends_on=[alb_service_account, alb_role_policy_attachment],
    ),
)

# Export important values
pulumi.export("cluster_name", cluster.eks_cluster.name)
pulumi.export("cluster_endpoint", cluster.eks_cluster.endpoint)
pulumi.export("kubeconfig", cluster.kubeconfig)
pulumi.export("vpc_id", vpc.id)
pulumi.export("oidc_provider_arn", oidc_provider_arn)
pulumi.export("oidc_provider_url", oidc_provider_url)
pulumi.export("region", region)
pulumi.export("alb_controller_role_arn", alb_role.arn)
