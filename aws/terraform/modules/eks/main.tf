terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

locals {
  tags = var.tags
}

# Speaks to the cluster's API server directly (no kubeconfig), authenticating
# via `aws eks get-token` (the same exec credential plugin kubectl uses). This
# runs with the credentials of whoever executes terraform, who is the cluster
# creator and therefore has cluster-admin access. Used to manage the aws-auth
# ConfigMap (see kubernetes_config_map_v1.aws_auth) without a shell heredoc.
provider "kubernetes" {
  host                   = aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.this.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.this.name, "--region", var.region]
  }
}

# Cluster security group: protects the (private) API endpoint.
# Cross-SG rules use standalone ingress_rule resources (inline ingress blocks
# on both SGs would create a creation cycle).
resource "aws_security_group" "cluster" {
  name_prefix = "${var.name}-cluster-"
  description = "EKS cluster API endpoint"
  vpc_id      = var.vpc_id

  # kubectl/helm from outside the VPC (provisioner, bootstrap, CI/CD).
  # Dev: open to the world; auth is enforced by IAM. Restrict to specific
  # source CIDRs before prod.
  ingress {
    description = "EKS API (443) to kubectl/CI"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "allow all outbound (API to nodes, pods)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${var.name}-cluster" })

  lifecycle {
    ignore_changes = [name]
  }
}

# Node security group. Workers have no public IPs: internet egress goes
# through the NAT gateway, inbound is the cluster API, inter-node traffic,
# and the ALB (source ranges of the VPC) hitting pod ports directly
# (target-type=ip).
resource "aws_security_group" "node" {
  name_prefix = "${var.name}-node-"
  description = "EKS worker nodes"
  vpc_id      = var.vpc_id

  ingress {
    description = "in-VPC traffic (ALB to pod IPs on app ports, inter-node)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "allow all outbound (NAT, cluster API, inter-node)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${var.name}-node" })

  lifecycle {
    ignore_changes = [name]
  }
}

resource "aws_eks_cluster" "this" {
  name     = var.name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = var.private_subnet_ids
    # Public API access so kubectl/helm (the aws-auth provisioner,
    # bootstrap/setup-eks.sh, and the CD workflow) can reach the control
    # plane from outside the VPC. Auth is still enforced by IAM (OIDC/IRSA);
    # restrict the cluster SG ingress before prod.
    endpoint_public_access  = true
    endpoint_private_access = true
    security_group_ids      = [aws_security_group.cluster.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_amazon,
    aws_security_group.node,
  ]

  # Set up a kubeconfig context for the cluster so the operator can use
  # kubectl right after `terraform apply`. The aws-auth ConfigMap itself is
  # managed by kubernetes_config_map_v1.aws_auth (EKS auto-creates it with the
  # node role when the managed node group is created; we add the CD role).
  # Uses var.name (not aws_eks_cluster.this.name): a provisioner must not
  # reference the resource it is attached to - that forms a self-cycle.
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${var.name} --alias ${var.name} --region ${var.region}"
  }

  tags = merge(local.tags, { Name = var.name })
}

# addon_version omitted: the provider picks the latest version compatible
# with the cluster's Kubernetes version.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "coredns"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "kube-proxy"
}

# ----- cluster role -----

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name_prefix        = "${var.name}-cluster-"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json

  tags = local.tags
}

data "aws_iam_policy" "cluster_managed" {
  arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_amazon" {
  role       = aws_iam_role.cluster.name
  policy_arn = data.aws_iam_policy.cluster_managed.arn
}

# ----- worker nodes -----

data "aws_iam_policy_document" "worker_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name_prefix        = "${var.name}-node-"
  assume_role_policy = data.aws_iam_policy_document.worker_assume.json

  tags = local.tags
}

data "aws_iam_policy" "node_managed" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly",
  ])

  arn = "arn:aws:iam::aws:policy/${each.value}"
}

resource "aws_iam_role_policy_attachment" "node_managed" {
  for_each = data.aws_iam_policy.node_managed

  role       = aws_iam_role.node.name
  policy_arn = each.value.arn
}

