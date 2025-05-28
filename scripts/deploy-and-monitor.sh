#!/bin/bash
# Provided by Tidal <support@tidalcloud.com>

# Azure RBAC POC - Deploy and Monitor Script
# Phase 3: Baseline Deployment & Capture
# This script deploys the demo app with broad permissions and captures all required actions

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform/demo-app"
LOG_DIR="$PROJECT_ROOT/logs"
CONFIG_FILE="$PROJECT_ROOT/config/azure-config.env"

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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed and logged in
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        error "Terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Load configuration from multiple sources (in order of precedence)
    load_configuration
    
    # Verify required variables
    if [[ -z "$AZURE_SUBSCRIPTION_ID" || -z "$SERVICE_PRINCIPAL_ID" ]]; then
        error "Required configuration variables not found"
        error "Please ensure AZURE_SUBSCRIPTION_ID and SERVICE_PRINCIPAL_ID are set"
        error "Check .env, .env.terraform, or config/azure-config.env files"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Load configuration from multiple sources
load_configuration() {
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
    
    if [[ -n "$ARM_CLIENT_SECRET" && -z "$SERVICE_PRINCIPAL_SECRET" ]]; then
        export SERVICE_PRINCIPAL_SECRET="$ARM_CLIENT_SECRET"
        log "Mapped ARM_CLIENT_SECRET to SERVICE_PRINCIPAL_SECRET"
    fi
    
    # Get the service principal object ID for activity log queries
    if [[ -n "$SERVICE_PRINCIPAL_ID" ]]; then
        log "Getting service principal object ID for activity log queries..."
        SERVICE_PRINCIPAL_OBJECT_ID=$(az ad sp show --id "$SERVICE_PRINCIPAL_ID" --query "id" --output tsv 2>/dev/null)
        if [[ -n "$SERVICE_PRINCIPAL_OBJECT_ID" ]]; then
            export SERVICE_PRINCIPAL_OBJECT_ID
            log "Service Principal Object ID: ${SERVICE_PRINCIPAL_OBJECT_ID:0:8}..."
        else
            warning "Could not retrieve service principal object ID"
        fi
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
    
    if [[ -n "$AZURE_TENANT_ID" ]]; then
        log "  AZURE_TENANT_ID: ${AZURE_TENANT_ID:0:8}..."
    else
        log "  AZURE_TENANT_ID: (not set)"
    fi
    
    # Validate that we have the minimum required configuration
    if [[ -z "$AZURE_SUBSCRIPTION_ID" ]]; then
        warning "AZURE_SUBSCRIPTION_ID not found in any configuration file"
    fi
    
    if [[ -z "$SERVICE_PRINCIPAL_ID" ]]; then
        warning "SERVICE_PRINCIPAL_ID not found in any configuration file"
    fi
}

# Create logs directory
setup_logging() {
    log "Setting up logging directory..."
    mkdir -p "$LOG_DIR"
    
    # Create deployment log file with timestamp
    DEPLOYMENT_LOG="$LOG_DIR/deployment-$(date +'%Y%m%d-%H%M%S').log"
    export DEPLOYMENT_LOG
    
    success "Logging setup complete: $DEPLOYMENT_LOG"
}

# Get current service principal permissions
check_current_permissions() {
    log "Checking current service principal permissions..."
    
    # Get current role assignments
    az role assignment list \
        --assignee "$SERVICE_PRINCIPAL_ID" \
        --subscription "$AZURE_SUBSCRIPTION_ID" \
        --output table | tee "$LOG_DIR/current-permissions.txt"
    
    success "Current permissions saved to $LOG_DIR/current-permissions.txt"
}

# Clean slate deployment
clean_existing_resources() {
    log "Ensuring clean slate for accurate permission capture..."
    
    cd "$TERRAFORM_DIR"
    
    # Check if state file exists
    if [[ -f "terraform.tfstate" ]]; then
        warning "Existing Terraform state found. Destroying resources for clean deployment..."
        
        # Initialize Terraform if needed
        terraform init -input=false
        
        # Destroy existing resources
        if terraform destroy -auto-approve | tee -a "$DEPLOYMENT_LOG"; then
            success "Existing resources destroyed successfully"
        else
            error "Failed to destroy existing resources"
            exit 1
        fi
        
        # Wait for cleanup to complete
        log "Waiting 60 seconds for cleanup to complete..."
        sleep 60
    else
        log "No existing state found. Proceeding with fresh deployment."
    fi
}

