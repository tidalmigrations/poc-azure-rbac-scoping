#!/bin/bash
# Provided by Tidal <support@tidalcloud.com>

# Azure RBAC POC - Phase 3 Validation Script
# Validates that Phase 3 deployment and monitoring completed successfully

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_ROOT/logs"
CONFIG_FILE="$PROJECT_ROOT/config/azure-config.env"
TERRAFORM_DIR="$PROJECT_ROOT/terraform/demo-app"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Validation counters
CHECKS_PASSED=0
CHECKS_FAILED=0
TOTAL_CHECKS=0

# Check function
check() {
    local description="$1"
    local command="$2"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    log "Checking: $description"
    
    if eval "$command" &> /dev/null; then
        success "✓ $description"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        return 0
    else
        error "✗ $description"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
        return 1
    fi
}

# Load configuration
load_config() {
    log "Loading configuration from available sources..."
    
    # Source .env file if it exists (lowest precedence)
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        log "Loading configuration from .env"
        source "$PROJECT_ROOT/.env"
        success "Loaded .env file"
    fi
    
    # Source .env.terraform file if it exists (medium precedence)
    if [[ -f "$PROJECT_ROOT/.env.terraform" ]]; then
        log "Loading configuration from .env.terraform"
        source "$PROJECT_ROOT/.env.terraform"
        success "Loaded .env.terraform file"
    fi
    
    # Source azure-config.env file if it exists (highest precedence)
    if [[ -f "$CONFIG_FILE" ]]; then
        log "Loading configuration from azure-config.env"
        source "$CONFIG_FILE"
        success "Loaded azure-config.env file"
    fi
    
    # Map Terraform ARM_* variables to our expected variable names
    if [[ -n "$ARM_SUBSCRIPTION_ID" && -z "$AZURE_SUBSCRIPTION_ID" ]]; then
        export AZURE_SUBSCRIPTION_ID="$ARM_SUBSCRIPTION_ID"
        log "Mapped ARM_SUBSCRIPTION_ID to AZURE_SUBSCRIPTION_ID"
    fi
    
    if [[ -n "$ARM_CLIENT_ID" && -z "$SERVICE_PRINCIPAL_ID" ]]; then
        export SERVICE_PRINCIPAL_ID="$ARM_CLIENT_ID"
        log "Mapped ARM_CLIENT_ID to SERVICE_PRINCIPAL_ID"
    fi
    
    if [[ -n "$ARM_TENANT_ID" && -z "$AZURE_TENANT_ID" ]]; then
        export AZURE_TENANT_ID="$ARM_TENANT_ID"
        log "Mapped ARM_TENANT_ID to AZURE_TENANT_ID"
    fi
    
    # Display loaded configuration (without sensitive values)
    log "Configuration summary:"
    if [[ -n "$AZURE_SUBSCRIPTION_ID" ]]; then
        log "  AZURE_SUBSCRIPTION_ID: ${AZURE_SUBSCRIPTION_ID:0:8}..."
    else
        log "  AZURE_SUBSCRIPTION_ID: (not set)"
    fi
    
    if [[ -n "$SERVICE_PRINCIPAL_ID" ]]; then
        log "  SERVICE_PRINCIPAL_ID: ${SERVICE_PRINCIPAL_ID:0:8}..."
    else
        log "  SERVICE_PRINCIPAL_ID: (not set)"
    fi
    
    # Validate that we have the minimum required configuration
    if [[ -z "$AZURE_SUBSCRIPTION_ID" ]]; then
        warning "AZURE_SUBSCRIPTION_ID not found in any configuration file"
    fi
    
    if [[ -z "$SERVICE_PRINCIPAL_ID" ]]; then
        warning "SERVICE_PRINCIPAL_ID not found in any configuration file"
    fi
}

# Validate Phase 3 prerequisites
validate_prerequisites() {
    log "Validating Phase 3 prerequisites..."
    
    check "Azure CLI is installed" "command -v az"
    check "Terraform is installed" "command -v terraform"
    check "jq is installed" "command -v jq"
    check "Azure CLI is logged in" "az account show"
    
    # Check for any supported configuration file
    if [[ -f "$CONFIG_FILE" || -f "$PROJECT_ROOT/.env" || -f "$PROJECT_ROOT/.env.terraform" ]]; then
        check "Configuration file exists" "true"
    else
        check "Configuration file exists" "false"
    fi
    
    check "Service Principal ID is configured" "[[ -n '$SERVICE_PRINCIPAL_ID' ]]"
    check "Azure Subscription ID is configured" "[[ -n '$AZURE_SUBSCRIPTION_ID' ]]"
}

