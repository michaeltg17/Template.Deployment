locals {
  # Shared prefix for every resource name (e.g. template-dev-rg, template-dev, ...)
  name = "${var.project_name}-${var.environment}"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
