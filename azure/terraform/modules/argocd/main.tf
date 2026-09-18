# ArgoCD (GitOps controller) on AKS.
#
# Installs ArgoCD with helm and creates the Application that syncs this repo's
# rendered manifests (deploy/<env>/azure/) into the cluster. The rendered
# manifests are committed to the repo by the CD workflow; ArgoCD is the only
# thing that applies them to the cluster.
#
# The Application is a plain CR - it is created with the kubernetes provider
# (no need to reach the ArgoCD API server from outside the cluster).
#
# The helm + kubernetes providers authenticate with the cluster's client
# certificate (kube_config), read via a data source. The calling identity
# needs the "Azure Kubernetes Service Cluster User Role" (granted to the
# tf-plan / tf-apply identities by the aks module) to read it.
#
# First-apply bootstrap: the data source cannot read a cluster that does not
# exist yet, so the first apply must run locally (az login with Contributor).
# The tf-apply identity's RBAC binding (below) is created by that first apply;
# CI applies work from the second apply onward.
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
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

provider "azurerm" {
  features {}
}

# NOTE: the module call in the environment must set `depends_on = [module.aks]`
# so this data source is only read after the cluster exists (first apply).
data "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  resource_group_name = var.resource_group_name
}

provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.this.kube_config[0].host
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = data.azurerm_kubernetes_cluster.this.kube_config[0].host
    client_certificate     = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].client_certificate)
    client_key             = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
  }
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

# RBAC for the terraform plan/apply identities. With managed AAD (on by
# default on AKS), a service principal / managed identity is projected as the
# k8s User named by its object id (principal id) - so we bind the exact
# principals:
#   tf-plan  -> read-only (the helm provider reads release state during plan)
#   tf-apply -> cluster-admin (creates the ArgoCD resources below)
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
    kind = "User"
    name = var.tf_plan_principal_id
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
    kind = "User"
    name = var.tf_apply_principal_id
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
# - path: deploy/<env>/azure (rendered by the CD workflow, committed to the repo)
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
        path           = "deploy/${var.environment}/azure"
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

  depends_on = [helm_release.argocd]
}