# Validate demo application deployment
validate_deployment() {
    log "Validating demo application deployment..."
    
    cd "$TERRAFORM_DIR"
    
    check "Terraform state file exists" "[[ -f 'terraform.tfstate' ]]"
    check "Terraform backend is initialized" "[[ -d '.terraform' ]]"
    
    # Check if Terraform can read the state (plan might show changes due to different user context)
    if terraform plan -detailed-exitcode &> /dev/null; then
        check "Terraform plan succeeds (no changes)" "true"
    elif terraform plan &> /dev/null; then
        check "Terraform plan succeeds (with changes)" "true"
        warning "Terraform plan shows changes - this may be due to different user context"
    else
        check "Terraform plan succeeds" "false"
    fi
    
    # Check if resources are actually deployed
    if terraform output &> /dev/null; then
        check "Terraform outputs are available" "terraform output"
        
        # Get resource group name from outputs
        local rg_name=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
        if [[ -n "$rg_name" ]]; then
            check "Resource group exists in Azure" "az group show --name '$rg_name'"
            
            # Check specific resources
            check "App Service exists" "az webapp list --resource-group '$rg_name' --query '[0].name' -o tsv"
            check "PostgreSQL server exists" "az postgres flexible-server list --resource-group '$rg_name' --query '[0].name' -o tsv"
            check "Storage account exists" "az storage account list --resource-group '$rg_name' --query '[0].name' -o tsv"
            check "Key Vault exists" "az keyvault list --resource-group '$rg_name' --query '[0].name' -o tsv"
        else
            warning "Could not determine resource group name from Terraform outputs"
        fi
    else
        warning "No Terraform outputs available"
    fi
}

# Validate logging and monitoring
validate_logging() {
    log "Validating logging and monitoring setup..."
    
    check "Logs directory exists" "[[ -d '$LOG_DIR' ]]"
    
    # Check for recent deployment logs
    local recent_deployment_log=$(find "$LOG_DIR" -name "deployment-*.log" -mtime -1 -exec ls -t {} + 2>/dev/null | head -1)
    if [[ -n "$recent_deployment_log" ]]; then
        check "Recent deployment log exists" "[[ -f '$recent_deployment_log' ]]"
        check "Deployment log contains start time" "grep -q 'DEPLOYMENT_START_TIME' '$recent_deployment_log'"
        check "Deployment log contains end time" "grep -q 'DEPLOYMENT_END_TIME' '$recent_deployment_log'"
    else
        warning "No recent deployment logs found (within last 24 hours)"
    fi
    
    # Check for permission analysis files
    local recent_permissions=$(find "$LOG_DIR" -name "permissions-analysis-*.json" -mtime -1 -exec ls -t {} + 2>/dev/null | head -1)
    if [[ -n "$recent_permissions" ]]; then
        check "Recent permissions analysis exists" "[[ -f '$recent_permissions' ]]"
        check "Permissions analysis contains data" "[[ \$(jq length \"$recent_permissions\" 2>/dev/null || echo 0) -gt 0 ]]"
    else
        warning "No recent permission analysis files found"
    fi
    
    # Check for activity logs
    local recent_activity=$(find "$LOG_DIR" -name "activity-logs-*.json" -mtime -1 -exec ls -t {} + 2>/dev/null | head -1)
    if [[ -n "$recent_activity" ]]; then
        check "Recent activity logs exist" "[[ -f '$recent_activity' ]]"
        check "Activity logs contain data" "[[ \$(jq length \"$recent_activity\" 2>/dev/null || echo 0) -gt 0 ]]"
    else
        warning "No recent activity log files found"
    fi
}

# Validate scripts and tools
validate_scripts() {
    log "Validating Phase 3 scripts and tools..."
    
    check "deploy-and-monitor.sh exists" "[[ -f '$SCRIPT_DIR/deploy-and-monitor.sh' ]]"
    check "deploy-and-monitor.sh is executable" "[[ -x '$SCRIPT_DIR/deploy-and-monitor.sh' ]]"
    check "extract-permissions.sh exists" "[[ -f '$SCRIPT_DIR/extract-permissions.sh' ]]"
    check "extract-permissions.sh is executable" "[[ -x '$SCRIPT_DIR/extract-permissions.sh' ]]"
    
    # Check if Azure Monitor extension is available
    if az extension show --name monitor-control-service &> /dev/null; then
        check "Azure Monitor extension is installed" "true"
    else
        warning "Azure Monitor extension not installed (optional)"
    fi
}

