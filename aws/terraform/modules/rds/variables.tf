variable "name" {
  description = "DB instance identifier (lowercase, hyphens ok)"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "18.6"
}

variable "instance_class" {
  description = "DB instance class. db.t4g.micro is the cheapest PostgreSQL class and supports Multi-AZ"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  description = "Initial GP3 storage"
  type        = number
  default     = 20
}

variable "max_allocated_storage_gb" {
  description = "Storage auto-scaling ceiling (free until actually used)"
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "template_db"
}

variable "master_username" {
  description = "Master username (dev: the app connects as the master user)"
  type        = string
  default     = "app"
}

variable "master_password" {
  description = "Master password. Used for the master login (and, when app_username is empty, the login the app connects as)"
  type        = string
  sensitive   = true
}

variable "app_username" {
  description = "Optional dedicated application login (prod). When set, the app + migrations connect as this user instead of the master. The role itself is created by bootstrap/provision-db-user.sh (the private RDS endpoint is not reachable from the terraform runner). Empty = the app connects as the master user (dev/qa)"
  type        = string
  default     = ""
}

variable "app_password" {
  description = "Password for the dedicated application login (only used when app_username is set)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "multi_az" {
  description = "Multi-AZ standby (handles infrastructure failure, roughly doubles DB cost)"
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Apply pending changes immediately (dev). Prod sets false so changes land in the maintenance window"
  type        = bool
  default     = true
}

variable "backup_retention_period" {
  description = "Automated backup retention in days"
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "Refuse deletion (prod sets true)"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy (dev). Prod sets false and provides final_snapshot_identifier"
  type        = bool
  default     = true
}

variable "final_snapshot_identifier" {
  description = "Final snapshot identifier (required when skip_final_snapshot is false)"
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC id"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the DB subnet group (must span >= 2 AZs)"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to connect (EKS node SG)"
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "VPC CIDR block. EKS managed node groups attach EKS-managed SGs to node ENIs (not the node SG), so allow the whole VPC for reliable DB access"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to every resource in this module"
  type        = map(string)
  default     = {}
}
