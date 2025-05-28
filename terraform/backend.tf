terraform {
  backend "azurerm" {
    resource_group_name  = "rg-rbac-poc"
    storage_account_name = "strbacpoc82677"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}