resource "aws_iam_instance_profile" "node" {
  name_prefix = "${var.name}-node-"
  role        = aws_iam_role.node.name

  tags = local.tags
}

resource "aws_eks_node_group" "this" {
  node_group_name = "${var.name}-workers"
  cluster_name    = aws_eks_cluster.this.name
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.worker_instance_types
  scaling_config {
    min_size     = var.worker_min_size
    max_size     = var.worker_max_size
    desired_size = var.worker_desired_size
  }
  disk_size = var.worker_disk_size_gb

  update_config {
    max_unavailable = 1
  }

  labels = merge(local.tags)

  tags = merge(local.tags, { Name = "${var.name}-workers" })

  depends_on = [aws_iam_role_policy_attachment.node_managed]
}

# ----- GitHub Actions OIDC (CD) -----

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # These MUST be the SHA-1 of the certs in GitHub's JWKS (the keys that sign
  # the OIDC tokens), NOT the TLS server-certificate chain of the endpoint.
  # GitHub rotates these signing certs, so refresh periodically. To recompute:
  #   fetch https://token.actions.githubusercontent.com/.well-known/openid-configuration
  #   -> jwks_uri -> for each key, sha1(base64decode(key.x5c[0])).hex
  # Verified 2026-09-14 against the live JWKS.
  thumbprint_list = ["38e9b30b3a023a1b72309921a69a42fcc496c42c", "4f3e9ad8c9a6f5eb3173006f4fa630e28f43dce9", "ca435a638a8cfed6b89364e064e08460b91c6250"]

  tags = local.tags
}

data "aws_iam_policy_document" "cd_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Default (empty) allows any ref on the repo; prod passes explicit
      # ref:heads/main + ref:heads/dev patterns to pin the CD identity.
      #
      # Match BOTH sub formats:
      #   classic:     repo:owner/name:ref:refs/heads/...
      #   immutable:   repo:owner@<org-id>/name@<repo-id>:ref:refs/heads/...
      # GitHub switched new repos (created on/after 2026-07-15) to the
      # immutable-ID format, which a classic-only pattern never matches.
      # The immutable pattern is only added when both numeric IDs are set.
      values = length(var.cd_oidc_sub) > 0 ? var.cd_oidc_sub : concat(
        ["repo:${var.github_repo}:*"],
        (var.github_owner_id != "" && var.github_repo_id != "") ? [
          "repo:${split("/", var.github_repo)[0]}@${var.github_owner_id}/${split("/", var.github_repo)[1]}@${var.github_repo_id}:*",
        ] : [],
      )
    }
  }
}

resource "aws_iam_role" "cd" {
  name_prefix        = "${var.name}-cd-"
  assume_role_policy = data.aws_iam_policy_document.cd_assume.json

  tags = local.tags
}

data "aws_iam_policy_document" "cd" {
  statement {
    effect = "Allow"
    actions = [
      "sts:TagSession",
      "eks:DescribeCluster",
      "eks:AccessKubernetesCluster",
    ]
    resources = [aws_eks_cluster.this.arn]
  }

  # `aws eks get-token` (the kubeconfig exec credential plugin) mints a
  # Kubernetes token by calling sts:GetWebIdentityToken. Without it, kubectl
  # fails with "the server has asked for the client to provide credentials".
  # TODO(harden): scope sts:IdentityTokenAudience to this cluster's issuer.
  statement {
    effect    = "Allow"
    actions   = ["sts:GetWebIdentityToken"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "rds:DescribeDBInstances",
    ]
    # Scoped to this env's DB identifier (<name>-db, created by the rds module).
    # The RDS instance ARN uses the "db:" resource type (not "dbinstance:").
    # Wildcards only for region/account so the eks module stays decoupled from
    # the rds module (a direct ARN reference would be a module cycle).
    resources = ["arn:aws:rds:*:*:db:${var.name}-db"]
  }

  statement {
    effect = "Allow"
    actions = [
      "elbv2:DescribeLoadBalancers",
      "elbv2:DescribeTargetGroups",
      "elbv2:DescribeTargetGroupAttributes",
      "elbv2:DescribeTags",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
    ]
    # Non-secret config (the image API URL) the CD workflow renders into the
    # env file. Wildcard region/account + the template/ path prefix keeps the
    # eks module decoupled from the secrets module (a direct ARN reference
    # would be a module cycle). Read-only.
    resources = ["arn:aws:ssm:*:*:parameter/template/*"]
  }
}