# Deploy demo application with monitoring
deploy_with_monitoring() {
    log "Starting monitored deployment..."
    
    cd "$TERRAFORM_DIR"
    
    # Record start time for log analysis
    START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "DEPLOYMENT_START_TIME=$START_TIME" >> "$DEPLOYMENT_LOG"
    
    log "Deployment start time: $START_TIME"
    
    # Initialize Terraform
    log "Initializing Terraform..."
    if terraform init -input=false | tee -a "$DEPLOYMENT_LOG"; then
        success "Terraform initialization completed"
    else
        error "Terraform initialization failed"
        exit 1
    fi
    
    # Plan deployment
    log "Creating Terraform plan..."
    if terraform plan -out=tfplan | tee -a "$DEPLOYMENT_LOG"; then
        success "Terraform plan created successfully"
    else
        error "Terraform plan failed"
        exit 1
    fi
    
    # Apply deployment
    log "Applying Terraform configuration..."
    if terraform apply tfplan | tee -a "$DEPLOYMENT_LOG"; then
        success "Terraform deployment completed successfully"
    else
        error "Terraform deployment failed"
        exit 1
    fi
    
    # Record end time
    END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "DEPLOYMENT_END_TIME=$END_TIME" >> "$DEPLOYMENT_LOG"
    
    log "Deployment end time: $END_TIME"
    
    # Wait for activity logs to populate
    log "Waiting 5 minutes for activity logs to populate..."
    sleep 300
    
    success "Deployment monitoring completed"
}

# Extract permissions used during deployment
extract_permissions() {
    log "Extracting permissions used during deployment..."
    
    # Extract deployment times from the log file
    local start_time=$(grep "DEPLOYMENT_START_TIME=" "$DEPLOYMENT_LOG" | cut -d'=' -f2)
    local end_time=$(grep "DEPLOYMENT_END_TIME=" "$DEPLOYMENT_LOG" | cut -d'=' -f2)
    
    if [[ -z "$start_time" || -z "$end_time" ]]; then
        error "Deployment times not found in log file: $DEPLOYMENT_LOG"
        exit 1
    fi
    
    log "Using deployment time range: $start_time to $end_time"
    
    # Call the permission extraction script
    if [[ -f "$SCRIPT_DIR/extract-permissions.sh" ]]; then
        "$SCRIPT_DIR/extract-permissions.sh" "$start_time" "$end_time"
    else
        warning "extract-permissions.sh not found. Creating basic extraction..."
        
        # Basic permission extraction using Azure CLI
        PERMISSIONS_FILE="$LOG_DIR/permissions-$(date +'%Y%m%d-%H%M%S').json"
        
        log "Querying activity logs for time range: $start_time to $end_time"
        
        # Use object ID if available, fallback to service principal ID
        local caller_id="${SERVICE_PRINCIPAL_OBJECT_ID:-$SERVICE_PRINCIPAL_ID}"
        log "Using caller ID: ${caller_id:0:8}..."
        
        az monitor activity-log list \
            --start-time "$start_time" \
            --end-time "$end_time" \
            --caller "$caller_id" \
            --status "Succeeded" \
            --output json > "$PERMISSIONS_FILE"
        
        success "Basic permissions extracted to: $PERMISSIONS_FILE"
    fi
}

# Generate deployment summary
generate_summary() {
    log "Generating deployment summary..."
    
    SUMMARY_FILE="$LOG_DIR/deployment-summary-$(date +'%Y%m%d-%H%M%S').txt"
    
    cat > "$SUMMARY_FILE" << EOF
# Azure RBAC POC - Phase 3 Deployment Summary
Generated: $(date)

## Deployment Details
- Start Time: $DEPLOYMENT_START_TIME
- End Time: $DEPLOYMENT_END_TIME
- Service Principal: $SERVICE_PRINCIPAL_ID
- Subscription: $AZURE_SUBSCRIPTION_ID

## Resources Deployed
EOF
    
    # Add Terraform outputs if available
    cd "$TERRAFORM_DIR"
    if terraform output &> /dev/null; then
        echo "" >> "$SUMMARY_FILE"
        echo "## Terraform Outputs" >> "$SUMMARY_FILE"
        terraform output >> "$SUMMARY_FILE"
    fi
    
    # Add resource group information
    echo "" >> "$SUMMARY_FILE"
    echo "## Resource Groups Created" >> "$SUMMARY_FILE"
    az group list --query "[?contains(name, 'demo')].{Name:name, Location:location}" --output table >> "$SUMMARY_FILE"
    
    success "Deployment summary saved to: $SUMMARY_FILE"
}

# Main execution
main() {
    log "Starting Azure RBAC POC - Phase 3: Baseline Deployment & Capture"
    
    check_prerequisites
    setup_logging
    check_current_permissions
    clean_existing_resources
    deploy_with_monitoring
    extract_permissions
    generate_summary
    
    success "Phase 3 deployment and monitoring completed successfully!"
    success "Check the logs directory for detailed results: $LOG_DIR"
    
    log "Next steps:"
    log "1. Review the permissions extracted in $LOG_DIR"
    log "2. Analyze the activity logs for optimization opportunities"
    log "3. Proceed to Phase 4 for policy generation"
}

# Run main function
main "$@" 