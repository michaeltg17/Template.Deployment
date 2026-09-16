variable "aws_region" {
  description = "AWS region to deploy in"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Optional AWS CLI profile name (empty = default credentials chain)"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, one per AZ (ALB + NAT)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs, one per AZ (EKS nodes + RDS)"
  type        = list(string)
  default     = ["10.0.10.0/23", "10.0.12.0/23", "10.0.14.0/23"]
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version (major.minor)"
  type        = string
  default     = "1.36"
}

# ----- prod node profile (HA: one node per AZ) -----

variable "worker_instance_types" {
  description = "Node group instance types. Prod uses m7i-flex.xlarge (4 vCPU/16 GB) for real headroom"
  type        = list(string)
  default     = ["m7i-flex.xlarge"]
}

variable "worker_disk_size_gb" {
  description = "GP3 root volume per node"
  type        = number
  default     = 50
}

variable "worker_min_size" {
  description = "Node group min size (3 = one per AZ for HA)"
  type        = number
  default     = 3
}

variable "worker_max_size" {
  description = "Node group max size"
  type        = number
  default     = 3
}

variable "worker_desired_size" {
  description = "Node group desired size"
  type        = number
  default     = 3
}

# ----- prod RDS profile (hardened) -----

variable "db_engine_version" {
  description = "RDS PostgreSQL engine version"
  type        = string
  default     = "18.6"
}

variable "db_instance_class" {
  description = "RDS instance class. Prod uses db.t4g.medium (2 vCPU/8 GB, Multi-AZ capable)"
  type        = string
  default     = "db.t4g.medium"
}

variable "db_master_password" {
  description = "RDS master password. Stored in the prod-template-db-master secret. Never in GitHub"
  type        = string
  sensitive   = true
}

variable "db_app_username" {
  description = "Dedicated app login (prod). The app + migrations connect as this user, not the master (the RDS master user is named 'app', so this must differ)"
  type        = string
  default     = "template_app"
}

variable "db_app_password" {
  description = "Dedicated app login password. Stored in the prod-template-db secret"
  type        = string
  sensitive   = true
}

variable "db_multi_az" {
  description = "RDS Multi-AZ standby"
  type        = bool
  default     = true
}

variable "db_apply_immediately" {
  description = "Apply pending RDS changes immediately (prod: false -> maintenance window)"
  type        = bool
  default     = false
}

variable "db_backup_retention_period" {
  description = "RDS automated backup retention in days (prod: 7)"
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "RDS deletion protection (prod: true)"
  type        = bool
  default     = true
}

variable "db_skip_final_snapshot" {
  description = "Skip the final snapshot on destroy (prod: false)"
  type        = bool
  default     = false
}

variable "db_final_snapshot_identifier" {
  description = "RDS final snapshot identifier (required because skip_final_snapshot is false)"
  type        = string
  default     = "prod-template-db-final"
}

variable "image_api_key" {
  description = "Image API key for this environment (stored in the prod-template-image-api secret)"
  type        = string
  sensitive   = true
}

variable "image_api_url" {
  description = "Image API base URL for this environment (stored in SSM Parameter Store)"
  type        = string
}

# ----- prod CD identity hardening -----

variable "cd_oidc_sub" {
  description = "OIDC 'sub' patterns allowed to assume the CD (deploy) role. Prod pins to the main/dev branches only"
  type        = list(string)
  default = [
    "repo:michaeltg17/Template.Deployment:ref:heads/main",
    "repo:michaeltg17/Template.Deployment:ref:heads/dev",
  ]
}