resource "aws_iam_role_policy" "cd" {
  role   = aws_iam_role.cd.id
  policy = data.aws_iam_policy_document.cd.json
}

# ----- load balancer controller (IRSA) -----
# The controller creates and manages the ALB from the Ingress in
# k8s/ingress.yaml. The ALB (and its k8s-* security groups) are NOT in the
# Terraform state - never run `terraform destroy` directly; use
# bootstrap/teardown.sh, which deletes the k8s resources first so the
# controller can remove the ALB (otherwise the cluster is destroyed with the
# ALB still alive and its ENIs/EIPs block the subnets/VPC).

# OIDC provider for the cluster issuer (required for IRSA). The EKS OIDC
# endpoint serves an Amazon-issued certificate; the thumbprints below are the
# top intermediate CA (Amazon RSA 2048 M01) and root (Amazon Root CA 1) of
# that endpoint, verified 2026-08-27 via the AWS-documented command:
#   echo | openssl s_client -servername oidc.eks.<region>.amazonaws.com -showcerts \
#     -connect oidc.eks.<region>.amazonaws.com:443 2>/dev/null \
#     | awk '/-----BEGIN CERTIFICATE-----/{cert=""} {cert=cert $0 "\n"} \
#       /-----END CERTIFICATE-----/{last_cert=cert} END{printf "%s", last_cert}' \
#     | openssl x509 -fingerprint -noout | sed 's/://g' | awk -F= '{print tolower($2)}'
# The root value is the one STS actually validates; a single typo there
# silently breaks every AssumeRoleWithWebIdentity (generic AccessDenied).
resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["2ad974a775f73cbdbbd8f5ac3a49255fa8fb1f8c", "06b25927c42a721631c1efd9431e648fa62e1e39"]

  tags = local.tags
}

data "aws_iam_policy_document" "alb_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name_prefix        = "${var.name}-alb-controller-"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume.json

  tags = local.tags
}

data "aws_iam_policy_document" "alb_controller" {
  statement {
    effect = "Allow"
    actions = [
      "acm:DescribeCertificate",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "iam:CreateServiceLinkedRole",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeRouteTables",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeAddresses",
      "ec2:DescribeNetworkAcls",
      "ec2:DescribeTags",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DeleteSecurityGroup",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeListenerAttributes",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetWebAcl",
    ]
    resources = ["*"]
  }
}

# Map the CD role into the legacy aws-auth ConfigMap so `aws eks get-token`
# (the kubectl exec credential plugin used by the CD workflow) can
# authenticate. This cluster uses the CONFIG_MAP auth mode, so access entries
# are not available; the ConfigMap is the only mechanism.
#
# EKS auto-creates the aws-auth ConfigMap (with the node role) when the
# managed node group is created, so this resource runs after the node group
# and adds the CD role on top. Managed via the kubernetes provider (not a
# local-exec heredoc, which does not work under the Windows cmd.exe shell).
resource "kubernetes_config_map_v1" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = templatefile("${path.module}/templates/aws-auth.tpl", {
      node_role_arn = aws_iam_role.node.arn
      cd_role_arn   = aws_iam_role.cd.arn
      cluster_name  = var.name
    })
  }

  depends_on = [
    aws_eks_node_group.this,
    aws_iam_role.cd,
  ]
}

resource "aws_iam_role_policy" "alb_controller" {
  role   = aws_iam_role.alb_controller.id
  policy = data.aws_iam_policy_document.alb_controller.json
}
