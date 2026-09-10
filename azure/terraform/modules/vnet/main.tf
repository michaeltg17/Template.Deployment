locals {
  tags = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "${var.name}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_cidr]

  tags = merge(local.tags, { Name = "${var.name}-vnet" })
}

# App Gateway: public, dedicated and delegated (no other resource may live in
# this subnet). AGIC requires a Standard_v2/WAF_v2 gateway on a delegated subnet.
resource "azurerm_subnet" "appgw" {
  name                 = "${var.name}-appgw"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.appgw_subnet_cidr]

  delegation {
    name = "${var.name}-appgw-delegation"
    service_delegation {
      name = "Microsoft.Network/applicationGateways"
      # Azure auto-adds the join action; declare it so it does not show as
      # perpetual plan drift (matches the PostgreSQL subnet delegation below).
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# AKS nodes (+ pods, CNI node-subnet model: pods share the node subnet IPs).
# Private - no public IPs. Outbound to the internet is provided by AKS's
# default egress (no NAT gateway, to keep the dev bill low).
resource "azurerm_subnet" "nodes" {
  name                 = "${var.name}-nodes"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.nodes_subnet_cidr]
}

# PostgreSQL Flexible Server. Private. Must be delegated to the PostgreSQL
# service (private / VNet-integration mode) - no other resource may live here.
resource "azurerm_subnet" "pg" {
  name                 = "${var.name}-pg"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.pg_subnet_cidr]

  delegation {
    name = "${var.name}-pg-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Node subnet: allow all in-VNet inbound (App Gateway -> pods, inter-node,
# control plane -> nodes, nodes -> everything else is covered by the default
# egress rule). This mirrors the AWS node security group (allow in-VPC).
resource "azurerm_network_security_group" "nodes" {
  name                = "${var.name}-nsg-nodes"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "in-vnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.vnet_cidr
    destination_address_prefix = "*"
  }

  tags = merge(local.tags, { Name = "${var.name}-nsg-nodes" })
}

# PG subnet: only the AKS node subnet may reach PostgreSQL on 5432.
resource "azurerm_network_security_group" "pg" {
  name                = "${var.name}-nsg-pg"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "in-nodes-pg"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = var.nodes_subnet_cidr
    destination_address_prefix = "*"
  }

  tags = merge(local.tags, { Name = "${var.name}-nsg-pg" })
}

resource "azurerm_subnet_network_security_group_association" "nodes" {
  subnet_id                 = azurerm_subnet.nodes.id
  network_security_group_id = azurerm_network_security_group.nodes.id
}

resource "azurerm_subnet_network_security_group_association" "pg" {
  subnet_id                 = azurerm_subnet.pg.id
  network_security_group_id = azurerm_network_security_group.pg.id
}