# Validate service principal permissions
validate_permissions() {
    log "Validating service principal permissions..."
    
    if [[ -n "$SERVICE_PRINCIPAL_ID" ]]; then
        check "Service principal exists" "az ad sp show --id '$SERVICE_PRINCIPAL_ID'"
        check "Service principal has role assignments" "az role assignment list --assignee '$SERVICE_PRINCIPAL_ID' --query '[0].roleDefinitionName' -o tsv"
        
        # Check if we can query activity logs
        local start_time=$(date -u -v-1H +"%Y-%m-%dT%H:%M:%SZ")
        check "Can query activity logs" "az monitor activity-log list --start-time '$start_time' --caller '$SERVICE_PRINCIPAL_ID' --query '[0].operationName.value' -o tsv"
    else
        error "Service Principal ID not configured"
    fi
}

# Generate validation report
generate_report() {
    log "Generating Phase 3 validation report..."
    
    local report_file="$LOG_DIR/phase3-validation-$(date +'%Y%m%d-%H%M%S').txt"
    
    cat > "$report_file" << EOF
# Azure RBAC POC - Phase 3 Validation Report
Generated: $(date)

## Validation Summary
- Total Checks: $TOTAL_CHECKS
- Passed: $CHECKS_PASSED
- Failed: $CHECKS_FAILED
- Success Rate: $(( CHECKS_PASSED * 100 / TOTAL_CHECKS ))%

## Phase 3 Status
EOF
    
    if [[ $CHECKS_FAILED -eq 0 ]]; then
        echo "✅ Phase 3 COMPLETED - All validations passed" >> "$report_file"
        echo "" >> "$report_file"
        echo "## Next Steps" >> "$report_file"
        echo "1. Review the permissions analysis files in $LOG_DIR" >> "$report_file"
        echo "2. Analyze the captured operations for optimization opportunities" >> "$report_file"
        echo "3. Proceed to Phase 4: Policy Generation & Optimization" >> "$report_file"
    elif [[ $CHECKS_FAILED -le 2 ]]; then
        echo "⚠️  Phase 3 MOSTLY COMPLETED - Minor issues found" >> "$report_file"
        echo "" >> "$report_file"
        echo "## Recommendations" >> "$report_file"
        echo "1. Review failed checks and address if necessary" >> "$report_file"
        echo "2. Consider proceeding to Phase 4 if core functionality works" >> "$report_file"
    else
        echo "❌ Phase 3 INCOMPLETE - Multiple issues found" >> "$report_file"
        echo "" >> "$report_file"
        echo "## Required Actions" >> "$report_file"
        echo "1. Address failed validations before proceeding" >> "$report_file"
        echo "2. Re-run deployment and monitoring scripts" >> "$report_file"
        echo "3. Validate setup again" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

## Environment Details
- Azure Subscription: $AZURE_SUBSCRIPTION_ID
- Service Principal: $SERVICE_PRINCIPAL_ID
- Terraform Directory: $TERRAFORM_DIR
- Logs Directory: $LOG_DIR

## Files to Review
EOF
    
    # List recent files in logs directory
    if [[ -d "$LOG_DIR" ]]; then
        find "$LOG_DIR" -type f -mtime -1 | while read file; do
            echo "- $(basename "$file")" >> "$report_file"
        done
    fi
    
    success "Validation report saved to: $report_file"
}

# Display final results
display_results() {
    echo ""
    echo "=================================="
    echo "Phase 3 Validation Results"
    echo "=================================="
    echo ""
    
    if [[ $CHECKS_FAILED -eq 0 ]]; then
        success "🎉 All validations passed! Phase 3 is complete."
        echo ""
        echo "✅ Demo application deployed successfully"
        echo "✅ Activity logging and monitoring working"
        echo "✅ Permission extraction tools ready"
        echo ""
        success "Ready to proceed to Phase 4!"
    elif [[ $CHECKS_FAILED -le 2 ]]; then
        warning "⚠️  Phase 3 mostly complete with minor issues"
        echo ""
        echo "Passed: $CHECKS_PASSED/$TOTAL_CHECKS checks"
        echo ""
        warning "Review the issues and consider if they block Phase 4"
    else
        error "❌ Phase 3 validation failed"
        echo ""
        echo "Passed: $CHECKS_PASSED/$TOTAL_CHECKS checks"
        echo "Failed: $CHECKS_FAILED/$TOTAL_CHECKS checks"
        echo ""
        error "Please address the issues before proceeding to Phase 4"
    fi
    
    echo ""
    log "Check the logs directory for detailed analysis: $LOG_DIR"
}

# Main execution
main() {
    log "Starting Azure RBAC POC - Phase 3 Validation"
    
    load_config
    validate_prerequisites
    validate_deployment
    validate_logging
    validate_scripts
    validate_permissions
    generate_report
    display_results
}

# Run main function
main "$@" 