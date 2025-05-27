#!/bin/bash

# Azure RBAC POC - Setup Validation Script
# This script validates that Phase 1 setup is working correctly

set -e

echo "🔍 Azure RBAC POC - Setup Validation"
echo "===================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ $2${NC}"
    else
        echo -e "${RED}❌ $2${NC}"
    fi
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check prerequisites
echo "📋 Checking Prerequisites..."

# Check Azure CLI
if command -v az &> /dev/null; then
    print_status 0 "Azure CLI is installed"
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
    echo "   Version: $AZ_VERSION"
else
    print_status 1 "Azure CLI is not installed"
    exit 1
fi

# Check Terraform
if command -v terraform &> /dev/null; then
    print_status 0 "Terraform is installed"
    TF_VERSION=$(terraform version -json | jq -r '.terraform_version')
    echo "   Version: $TF_VERSION"
else
    print_status 1 "Terraform is not installed"
    exit 1
fi

# Check jq
if command -v jq &> /dev/null; then
    print_status 0 "jq is installed"
else
    print_status 1 "jq is not installed (required for scripts)"
    exit 1
fi

echo ""

# Check Azure login
echo "🔐 Checking Azure Authentication..."
if az account show &> /dev/null; then
    print_status 0 "Logged into Azure CLI"
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    echo "   Subscription: $SUBSCRIPTION_NAME"
    echo "   ID: $SUBSCRIPTION_ID"
else
    print_status 1 "Not logged into Azure CLI"
    echo "   Run: az login"
    exit 1
fi

echo ""

# Check environment files
echo "📁 Checking Environment Configuration..."

if [ -f ".env.terraform" ]; then
    print_status 0 "Terraform environment file exists"
    
    # Check if environment variables are set
    source .env.terraform
    if [ -n "$ARM_CLIENT_ID" ] && [ -n "$ARM_CLIENT_SECRET" ] && [ -n "$ARM_SUBSCRIPTION_ID" ] && [ -n "$ARM_TENANT_ID" ]; then
        print_status 0 "Terraform environment variables are set"
    else
        print_status 1 "Terraform environment variables are incomplete"
        print_warning "Run: source .env.terraform"
    fi
else
    print_status 1 "Terraform environment file not found"
    print_warning "Run: ./scripts/azure-setup.sh"
fi

if [ -f ".env" ]; then
    print_status 0 "Backend environment file exists"
else
    print_warning "Backend environment file not found (run ./scripts/setup-backend.sh)"
fi

echo ""

# Check directory structure
echo "📂 Checking Project Structure..."

REQUIRED_DIRS=("terraform/demo-app" "terraform/logging-setup" "terraform/modules" "scripts" "policies" "docs")
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        print_status 0 "Directory exists: $dir"
    else
        print_status 1 "Directory missing: $dir"
    fi
done

echo ""

# Check Terraform files
echo "🏗️  Checking Terraform Configuration..."

TF_FILES=("terraform/demo-app/main.tf" "terraform/demo-app/variables.tf" "terraform/demo-app/outputs.tf")
for file in "${TF_FILES[@]}"; do
    if [ -f "$file" ]; then
        print_status 0 "File exists: $file"
    else
        print_status 1 "File missing: $file"
    fi
done

# Check if backend is configured
if [ -f "terraform/backend.tf" ]; then
    print_status 0 "Terraform backend configuration exists"
else
    print_warning "Terraform backend not configured (run ./scripts/setup-backend.sh)"
fi

echo ""

# Test Terraform initialization (if backend exists)
if [ -f "terraform/backend.tf" ]; then
    echo "🔧 Testing Terraform Initialization..."
    cd terraform/demo-app
    
    if terraform init -backend=false &> /dev/null; then
        print_status 0 "Terraform configuration is valid"
    else
        print_status 1 "Terraform configuration has errors"
        echo "   Run: cd terraform/demo-app && terraform init"
    fi
    
    cd ../..
fi

echo ""

# Summary
echo "📊 Validation Summary"
echo "===================="

if [ -f ".env.terraform" ] && [ -f "terraform/demo-app/main.tf" ] && command -v az &> /dev/null && command -v terraform &> /dev/null; then
    echo -e "${GREEN}✅ Phase 1 setup appears to be complete!${NC}"
    echo ""
    echo "📋 Next steps:"
    echo "1. Source environment variables: source .env.terraform && source .env"
    echo "2. Set up backend (if not done): ./scripts/setup-backend.sh"
    echo "3. Deploy demo app: cd terraform/demo-app && terraform init && terraform plan"
else
    echo -e "${RED}❌ Phase 1 setup is incomplete${NC}"
    echo ""
    echo "📋 Required actions:"
    echo "1. Install missing prerequisites"
    echo "2. Run: ./scripts/azure-setup.sh"
    echo "3. Run: ./scripts/setup-backend.sh"
fi 