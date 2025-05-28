#!/bin/bash
# Provided by Tidal <support@tidalcloud.com>

# Azure RBAC POC - Terraform Backend Setup
# This script creates an Azure Storage Account to store Terraform state files

set -e

# Configuration
RESOURCE_GROUP="rg-rbac-poc"
STORAGE_ACCOUNT="strbacpoc$(date +%s | tail -c 6)"  # Add random suffix to ensure uniqueness
CONTAINER_NAME="tfstate"
LOCATION="eastus"

echo "🚀 Setting up Terraform backend..."
echo "Resource Group: $RESOURCE_GROUP"
echo "Storage Account: $STORAGE_ACCOUNT"
echo "Container: $CONTAINER_NAME"
echo "Location: $LOCATION"

# Check if Azure CLI is logged in
if ! az account show &> /dev/null; then
    echo "❌ Please login to Azure CLI first: az login"
    exit 1
fi

# Get current subscription
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "Using subscription: $SUBSCRIPTION_ID"

# Create resource group if it doesn't exist
echo "📦 Creating resource group..."
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output table

# Create storage account
echo "💾 Creating storage account..."
az storage account create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$STORAGE_ACCOUNT" \
    --sku Standard_LRS \
    --encryption-services blob \
    --https-only true \
    --kind StorageV2 \
    --access-tier Hot \
    --output table

# Get storage account key
echo "🔑 Retrieving storage account key..."
ACCOUNT_KEY=$(az storage account keys list \
    --resource-group "$RESOURCE_GROUP" \
    --account-name "$STORAGE_ACCOUNT" \
    --query '[0].value' -o tsv)

# Create container for Terraform state
echo "📁 Creating storage container..."
az storage container create \
    --name "$CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$ACCOUNT_KEY" \
    --output table

# Create backend configuration file
echo "📝 Creating backend configuration..."
cat > terraform/backend.tf << EOF
terraform {
  backend "azurerm" {
    resource_group_name  = "$RESOURCE_GROUP"
    storage_account_name = "$STORAGE_ACCOUNT"
    container_name       = "$CONTAINER_NAME"
    key                  = "terraform.tfstate"
  }
}
EOF

# Create environment variables file
cat > .env << EOF
# Azure Backend Configuration
export ARM_RESOURCE_GROUP_NAME="$RESOURCE_GROUP"
export ARM_STORAGE_ACCOUNT_NAME="$STORAGE_ACCOUNT"
export ARM_CONTAINER_NAME="$CONTAINER_NAME"
export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"

# Source this file before running Terraform:
# source .env
EOF

echo "✅ Terraform backend setup complete!"
echo ""
echo "📋 Next steps:"
echo "1. Source the environment variables: source .env"
echo "2. Initialize Terraform: cd terraform/demo-app && terraform init"
echo ""
echo "💡 Backend configuration saved to: terraform/backend.tf"
echo "💡 Environment variables saved to: .env" 