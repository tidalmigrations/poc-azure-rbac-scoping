# Azure RBAC POC - Logging Infrastructure
# This configuration sets up comprehensive activity logging and monitoring

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
  features {}
}

# Data sources
data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Resource Group for logging infrastructure
resource "azurerm_resource_group" "logging" {
  name     = "rg-logging-${random_string.suffix.result}"
  location = var.location

  tags = var.tags
}

# Log Analytics Workspace for policy analysis
resource "azurerm_log_analytics_workspace" "policy_analysis" {
  name                = "law-policy-analysis-${random_string.suffix.result}"
  location            = azurerm_resource_group.logging.location
  resource_group_name = azurerm_resource_group.logging.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}

# Diagnostic Settings for Activity Log at subscription level
resource "azurerm_monitor_diagnostic_setting" "subscription_activity_log" {
  name                       = "activity-log-to-law"
  target_resource_id         = data.azurerm_subscription.current.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.policy_analysis.id

  enabled_log {
    category = "Administrative"
  }

  enabled_log {
    category = "Security"
  }

  enabled_log {
    category = "ServiceHealth"
  }

  enabled_log {
    category = "Alert"
  }

  enabled_log {
    category = "Recommendation"
  }

  enabled_log {
    category = "Policy"
  }

  enabled_log {
    category = "Autoscale"
  }

  enabled_log {
    category = "ResourceHealth"
  }
}

# Storage Account for long-term log retention (optional)
resource "azurerm_storage_account" "logs" {
  name                     = "st${random_string.suffix.result}logs"
  resource_group_name      = azurerm_resource_group.logging.name
  location                 = azurerm_resource_group.logging.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  tags = var.tags
}

# Storage Container for archived logs
resource "azurerm_storage_container" "activity_logs" {
  name                  = "activity-logs"
  storage_account_name  = azurerm_storage_account.logs.name
  container_access_type = "private"
}
