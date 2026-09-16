locals {
  # Shared prefix for every resource name (e.g. dev-template-rg, dev-template, ...)
  name = "${var.environment}-${var.project_name}"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
