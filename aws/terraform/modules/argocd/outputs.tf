output "application_name" {
  description = "ArgoCD Application name"
  value       = "${var.name}-app"
}

output "argocd_namespace" {
  description = "Namespace ArgoCD runs in"
  value       = "argocd"
}
