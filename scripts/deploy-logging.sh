#!/bin/bash
# Provided by Tidal <support@tidalcloud.com>

# Azure RBAC POC - Deploy Logging Infrastructure
# This script deploys the Log Analytics workspace and diagnostic settings

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "terraform/logging-setup/main.tf" ]; then
    print_error "Please run this script from the project root directory"
    exit 1
fi

# Check if Azure CLI is installed and logged in
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    print_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    print_error "Terraform is not installed. Please install it first."
    exit 1
fi

# Configure Azure CLI for non-interactive extension installation
print_status "Configuring Azure CLI for automated extension installation..."
az config set extension.use_dynamic_install=yes_without_prompt 2>/dev/null || true
az config set extension.dynamic_install_allow_preview=true 2>/dev/null || true

# Install log-analytics extension if not already installed
print_status "Ensuring log-analytics extension is installed..."
if ! az extension list --query "[?name=='log-analytics']" -o tsv | grep -q log-analytics; then
    print_status "Installing log-analytics extension..."
    az extension add --name log-analytics --yes 2>/dev/null || true
fi

print_status "Starting logging infrastructure deployment..."

# Get current subscription info
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

print_status "Current subscription: $SUBSCRIPTION_ID"
print_status "Current tenant: $TENANT_ID"

# Change to logging setup directory
cd terraform/logging-setup

# Initialize Terraform
print_status "Initializing Terraform..."
terraform init

# Validate configuration
print_status "Validating Terraform configuration..."
terraform validate

# Plan deployment
print_status "Planning deployment..."
terraform plan -out=tfplan

# Ask for confirmation
echo
read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Deployment cancelled by user"
    rm -f tfplan
    exit 0
fi

# Apply deployment
print_status "Deploying logging infrastructure..."
terraform apply tfplan

# Clean up plan file
rm -f tfplan

# Get outputs
print_status "Retrieving deployment outputs..."
WORKSPACE_ID=$(terraform output -raw log_analytics_customer_id)
WORKSPACE_NAME=$(terraform output -raw log_analytics_workspace_name)
RESOURCE_GROUP=$(terraform output -raw log_analytics_workspace_resource_group)

print_success "Logging infrastructure deployed successfully!"
echo
print_status "Log Analytics Workspace Details:"
echo "  - Workspace ID: $WORKSPACE_ID"
echo "  - Workspace Name: $WORKSPACE_NAME"
echo "  - Resource Group: $RESOURCE_GROUP"
echo

# Wait for diagnostic settings to take effect
print_status "Waiting for diagnostic settings to take effect (60 seconds)..."
sleep 60

# Test Log Analytics connectivity
print_status "Testing Log Analytics connectivity..."

# Try to install the extension first if the query fails
if ! az monitor log-analytics query \
    --workspace "$WORKSPACE_ID" \
    --analytics-query "AzureActivity | take 1" \
    --output table > /dev/null 2>&1; then
    
    print_status "Installing required Azure CLI extensions..."
    az extension add --name log-analytics --yes --only-show-errors 2>/dev/null || true
    
    # Try the query again after installing extension
    if az monitor log-analytics query \
        --workspace "$WORKSPACE_ID" \
        --analytics-query "AzureActivity | take 1" \
        --output table > /dev/null 2>&1; then
        print_success "Log Analytics workspace is accessible and ready!"
    else
        print_warning "Log Analytics workspace deployed but may need more time for data ingestion"
        print_status "You can test connectivity later with:"
        print_status "  az monitor log-analytics query --workspace $WORKSPACE_ID --analytics-query 'AzureActivity | take 1'"
    fi
else
    print_success "Log Analytics workspace is accessible and ready!"
fi

# Create configuration file for scripts
CONFIG_FILE="../../config/logging-config.json"
mkdir -p "$(dirname "$CONFIG_FILE")"

cat > "$CONFIG_FILE" << EOF
{
  "workspace_id": "$WORKSPACE_ID",
  "workspace_name": "$WORKSPACE_NAME",
  "resource_group": "$RESOURCE_GROUP",
  "subscription_id": "$SUBSCRIPTION_ID",
  "tenant_id": "$TENANT_ID",
  "deployed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

print_success "Configuration saved to $CONFIG_FILE"

# Return to project root
cd ../..

print_success "Phase 2 logging infrastructure deployment completed!"
echo
print_status "Next steps:"
echo "  1. Wait 5-10 minutes for activity logs to start flowing"
echo "  2. Deploy demo application to generate activity data"
echo "  3. Use KQL queries in scripts/queries/ to analyze permissions"
echo "  4. Run: az monitor log-analytics query --workspace $WORKSPACE_ID --analytics-query 'AzureActivity | take 10'" 