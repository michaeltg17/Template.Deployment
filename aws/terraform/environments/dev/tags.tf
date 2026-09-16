variable "project_name" {
  description = "Resource name suffix and Project tag (AWS resource-group equivalent)"
  type        = string
  default     = "template"
}

variable "environment" {
  description = "Environment name (prefix of every resource name + Environment tag)"
  type        = string
  default     = "dev"
}

locals {
  name = "${var.environment}-${var.project_name}"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
