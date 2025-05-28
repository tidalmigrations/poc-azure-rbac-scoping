#!/bin/bash

# Azure RBAC POC - Install Required Azure CLI Extensions
# This script installs the necessary Azure CLI extensions for the project

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

print_status "Installing required Azure CLI extensions for Azure RBAC POC..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Configure Azure CLI for non-interactive extension installation
print_status "Configuring Azure CLI for automated extension installation..."
az config set extension.use_dynamic_install=yes_without_prompt 2>/dev/null || true
az config set extension.dynamic_install_allow_preview=true 2>/dev/null || true

# List of required extensions
EXTENSIONS=("log-analytics" "monitor-control-service")

for extension in "${EXTENSIONS[@]}"; do
    print_status "Checking extension: $extension"
    
    if az extension list --query "[?name=='$extension']" -o tsv | grep -q "$extension"; then
        print_success "✓ Extension '$extension' is already installed"
    else
        print_status "Installing extension: $extension"
        if az extension add --name "$extension" --yes --only-show-errors 2>/dev/null; then
            print_success "✓ Extension '$extension' installed successfully"
        else
            print_warning "⚠ Failed to install extension '$extension' (may not be critical)"
        fi
    fi
done

print_success "Extension installation completed!"
echo
print_status "Installed extensions:"
az extension list --query "[].{Name:name, Version:version}" -o table

echo
print_status "You can now run the logging deployment:"
echo "  ./scripts/deploy-logging.sh" 