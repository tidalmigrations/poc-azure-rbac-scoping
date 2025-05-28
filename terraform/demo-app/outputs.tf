# Outputs for the demo application
# These will be used for logging configuration in later phases

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.demo.name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.demo.id
}

output "web_app_name" {
  description = "Name of the web app"
  value       = azurerm_linux_web_app.demo.name
}

output "web_app_url" {
  description = "URL of the web app"
  value       = "https://${azurerm_linux_web_app.demo.default_hostname}"
}

output "postgresql_server_name" {
  description = "Name of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.demo.name
}

output "postgresql_database_name" {
  description = "Name of the PostgreSQL database"
  value       = azurerm_postgresql_flexible_server_database.demo.name
}

output "postgresql_fqdn" {
  description = "FQDN of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.demo.fqdn
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.demo.name
}

output "key_vault_name" {
  description = "Name of the key vault"
  value       = azurerm_key_vault.demo.name
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.demo.name
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = azurerm_application_insights.demo.instrumentation_key
  sensitive   = true
}

# Summary for logging configuration
output "deployment_summary" {
  description = "Summary of deployed resources for logging analysis"
  value = {
    resource_group = azurerm_resource_group.demo.name
    location       = azurerm_resource_group.demo.location
    resources = {
      web_app              = azurerm_linux_web_app.demo.name
      app_service_plan     = azurerm_service_plan.demo.name
      postgresql_server    = azurerm_postgresql_flexible_server.demo.name
      postgresql_database  = azurerm_postgresql_flexible_server_database.demo.name
      storage_account      = azurerm_storage_account.demo.name
      key_vault            = azurerm_key_vault.demo.name
      application_insights = azurerm_application_insights.demo.name
    }
  }
}
