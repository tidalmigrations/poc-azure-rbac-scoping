# Provided by Tidal <support@tidalcloud.com>

# Outputs for the logging infrastructure
# These will be used by scripts to query and analyze activity logs

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.policy_analysis.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.policy_analysis.name
}

output "log_analytics_workspace_resource_group" {
  description = "Resource group of the Log Analytics workspace"
  value       = azurerm_resource_group.logging.name
}

output "log_analytics_customer_id" {
  description = "Customer ID (workspace ID) for Log Analytics queries"
  value       = azurerm_log_analytics_workspace.policy_analysis.workspace_id
}

output "storage_account_name" {
  description = "Name of the storage account for log archival"
  value       = azurerm_storage_account.logs.name
}

output "subscription_id" {
  description = "Subscription ID being monitored"
  value       = data.azurerm_subscription.current.subscription_id
}

output "tenant_id" {
  description = "Tenant ID of the current subscription"
  value       = data.azurerm_client_config.current.tenant_id
}

# Configuration summary for scripts
output "logging_config" {
  description = "Configuration summary for logging analysis scripts"
  value = {
    workspace_id    = azurerm_log_analytics_workspace.policy_analysis.workspace_id
    workspace_name  = azurerm_log_analytics_workspace.policy_analysis.name
    resource_group  = azurerm_resource_group.logging.name
    subscription_id = data.azurerm_subscription.current.subscription_id
    tenant_id       = data.azurerm_client_config.current.tenant_id
    storage_account = azurerm_storage_account.logs.name
    retention_days  = azurerm_log_analytics_workspace.policy_analysis.retention_in_days
  }
} 
