# Azure RBAC POC - Demo Application
# This configuration creates a simple web application with database to generate diverse permissions

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

# Data sources
data "azurerm_client_config" "current" {}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Resource Group
resource "azurerm_resource_group" "demo" {
  name     = "rg-demo-app-${random_string.suffix.result}"
  location = var.location

  tags = var.tags
}

# App Service Plan
resource "azurerm_service_plan" "demo" {
  name                = "asp-demo-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.demo.name
  location            = azurerm_resource_group.demo.location
  os_type             = "Linux"
  sku_name            = "B1"

  tags = var.tags
}

# Web App
resource "azurerm_linux_web_app" "demo" {
  name                = "app-demo-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.demo.name
  location            = azurerm_service_plan.demo.location
  service_plan_id     = azurerm_service_plan.demo.id

  site_config {
    application_stack {
      node_version = "18-lts"
    }
  }

  app_settings = {
    "WEBSITE_NODE_DEFAULT_VERSION" = "18.17.0"
    "DATABASE_URL"                 = "postgresql://${azurerm_postgresql_flexible_server.demo.administrator_login}:${azurerm_postgresql_flexible_server.demo.administrator_password}@${azurerm_postgresql_flexible_server.demo.fqdn}:5432/${azurerm_postgresql_flexible_server_database.demo.name}?sslmode=require"
    "STORAGE_CONNECTION_STRING"    = azurerm_storage_account.demo.primary_connection_string
  }

  tags = var.tags
}

# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "demo" {
  name                   = "psql-demo-${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.demo.name
  location               = azurerm_resource_group.demo.location
  version                = "13"
  administrator_login    = "psqladmin"
  administrator_password = random_string.db_password.result

  storage_mb = 32768
  sku_name   = "B_Standard_B1ms"

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  tags = var.tags
}

# PostgreSQL Database
resource "azurerm_postgresql_flexible_server_database" "demo" {
  name      = "demoapp"
  server_id = azurerm_postgresql_flexible_server.demo.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# PostgreSQL Firewall Rule (allow Azure services)
resource "azurerm_postgresql_flexible_server_firewall_rule" "demo" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.demo.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Storage Account
resource "azurerm_storage_account" "demo" {
  name                     = "st${random_string.suffix.result}demo"
  resource_group_name      = azurerm_resource_group.demo.name
  location                 = azurerm_resource_group.demo.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  tags = var.tags
}

# Storage Container
resource "azurerm_storage_container" "demo" {
  name                  = "uploads"
  storage_account_name  = azurerm_storage_account.demo.name
  container_access_type = "private"
}

# Key Vault
resource "azurerm_key_vault" "demo" {
  name                = "kv-demo-${random_string.suffix.result}"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get", "List", "Create", "Delete", "Update"
    ]

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge", "Recover"
    ]
  }

  tags = var.tags
}

# Key Vault Secret
resource "azurerm_key_vault_secret" "demo" {
  name         = "database-password"
  value        = random_string.db_password.result
  key_vault_id = azurerm_key_vault.demo.id

  depends_on = [azurerm_key_vault.demo]
}

# Application Insights
resource "azurerm_application_insights" "demo" {
  name                = "appi-demo-${random_string.suffix.result}"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  application_type    = "web"

  tags = var.tags
}

# Random password for PostgreSQL
resource "random_string" "db_password" {
  length  = 16
  special = true
}
