# Provided by Tidal <support@tidalcloud.com>

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
}

variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
  default = {
    Environment = "POC"
    Project     = "Azure-RBAC-Scope-Reduction"
    Purpose     = "Demo-Application"
  }
} 
