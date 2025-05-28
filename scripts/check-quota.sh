#!/bin/bash

# Script to check App Service Plan quota availability across different Azure regions
# This helps identify which regions have available quota for your subscription

echo "🔍 Checking App Service Plan quota availability across Azure regions..."
echo "=================================================="

# List of regions to test (commonly available for sandbox subscriptions)
regions=(
    "West US 2"
    "Central US" 
    "West Europe"
    "Southeast Asia"
    "East US 2"
    "North Europe"
    "Canada Central"
    "Australia East"
)

# Create a temporary resource group for testing
test_rg="rg-quota-test-$(date +%s)"
echo "📝 Creating temporary resource group: $test_rg"

az group create --name "$test_rg" --location "West US 2" --output none

if [ $? -ne 0 ]; then
    echo "❌ Failed to create test resource group. Please check your Azure CLI authentication."
    exit 1
fi

echo ""
echo "🧪 Testing quota availability in different regions..."
echo "=================================================="

available_regions=()

for region in "${regions[@]}"; do
    echo -n "Testing $region... "
    
    # Try to create an App Service Plan (this will fail but give us quota info)
    result=$(az appservice plan create \
        --name "test-asp-$(date +%s)" \
        --resource-group "$test_rg" \
        --location "$region" \
        --sku B1 \
        --is-linux \
        --output none 2>&1)
    
    if [[ $result == *"quota"* ]] || [[ $result == *"Quota"* ]]; then
        echo "❌ No quota available"
    elif [[ $result == *"already exists"* ]] || [[ $result == *"successful"* ]] || [[ $result == "" ]]; then
        echo "✅ Quota available"
        available_regions+=("$region")
    else
        echo "⚠️  Unknown status (might have quota)"
        available_regions+=("$region")
    fi
done

echo ""
echo "📊 Summary:"
echo "=================================================="

if [ ${#available_regions[@]} -eq 0 ]; then
    echo "❌ No regions found with available quota."
    echo "💡 Recommendations:"
    echo "   1. Contact Azure support to increase your quota"
    echo "   2. Try a different SKU (like F1 for free tier)"
    echo "   3. Use a different subscription type"
else
    echo "✅ Regions with likely available quota:"
    for region in "${available_regions[@]}"; do
        echo "   - $region"
    done
    echo ""
    echo "💡 Update your terraform.tfvars file with one of these regions:"
    echo "   location = \"${available_regions[0]}\""
fi

echo ""
echo "🧹 Cleaning up temporary resource group..."
az group delete --name "$test_rg" --yes --no-wait --output none

echo "✅ Quota check completed!" 