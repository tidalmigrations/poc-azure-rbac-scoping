#!/bin/bash
# Provided by Tidal <support@tidalcloud.com>

# Azure RBAC POC - Validate Logging Setup
# This script validates that the logging infrastructure is working correctly

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

# Validation counters
TOTAL_CHECKS=0
PASSED_CHECKS=0

# Function to run a validation check
run_check() {
    local check_name="$1"
    local check_command="$2"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    print_status "Checking: $check_name"
    
    if eval "$check_command" > /dev/null 2>&1; then
        print_success "✓ $check_name"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        print_error "✗ $check_name"
        return 1
    fi
}

print_status "Starting logging infrastructure validation..."
echo

# Check 1: Configuration file exists
run_check "Configuration file exists" "[ -f 'config/logging-config.json' ]"

if [ -f "config/logging-config.json" ]; then
    # Read configuration
    WORKSPACE_ID=$(jq -r '.workspace_id' config/logging-config.json 2>/dev/null || echo "")
    WORKSPACE_NAME=$(jq -r '.workspace_name' config/logging-config.json 2>/dev/null || echo "")
    RESOURCE_GROUP=$(jq -r '.resource_group' config/logging-config.json 2>/dev/null || echo "")
    
    # Check 2: Configuration is valid JSON
    run_check "Configuration is valid JSON" "jq . config/logging-config.json"
    
    # Check 3: Workspace ID is not empty
    run_check "Workspace ID is configured" "[ -n '$WORKSPACE_ID' ]"
    
    # Check 4: Azure CLI is available and logged in
    run_check "Azure CLI is available and logged in" "az account show"
    
    if [ -n "$WORKSPACE_ID" ]; then
        # Check 5: Log Analytics workspace exists
        run_check "Log Analytics workspace exists" "az monitor log-analytics workspace show --workspace-name '$WORKSPACE_NAME' --resource-group '$RESOURCE_GROUP'"
        
        # Check 6: Can query the workspace
        run_check "Can query Log Analytics workspace" "az monitor log-analytics query --workspace '$WORKSPACE_ID' --analytics-query 'AzureActivity | take 1'"
        
        # Check 7: Activity logs are flowing (check for recent data)
        RECENT_LOGS=$(az monitor log-analytics query --workspace "$WORKSPACE_ID" --analytics-query "AzureActivity | where TimeGenerated > ago(1h) | count" --output tsv 2>/dev/null | tail -1 || echo "0")
        if [ "$RECENT_LOGS" -gt 0 ]; then
            print_success "✓ Activity logs are flowing ($RECENT_LOGS entries in last hour)"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
        else
            print_warning "⚠ No recent activity logs found (this is normal for new deployments)"
        fi
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        
        # Check 8: Diagnostic settings exist
        SUBSCRIPTION_ID=$(az account show --query id -o tsv)
        run_check "Subscription diagnostic settings exist" "az monitor diagnostic-settings list --resource '/subscriptions/$SUBSCRIPTION_ID' --query '[?name==\"activity-log-to-law\"]' | jq '. | length > 0'"
    fi
else
    print_error "Configuration file not found. Please run ./scripts/deploy-logging.sh first."
fi

# Check 9: Query files exist
run_check "KQL query files exist" "[ -f 'scripts/queries/permission-analysis.kql' ] && [ -f 'scripts/queries/terraform-specific.kql' ]"

# Check 10: Scripts are executable
run_check "Scripts are executable" "[ -x 'scripts/deploy-logging.sh' ] && [ -x 'scripts/query-logs.sh' ]"

echo
print_status "Validation Summary:"
echo "  Total checks: $TOTAL_CHECKS"
echo "  Passed: $PASSED_CHECKS"
echo "  Failed: $((TOTAL_CHECKS - PASSED_CHECKS))"

if [ $PASSED_CHECKS -eq $TOTAL_CHECKS ]; then
    print_success "All validation checks passed! Logging infrastructure is ready."
    echo
    print_status "Next steps:"
    echo "  1. Deploy demo application: cd terraform/demo-app && terraform apply"
    echo "  2. Wait 5-10 minutes for activity logs to populate"
    echo "  3. Query logs: ./scripts/query-logs.sh -s YOUR_SERVICE_PRINCIPAL_ID"
    echo "  4. Analyze permissions for Phase 3"
    exit 0
elif [ $PASSED_CHECKS -gt $((TOTAL_CHECKS / 2)) ]; then
    print_warning "Most checks passed, but some issues were found."
    echo
    print_status "Common solutions:"
    echo "  - Wait 5-10 minutes for diagnostic settings to take effect"
    echo "  - Ensure you have proper permissions on the subscription"
    echo "  - Check that the Log Analytics workspace was deployed successfully"
    exit 1
else
    print_error "Multiple validation checks failed. Please review the setup."
    echo
    print_status "Troubleshooting steps:"
    echo "  1. Ensure you're logged in to Azure: az login"
    echo "  2. Check your subscription: az account show"
    echo "  3. Re-run the deployment: ./scripts/deploy-logging.sh"
    echo "  4. Check Azure portal for any deployment errors"
    exit 2
fi 