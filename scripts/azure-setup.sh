#!/bin/bash
# Provided by Tidal <support@tidalcloud.com>

# Azure RBAC POC - Azure Setup Script
# This script helps set up the Azure environment for the POC

set -e

# Configuration
SP_NAME="sp-terraform-rbac-poc"
RESOURCE_GROUP="rg-rbac-poc"
LOCATION="eastus"

echo "🚀 Azure RBAC POC - Environment Setup"
echo "======================================"

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI is not installed. Please install it first:"
    echo "   https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    echo "🔐 Please login to Azure CLI..."
    az login
fi

# Get current subscription
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

echo "📋 Current Azure Context:"
echo "   Subscription: $SUBSCRIPTION_NAME"
echo "   Subscription ID: $SUBSCRIPTION_ID"
echo ""

# Confirm subscription
read -p "Is this the correct subscription? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please set the correct subscription:"
    echo "   az account set --subscription \"your-subscription-id\""
    exit 1
fi

# Create resource group
echo "📦 Creating resource group: $RESOURCE_GROUP"
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output table

# Check if service principal already exists
if az ad sp list --display-name "$SP_NAME" --query "[0].appId" -o tsv | grep -q .; then
    echo "⚠️  Service principal '$SP_NAME' already exists"
    SP_APP_ID=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" -o tsv)
    echo "   App ID: $SP_APP_ID"
    
    read -p "Do you want to reset the credentials? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🔄 Resetting service principal credentials..."
        SP_CREDENTIALS=$(az ad sp credential reset --id "$SP_APP_ID" --output json)
    else
        echo "⏭️  Skipping service principal creation"
        echo "   Note: You'll need to use existing credentials"
        SP_CREDENTIALS=""
    fi
else
    # Create service principal
    echo "👤 Creating service principal: $SP_NAME"
    SP_CREDENTIALS=$(az ad sp create-for-rbac \
        --name "$SP_NAME" \
        --role Contributor \
        --scopes "/subscriptions/$SUBSCRIPTION_ID" \
        --output json)
fi

# Extract credentials if we have them
if [ -n "$SP_CREDENTIALS" ]; then
    SP_APP_ID=$(echo "$SP_CREDENTIALS" | jq -r '.appId')
    SP_PASSWORD=$(echo "$SP_CREDENTIALS" | jq -r '.password')
    SP_TENANT=$(echo "$SP_CREDENTIALS" | jq -r '.tenant')

    echo "✅ Service principal created successfully!"
    echo ""
    echo "📝 Service Principal Details:"
    echo "   Name: $SP_NAME"
    echo "   App ID: $SP_APP_ID"
    echo "   Tenant: $SP_TENANT"
    echo ""

    # Create environment file for Terraform
    cat > .env.terraform << EOF
# Terraform Azure Provider Configuration
export ARM_CLIENT_ID="$SP_APP_ID"
export ARM_CLIENT_SECRET="$SP_PASSWORD"
export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
export ARM_TENANT_ID="$SP_TENANT"

# Source this file before running Terraform:
# source .env.terraform
EOF

    echo "💾 Terraform credentials saved to: .env.terraform"
    echo ""
    echo "🔒 IMPORTANT: Keep these credentials secure!"
    echo "   The client secret is only shown once and has been saved to .env.terraform"
fi

echo "📋 Next Steps:"
echo "1. Source the Terraform environment: source .env.terraform"
echo "2. Set up Terraform backend: ./scripts/setup-backend.sh"
echo "3. Initialize and deploy: cd terraform/demo-app && terraform init && terraform plan"
echo ""
echo "✅ Azure setup complete!" 