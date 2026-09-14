# Per-environment application secrets + config, stored in AWS so the CD
# workflow and the pods never need them in GitHub:
#
#   Secrets Manager (default AWS-managed key, no CMK):
#     <name>-db         {"username","password"}  - the login the APP connects as
#     <name>-db-master  {"username","password"}  - the RDS master login
#     <name>-image-api  {"key"}                  - the image API key
#   SSM Parameter Store (non-secret config):
#     /template/<env>/image-api-url               - the image API base URL
#
# The pods read these at runtime via External Secrets Operator (ESO): the
# ESO IRSA role (created by the eks module) gets GetSecretValue on the two
# secret ARNs below, and the aws/k8s ExternalSecret manifests sync them into
# in-cluster k8s Secrets. The CD workflow reads the SSM parameter for the
# image API URL and the RDS describe for the endpoint/user - it never sees
# the DB password or the image API key.
#
# <name>-db-master always holds the RDS master login. When there is a
# dedicated app user (prod), <name>-db holds that user and
# bootstrap/provision-db-user.sh reads <name>-db-master to create it. When
# there is no separate app user (dev/qa), <name>-db == <name>-db-master.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

locals {
  tags = var.tags

  db_secret_name = "${var.name}-db"
  # The login the app connects as: the dedicated app user when set, else master.
  app_username = var.app_username != "" ? var.app_username : var.db_master_username
  app_password = var.app_username != "" ? var.app_password : var.db_master_password
}

resource "aws_secretsmanager_secret" "db" {
  name                    = local.db_secret_name
  description             = "DB login the app connects as (${var.environment})"
  recovery_window_in_days = 7

  tags = merge(local.tags, { Name = local.db_secret_name })
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = local.app_username
    password = local.app_password
  })
}

resource "aws_secretsmanager_secret" "db_master" {
  name                    = "${var.name}-db-master"
  description             = "RDS master login (${var.environment})"
  recovery_window_in_days = 7

  tags = merge(local.tags, { Name = "${var.name}-db-master" })
}

resource "aws_secretsmanager_secret_version" "db_master" {
  secret_id = aws_secretsmanager_secret.db_master.id
  secret_string = jsonencode({
    username = var.db_master_username
    password = var.db_master_password
  })
}

resource "aws_secretsmanager_secret" "image_api" {
  name                    = "${var.name}-image-api"
  description             = "Image API key (${var.environment})"
  recovery_window_in_days = 7

  tags = merge(local.tags, { Name = "${var.name}-image-api" })
}

resource "aws_secretsmanager_secret_version" "image_api" {
  secret_id = aws_secretsmanager_secret.image_api.id
  secret_string = jsonencode({
    key = var.image_api_key
  })
}

# SSM parameter names must be fully qualified (start with /).
resource "aws_ssm_parameter" "image_api_url" {
  name  = "/template/${var.environment}/image-api-url"
  type  = "String"
  value = var.image_api_url

  tags = merge(local.tags, { Name = "/template/${var.environment}/image-api-url" })
}

# ----- External Secrets Operator (IRSA) -----
# Lives here (not the eks module) because it needs the secret ARNs this module
# creates AND the cluster OIDC issuer (passed in) - putting it in the eks
# module would form a cycle (eks -> secrets -> rds -> eks). The role trusts the
# cluster OIDC provider for the ESO service account and may only read this
# env's two secrets. Installed by bootstrap/setup-eks.sh (helm, with the
# role-arn annotation pointing at the ARN output below).

data "aws_iam_policy_document" "eso_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.cluster_oidc_issuer_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name_prefix        = "${var.name}-eso-"
  assume_role_policy = data.aws_iam_policy_document.eso_assume.json

  tags = local.tags
}

data "aws_iam_policy_document" "eso" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      aws_secretsmanager_secret.db.arn,
      aws_secretsmanager_secret.image_api.arn,
    ]
  }
}

resource "aws_iam_role_policy" "eso" {
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso.json
}
