# ArgoCD (GitOps controller) on EKS.
#
# Installs ArgoCD with helm and creates the Application that syncs this repo's
# rendered manifests (deploy/<env>/aws/) into the cluster. The rendered
# manifests are committed to the repo by the CD workflow; ArgoCD is the only
# thing that applies them to the cluster.
#
# The Application is a plain CR - it is created with the kubernetes provider
# (no need to reach the ArgoCD API server from outside the cluster).
#
# The helm + kubernetes providers authenticate with `aws eks get-token` (an
# exec credential plugin), so the calling identity needs
# eks:DescribeCluster + sts:GetWebIdentityToken (the apply role has both).
terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_ca_certificate)

    exec {
      api_version = "client.command.k8s.io/v1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
    }
  }
}

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)

  exec {
    api_version = "client.command.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
  }
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

# RBAC for the terraform plan/apply roles (their EKS access entries put them
# in the tf-plan / tf-apply k8s groups; see the eks module). plan is
# cluster-wide read-only (it reads the helm release + k8s objects to diff);
# apply is cluster-admin (it creates the namespace/SA/CRB/secret/Application
# below - including these bindings, on first apply).
resource "kubernetes_cluster_role" "tf_plan" {
  metadata {
    name = "tf-plan-${var.name}"
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "tf_plan" {
  metadata {
    name = "tf-plan-${var.name}"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.tf_plan.metadata[0].name
  }

  subject {
    kind = "Group"
    name = "tf-plan"
  }
}

resource "kubernetes_cluster_role_binding" "tf_apply" {
  metadata {
    name = "tf-apply-${var.name}"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind = "Group"
    name = "tf-apply"
  }
}

# ArgoCD needs broad cluster access to sync arbitrary manifests. This is the
# standard ArgoCD install (its controller SA gets cluster-admin); the security
# boundary is the repo + the Application's source path, not this role.
resource "kubernetes_service_account" "argocd" {
  metadata {
    name      = "argocd-application-controller"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding" "argocd" {
  metadata {
    name = "argocd-application-controller"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.argocd.metadata[0].name
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  set {
    name  = "controller.replicas"
    value = "1"
  }

  # Plan runs as the read-only tf-plan role, whose ClusterRole (above) grants
  # get/list/watch on all resources - including the secrets the helm provider
  # uses to store release state - so plan can read the release and diff it.
  #
  # First-apply bootstrap: the tf-apply binding (above) is created by the first
  # apply, which must run locally (the bootstrap creator has cluster-admin).
  # CI applies work from the second apply onward.
  depends_on = [kubernetes_service_account.argocd]
}

# Git credentials for the ArgoCD repo server: a PAT (contents:read on this
# repo only) stored as an ArgoCD repo-credentials secret. ArgoCD selects a
# repo secret by matching its `url` against the Application's source.repo_url.
resource "kubernetes_secret" "argocd_repo" {
  metadata {
    name      = "template-deployment-repo"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  data = {
    url  = var.git_repo_url
    text = var.git_repo_token
  }

  type = "Opaque"
}

# The Application: syncs the rendered manifests for this env/cloud.
#
# - path: deploy/<env>/aws (rendered by the CD workflow, committed to the repo)
# - automated prune + selfHeal: Git is the source of truth; manual `kubectl
#   apply` drift is rolled back on the next sync.
resource "kubernetes_manifest" "argocd_application" {
  provider = kubernetes

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "${var.name}-app"
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.git_repo_url
        targetRevision = "main"
        path           = "deploy/${var.environment}/aws"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "default"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true",
        ]
      }
    }
  }

  # The Application CRD does not exist until the helm release above installs
  # ArgoCD. Without this, the provider's read of the (not-yet-existing) CR
  # errors on the missing CRD instead of planning a create.
  depends_on = [helm_release.argocd]
}
