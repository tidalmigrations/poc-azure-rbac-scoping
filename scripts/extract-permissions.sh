#!/bin/bash

# Azure RBAC POC - Extract Permissions Script
# Phase 3: Extract permissions used during deployment from activity logs

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
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

# Usage function
usage() {
    echo "Usage: $0 <start_time> [end_time]"
    echo "  start_time: ISO 8601 format (e.g., 2024-01-15T10:00:00Z)"
    echo "  end_time:   ISO 8601 format (optional, defaults to now)"
    echo ""
    echo "Example: $0 2024-01-15T10:00:00Z 2024-01-15T11:00:00Z"
    exit 1
}

# Validate inputs
if [[ $# -lt 1 ]]; then
    usage
fi

START_TIME="$1"
END_TIME="${2:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"

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
    
    # Validate that we have the minimum required configuration
    if [[ -z "$AZURE_SUBSCRIPTION_ID" ]]; then
        warning "AZURE_SUBSCRIPTION_ID not found in any configuration file"
    fi
    
    if [[ -z "$SERVICE_PRINCIPAL_ID" ]]; then
        warning "SERVICE_PRINCIPAL_ID not found in any configuration file"
    fi
}

# Load configuration
load_configuration

# Verify required variables
if [[ -z "$AZURE_SUBSCRIPTION_ID" || -z "$SERVICE_PRINCIPAL_ID" ]]; then
    error "Required configuration variables not found"
    error "Please ensure AZURE_SUBSCRIPTION_ID and SERVICE_PRINCIPAL_ID are set"
    error "Check .env, .env.terraform, or config/azure-config.env files"
    exit 1
fi

# Create output files
TIMESTAMP=$(date +'%Y%m%d-%H%M%S')
ACTIVITY_LOG_FILE="$LOG_DIR/activity-logs-$TIMESTAMP.json"
PERMISSIONS_FILE="$LOG_DIR/permissions-analysis-$TIMESTAMP.json"
SUMMARY_FILE="$LOG_DIR/permissions-summary-$TIMESTAMP.txt"
CSV_FILE="$LOG_DIR/permissions-$TIMESTAMP.csv"

log "Extracting permissions for time range: $START_TIME to $END_TIME"
log "Service Principal: $SERVICE_PRINCIPAL_ID"

# Extract activity logs using Azure CLI
extract_activity_logs() {
    log "Extracting activity logs from Azure Monitor..."
    
    # Use object ID if available, fallback to service principal ID
    local caller_id="${SERVICE_PRINCIPAL_OBJECT_ID:-$SERVICE_PRINCIPAL_ID}"
    log "Using caller ID: ${caller_id:0:8}... (${SERVICE_PRINCIPAL_OBJECT_ID:+Object ID}${SERVICE_PRINCIPAL_OBJECT_ID:-App ID})"
    
    # Query activity logs for the service principal
    az monitor activity-log list \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --caller "$caller_id" \
        --output json > "$ACTIVITY_LOG_FILE"
    
    local log_count=$(jq length "$ACTIVITY_LOG_FILE")
    success "Extracted $log_count activity log entries to: $ACTIVITY_LOG_FILE"
}

# Extract permissions from Log Analytics if available
extract_from_log_analytics() {
    log "Attempting to extract from Log Analytics workspace..."
    
    # Check if Log Analytics workspace exists
    if [[ -n "$LOG_ANALYTICS_WORKSPACE_ID" ]]; then
        log "Using Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE_ID"
        
        # Use object ID if available, fallback to service principal ID
        local caller_id="${SERVICE_PRINCIPAL_OBJECT_ID:-$SERVICE_PRINCIPAL_ID}"
        
        # Create KQL query for permission analysis
        local kql_query="AzureActivity
| where TimeGenerated between (datetime($START_TIME) .. datetime($END_TIME))
| where Caller contains \"$caller_id\"
| where ActivityStatusValue == \"Success\"
| project TimeGenerated, OperationName, ResourceProvider, ResourceGroup, Resource, ActivityStatusValue
| order by TimeGenerated asc"
        
        # Execute query (requires az monitor log-analytics extension)
        if az extension show --name log-analytics &> /dev/null; then
            az monitor log-analytics query \
                --workspace "$LOG_ANALYTICS_WORKSPACE_ID" \
                --analytics-query "$kql_query" \
                --output json > "$LOG_DIR/log-analytics-$TIMESTAMP.json" 2>/dev/null || {
                warning "Failed to query Log Analytics workspace"
            }
        else
            warning "Log Analytics extension not installed. Install with: az extension add --name log-analytics"
        fi
    else
        warning "Log Analytics workspace ID not configured"
    fi
}

# Analyze permissions from activity logs
analyze_permissions() {
    log "Analyzing permissions from activity logs..."
    
    # Extract unique operations and resource providers
    jq -r '
    [.[] | select(.status.value == "Succeeded") | {
        operation: .operationName.value,
        resourceProvider: (.resourceId // "" | split("/") | .[4] // "Unknown"),
        resourceType: (.resourceId // "" | split("/") | .[6] // "Unknown"),
        resourceGroup: (.resourceGroupName // "Unknown"),
        timestamp: .eventTimestamp
    }] | 
    group_by(.operation) | 
    map({
        operation: .[0].operation,
        count: length,
        resourceProvider: .[0].resourceProvider,
        resourceType: .[0].resourceType,
        firstSeen: (map(.timestamp) | min),
        lastSeen: (map(.timestamp) | max)
    }) |
    sort_by(.operation)
    ' "$ACTIVITY_LOG_FILE" > "$PERMISSIONS_FILE"
    
    success "Permission analysis saved to: $PERMISSIONS_FILE"
}

# Generate CSV export
generate_csv() {
    log "Generating CSV export..."
    
    # Create CSV header
    echo "Operation,Count,Resource Provider,Resource Type,First Seen,Last Seen" > "$CSV_FILE"
    
    # Convert JSON to CSV
    jq -r '.[] | [.operation, .count, .resourceProvider, .resourceType, .firstSeen, .lastSeen] | @csv' "$PERMISSIONS_FILE" >> "$CSV_FILE"
    
    success "CSV export saved to: $CSV_FILE"
}

# Generate human-readable summary
generate_summary() {
    log "Generating permissions summary..."
    
    local total_operations=$(jq length "$PERMISSIONS_FILE")
    local unique_providers=$(jq -r '[.[].resourceProvider] | unique | length' "$PERMISSIONS_FILE")
    local unique_types=$(jq -r '[.[].resourceType] | unique | length' "$PERMISSIONS_FILE")
    
    cat > "$SUMMARY_FILE" << EOF
# Azure RBAC POC - Permissions Analysis Summary
Generated: $(date)
Analysis Period: $START_TIME to $END_TIME
Service Principal: $SERVICE_PRINCIPAL_ID

## Overview
- Total Unique Operations: $total_operations
- Unique Resource Providers: $unique_providers
- Unique Resource Types: $unique_types

## Top Operations by Frequency
EOF
    
    # Add top 20 operations by count
    jq -r '.[] | "\(.count)\t\(.operation)"' "$PERMISSIONS_FILE" | sort -nr | head -20 | while read count operation; do
        echo "- $operation ($count times)" >> "$SUMMARY_FILE"
    done
    
    cat >> "$SUMMARY_FILE" << EOF

## Resource Providers Used
EOF
    
    # Add unique resource providers
    jq -r '[.[].resourceProvider] | unique | .[]' "$PERMISSIONS_FILE" | while read provider; do
        echo "- $provider" >> "$SUMMARY_FILE"
    done
    
    cat >> "$SUMMARY_FILE" << EOF

## Recommended Actions for Phase 4
1. Review the operations list to identify essential vs. optional permissions
2. Group permissions by resource provider for custom role creation
3. Consider resource-specific scopes to further limit access
4. Test minimal permission set with a subset of operations

## Files Generated
- Activity Logs: $ACTIVITY_LOG_FILE
- Permissions Analysis: $PERMISSIONS_FILE
- CSV Export: $CSV_FILE
- This Summary: $SUMMARY_FILE
EOF
    
    success "Summary report saved to: $SUMMARY_FILE"
}

# Generate minimal role template
generate_role_template() {
    log "Generating minimal role template..."
    
    local role_file="$LOG_DIR/minimal-role-template-$TIMESTAMP.json"
    
    # Extract unique operations for role definition
    local actions=$(jq -r '[.[].operation] | unique | .[]' "$PERMISSIONS_FILE" | sed 's/^/    "/' | sed 's/$/",/' | sed '$s/,$//')
    
    cat > "$role_file" << EOF
{
  "Name": "Terraform Demo App Deployer - Generated",
  "Description": "Minimal permissions for demo app deployment - Generated from activity logs on $(date)",
  "Actions": [
$(echo "$actions")
  ],
  "NotActions": [],
  "DataActions": [],
  "NotDataActions": [],
  "AssignableScopes": [
    "/subscriptions/$AZURE_SUBSCRIPTION_ID"
  ]
}
EOF
    
    success "Minimal role template saved to: $role_file"
}

# Display results
display_results() {
    log "Permission extraction completed successfully!"
    echo ""
    success "Files generated:"
    echo "  📊 Activity Logs:      $ACTIVITY_LOG_FILE"
    echo "  🔍 Analysis:          $PERMISSIONS_FILE"
    echo "  📈 CSV Export:        $CSV_FILE"
    echo "  📋 Summary:           $SUMMARY_FILE"
    echo ""
    
    # Show quick stats
    local total_operations=$(jq length "$PERMISSIONS_FILE")
    local total_events=$(jq length "$ACTIVITY_LOG_FILE")
    
    echo "📈 Quick Stats:"
    echo "  - Total Activity Events: $total_events"
    echo "  - Unique Operations: $total_operations"
    echo "  - Time Range: $START_TIME to $END_TIME"
    echo ""
    
    # Show top 5 operations
    echo "🔝 Top 5 Operations:"
    jq -r '.[] | "\(.count)\t\(.operation)"' "$PERMISSIONS_FILE" | sort -nr | head -5 | while read count operation; do
        echo "  - $operation ($count times)"
    done
    echo ""
    
    success "Review the summary file for detailed analysis: $SUMMARY_FILE"
}

# Main execution
main() {
    log "Starting permission extraction for Azure RBAC POC"
    
    # Create logs directory if it doesn't exist
    mkdir -p "$LOG_DIR"
    
    extract_activity_logs
    extract_from_log_analytics
    analyze_permissions
    generate_csv
    generate_summary
    generate_role_template
    display_results
}

# Run main function
main "$@" 