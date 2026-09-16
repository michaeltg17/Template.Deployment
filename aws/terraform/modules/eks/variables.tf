variable "name" {
  description = "Cluster name (also the resource name prefix)"
  type        = string
}

variable "region" {
  description = "AWS region (used by the update-kubeconfig provisioner)"
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version (major.minor)"
  type        = string
  default     = "1.35"
}

variable "vpc_id" {
  description = "VPC id the cluster lives in"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block (in-VPC traffic allowed to the nodes)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the managed node group (one per AZ)"
  type        = list(string)
}

variable "worker_instance_types" {
  description = "Node group instance types. m7i-flex.large (2 vCPU/8 GB) is the smallest type this account's Free Tier allows that meets EKS's node minimum"
  type        = list(string)
  default     = ["m7i-flex.large"]
}

variable "worker_disk_size_gb" {
  description = "GP3 root volume size per node"
  type        = number
  default     = 20
}

variable "worker_min_size" {
  description = "Node group minimum size (use >= number of AZs for real HA)"
  type        = number
  default     = 1
}

variable "worker_max_size" {
  description = "Node group maximum size"
  type        = number
  default     = 3
}

variable "worker_desired_size" {
  description = "Node group desired size"
  type        = number
  default     = 3
}

variable "github_repo" {
  description = "GitHub repo (owner/name) allowed to assume the CD (deploy) role via OIDC"
  type        = string
  default     = "michaeltg17/Template.Deployment"
}

variable "github_owner_id" {
  description = "Numeric GitHub owner (user/org) ID, used to build GitHub's immutable OIDC 'sub' pattern (repos created on/after 2026-07-15). Find it with `gh api /users/<owner> --jq .id` (or /orgs/<org>). Empty = classic sub format only."
  type        = string
  default     = "13167621"
}

variable "github_repo_id" {
  description = "Numeric GitHub repo ID, used to build GitHub's immutable OIDC 'sub' pattern (repos created on/after 2026-07-15). Find it with `gh api /repos/<owner>/<repo> --jq .id`. Empty = classic sub format only."
  type        = string
  default     = "1334612509"
}

variable "cd_oidc_sub" {
  description = "OIDC 'sub' patterns (StringLike) allowed to assume the CD role. Default allows any ref; prod pins to the main/dev branches"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every resource in this module"
  type        = map(string)
  default     = {}
}
