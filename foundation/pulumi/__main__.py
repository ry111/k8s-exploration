"""
Pulumi program to create Dawn EKS cluster with spot instances.

This creates:
- VPC with public/private subnets
- EKS cluster with OIDC provider
- Managed node group using spot instances (t3.small)
- ALB controller using Helm
"""

import pulumi
import pulumi_aws as aws
import pulumi_eks as eks
import pulumi_kubernetes as k8s

# Configuration
config = pulumi.Config()
aws_config = pulumi.Config("aws")
region = aws_config.get("region") or "us-east-1"

project_name = pulumi.get_project()
stack_name = pulumi.get_stack()

# Tags for all resources
common_tags = {
    "Project": project_name,
    "Stack": stack_name,
    "ManagedBy": "Pulumi",
    "Service": "Dawn",
}

# Create VPC for EKS cluster
vpc = aws.ec2.Vpc(
    "dawn-vpc",
    cidr_block="10.0.0.0/16",
    enable_dns_hostnames=True,
    enable_dns_support=True,
    tags={**common_tags, "Name": f"dawn-vpc-{stack_name}"},
)

# Internet Gateway
igw = aws.ec2.InternetGateway(
    "dawn-igw",
    vpc_id=vpc.id,
    tags={**common_tags, "Name": f"dawn-igw-{stack_name}"},
)

# Public subnets for ALB
public_subnet_1 = aws.ec2.Subnet(
    "dawn-public-subnet-1",
    vpc_id=vpc.id,
    cidr_block="10.0.1.0/24",
    availability_zone=f"{region}a",
    map_public_ip_on_launch=True,
    tags={
        **common_tags,
        "Name": f"dawn-public-subnet-1-{stack_name}",
        "kubernetes.io/role/elb": "1",  # Required for ALB
    },
)

public_subnet_2 = aws.ec2.Subnet(
    "dawn-public-subnet-2",
    vpc_id=vpc.id,
    cidr_block="10.0.2.0/24",
    availability_zone=f"{region}b",
    map_public_ip_on_launch=True,
    tags={
        **common_tags,
        "Name": f"dawn-public-subnet-2-{stack_name}",
        "kubernetes.io/role/elb": "1",
    },
)

# Route table for public subnets
public_route_table = aws.ec2.RouteTable(
    "dawn-public-rt",
    vpc_id=vpc.id,
    routes=[
        aws.ec2.RouteTableRouteArgs(
            cidr_block="0.0.0.0/0",
            gateway_id=igw.id,
        )
    ],
    tags={**common_tags, "Name": f"dawn-public-rt-{stack_name}"},
)

public_rt_association_1 = aws.ec2.RouteTableAssociation(
    "dawn-public-rt-assoc-1",
    subnet_id=public_subnet_1.id,
    route_table_id=public_route_table.id,
)

public_rt_association_2 = aws.ec2.RouteTableAssociation(
    "dawn-public-rt-assoc-2",
    subnet_id=public_subnet_2.id,
    route_table_id=public_route_table.id,
)

# Create EKS cluster
cluster = eks.Cluster(
    "dawn-cluster",
    vpc_id=vpc.id,
    subnet_ids=[public_subnet_1.id, public_subnet_2.id],
    instance_type="t3.small",
    desired_capacity=2,
    min_size=1,
    max_size=3,
    node_associate_public_ip_address=True,
    create_oidc_provider=True,  # Required for ALB controller
    # Use spot instances for cost savings
    spot_price="0.0104",  # t3.small spot price (~70% savings)
    tags={**common_tags, "Name": f"dawn-cluster-{stack_name}"},
)

# Create Kubernetes provider using the cluster's kubeconfig
k8s_provider = k8s.Provider(
    "dawn-k8s",
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
    "dawn-alb-controller-policy",
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
    "dawn-alb-controller-role",
    assume_role_policy=alb_role_assume_policy,
    tags=common_tags,
)

alb_role_policy_attachment = aws.iam.RolePolicyAttachment(
    "dawn-alb-controller-policy-attachment",
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
