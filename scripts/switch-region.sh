#!/bin/bash
# Provided by Tidal <support@tidalcloud.com>

# Script to quickly switch Azure regions in terraform.tfvars
# Usage: ./switch-region.sh "West US 2"

if [ $# -eq 0 ]; then
    echo "🔧 Azure Region Switcher"
    echo "======================="
    echo "Usage: $0 \"<region-name>\""
    echo ""
    echo "Common regions with good quota availability:"
    echo "  - \"West US 2\""
    echo "  - \"Central US\""
    echo "  - \"West Europe\""
    echo "  - \"Southeast Asia\""
    echo "  - \"East US 2\""
    echo "  - \"North Europe\""
    echo ""
    echo "Example: $0 \"West US 2\""
    exit 1
fi

new_region="$1"
tfvars_file="terraform/demo-app/terraform.tfvars"

echo "🔄 Switching Azure region to: $new_region"

# Check if terraform.tfvars exists
if [ ! -f "$tfvars_file" ]; then
    echo "❌ terraform.tfvars not found at $tfvars_file"
    echo "💡 Creating new terraform.tfvars file..."
    
    cat > "$tfvars_file" << EOF
# Terraform variables file
# Azure region for deployment
location = "$new_region"

# Tags to apply to all resources
tags = {
  Environment = "POC"
  Project     = "Azure-RBAC-Scope-Reduction"
  Purpose     = "Demo-Application"
  Owner       = "sandbox-user"
  CostCenter  = "poc-testing"
}
EOF
    echo "✅ Created new terraform.tfvars with region: $new_region"
else
    # Update existing file
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/location = \".*\"/location = \"$new_region\"/" "$tfvars_file"
    else
        # Linux
        sed -i "s/location = \".*\"/location = \"$new_region\"/" "$tfvars_file"
    fi
    echo "✅ Updated terraform.tfvars with new region: $new_region"
fi

echo ""
echo "📋 Current terraform.tfvars content:"
echo "===================================="
cat "$tfvars_file"

echo ""
echo "🚀 Next steps:"
echo "1. cd terraform/demo-app"
echo "2. terraform plan"
echo "3. terraform apply" 