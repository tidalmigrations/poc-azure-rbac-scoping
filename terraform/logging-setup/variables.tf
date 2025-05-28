variable "location" {
  description = "The Azure region where logging resources will be created"
  type        = string
  default     = "East US"
}

variable "tags" {
  description = "A map of tags to assign to the logging resources"
  type        = map(string)
  default = {
    Environment = "POC"
    Project     = "Azure-RBAC-Scope-Reduction"
    Purpose     = "Logging-Infrastructure"
  }
}

variable "service_principal_object_id" {
  description = "Object ID of the service principal to monitor (optional, for filtering)"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
} 
