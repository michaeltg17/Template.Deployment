locals {
  tags = var.tags
}

resource "azurerm_public_ip" "this" {
  name                = "${var.name}-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  allocation_method   = "Static"

  # Gives the gateway a stable FQDN (<name>.<region>.cloudapp.azure.com) so the
  # appgateway_fqdn output is meaningful; otherwise a bare label-less PIP has no
  # fqdn and the output is empty. (azurerm 4.x: top-level attribute, not a
  # dns_settings block.)
  domain_name_label = var.name

  tags = merge(local.tags, { Name = "${var.name}-pip" })
}

# Standard_v2 is required by AGIC (Application Gateway Ingress Controller).
# The listener / rule / backend pool below are minimal placeholders so the
# gateway is valid at creation; AGIC takes full ownership of the routing config
# and replaces these from the Ingress (azure/k8s/ingress.yaml) once deployed.
resource "azurerm_application_gateway" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name

  sku {
    name = "Standard_v2"
    tier = "Standard_v2"
  }

  # Standard_v2 is autoscale-only. Minimum 1 unit keeps the dev cost minimal;
  # it scales up automatically under load and back down when idle.
  autoscale_configuration {
    min_capacity = 1
  }

  gateway_ip_configuration {
    name      = "${var.name}-ipconfig"
    subnet_id = var.public_subnet_id
  }

  frontend_ip_configuration {
    name                 = "${var.name}-feip"
    public_ip_address_id = azurerm_public_ip.this.id
  }

  frontend_port {
    name = "${var.name}-http"
    port = 80
  }

  http_listener {
    name                           = "${var.name}-listener"
    frontend_ip_configuration_name = "${var.name}-feip"
    frontend_port_name             = "${var.name}-http"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "${var.name}-rule"
    rule_type                  = "Basic"
    priority                   = 100
    http_listener_name         = "${var.name}-listener"
    backend_address_pool_name  = "${var.name}-backend"
    backend_http_settings_name = "${var.name}-settings"
  }

  backend_address_pool {
    name = "${var.name}-backend"
  }

  backend_http_settings {
    name                  = "${var.name}-settings"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
    cookie_based_affinity = "Disabled"
  }

  tags = merge(local.tags, { Name = var.name })

  # AGIC owns the App Gateway's runtime config and rewrites it from the Ingress:
  # the routing (listeners, rules, pools, HTTP settings, frontend port), the health
  # probes, and it adds its own tags (ingress-for-aks-cluster-id,
  # managed-by-k8s-ingress). Terraform only creates the initial placeholder so the
  # gateway is valid at creation. ignore_changes keeps later `terraform apply` from
  # clobbering AGIC's config (e.g. when only the PIP changes) - without this, any
  # re-apply reverts the gateway to the placeholder, drops AGIC's probes/tags, and
  # the app stops routing until the Ingress is re-applied.
  lifecycle {
    ignore_changes = [
      http_listener,
      request_routing_rule,
      backend_address_pool,
      backend_http_settings,
      frontend_port,
      probe,
      url_path_map,
      tags,
    ]
  }
}
