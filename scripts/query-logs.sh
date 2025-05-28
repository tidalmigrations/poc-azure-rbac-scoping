#!/bin/bash

# Azure RBAC POC - Query Activity Logs
# This script runs KQL queries against the Log Analytics workspace

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

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -s, --service-principal-id ID    Service principal object ID to filter by"
    echo "  -q, --query QUERY_FILE          KQL query file to execute (default: permission-analysis.kql)"
    echo "  -t, --time-range HOURS           Hours to look back (default: 24)"
    echo "  -o, --output FORMAT              Output format: table, json, csv (default: table)"
    echo "  -f, --file OUTPUT_FILE           Save output to file"
    echo "  -l, --list-queries               List available query files"
    echo "  -h, --help                       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -s 12345678-1234-1234-1234-123456789012"
    echo "  $0 -q terraform-specific.kql -s 12345678-1234-1234-1234-123456789012"
    echo "  $0 -s 12345678-1234-1234-1234-123456789012 -o json -f results.json"
}

# Default values
QUERY_FILE="permission-analysis.kql"
TIME_RANGE_HOURS=24
OUTPUT_FORMAT="table"
OUTPUT_FILE=""
SERVICE_PRINCIPAL_ID=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--service-principal-id)
            SERVICE_PRINCIPAL_ID="$2"
            shift 2
            ;;
        -q|--query)
            QUERY_FILE="$2"
            shift 2
            ;;
        -t|--time-range)
            TIME_RANGE_HOURS="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -f|--file)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -l|--list-queries)
            echo "Available query files:"
            ls -1 scripts/queries/*.kql 2>/dev/null | sed 's|scripts/queries/||' || echo "No query files found"
            exit 0
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check if configuration file exists
CONFIG_FILE="config/logging-config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "Logging configuration not found. Please run ./scripts/deploy-logging.sh first."
    exit 1
fi

# Read configuration
WORKSPACE_ID=$(jq -r '.workspace_id' "$CONFIG_FILE")
if [ "$WORKSPACE_ID" = "null" ] || [ -z "$WORKSPACE_ID" ]; then
    print_error "Invalid workspace ID in configuration file"
    exit 1
fi

# Check if query file exists
QUERY_PATH="scripts/queries/$QUERY_FILE"
if [ ! -f "$QUERY_PATH" ]; then
    print_error "Query file not found: $QUERY_PATH"
    print_status "Available queries:"
    ls -1 scripts/queries/*.kql 2>/dev/null | sed 's|scripts/queries/||' || echo "No query files found"
    exit 1
fi

# If no service principal ID provided, try to get it from Azure CLI
if [ -z "$SERVICE_PRINCIPAL_ID" ]; then
    print_warning "No service principal ID provided. Attempting to detect from current context..."
    
    # Try to get service principal from current login
    CURRENT_USER=$(az account show --query user.name -o tsv 2>/dev/null || echo "")
    if [[ "$CURRENT_USER" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        SERVICE_PRINCIPAL_ID="$CURRENT_USER"
        print_status "Detected service principal ID: $SERVICE_PRINCIPAL_ID"
    else
        print_error "Could not detect service principal ID. Please provide it with -s option."
        echo "You can find it by running: az ad sp list --display-name 'your-sp-name' --query '[].id' -o tsv"
        exit 1
    fi
fi

print_status "Querying Log Analytics workspace..."
print_status "Workspace ID: $WORKSPACE_ID"
print_status "Service Principal ID: $SERVICE_PRINCIPAL_ID"
print_status "Query file: $QUERY_FILE"
print_status "Time range: $TIME_RANGE_HOURS hours"

# Read and prepare the query
QUERY_CONTENT=$(cat "$QUERY_PATH")

# Replace placeholders in the query
START_TIME=$(date -u -d "$TIME_RANGE_HOURS hours ago" +"%Y-%m-%dT%H:%M:%SZ")
END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

QUERY_CONTENT=$(echo "$QUERY_CONTENT" | sed "s/{service-principal-id}/$SERVICE_PRINCIPAL_ID/g")
QUERY_CONTENT=$(echo "$QUERY_CONTENT" | sed "s/{start-time}/$START_TIME/g")
QUERY_CONTENT=$(echo "$QUERY_CONTENT" | sed "s/{end-time}/$END_TIME/g")

# Extract the first query (before the first comment starting with //)
FIRST_QUERY=$(echo "$QUERY_CONTENT" | awk '/^\/\/ Query [2-9]/ {exit} {print}' | grep -v '^//' | grep -v '^$' | head -20)

if [ -z "$FIRST_QUERY" ]; then
    print_error "No valid query found in $QUERY_FILE"
    exit 1
fi

print_status "Executing query..."

# Build the az command
AZ_CMD="az monitor log-analytics query --workspace '$WORKSPACE_ID' --analytics-query '$FIRST_QUERY' --output $OUTPUT_FORMAT"

# Execute the query
if [ -n "$OUTPUT_FILE" ]; then
    eval "$AZ_CMD" > "$OUTPUT_FILE"
    if [ $? -eq 0 ]; then
        print_success "Query results saved to $OUTPUT_FILE"
        print_status "Preview (first 10 lines):"
        head -10 "$OUTPUT_FILE"
    else
        print_error "Query execution failed"
        exit 1
    fi
else
    eval "$AZ_CMD"
    if [ $? -eq 0 ]; then
        print_success "Query executed successfully"
    else
        print_error "Query execution failed"
        exit 1
    fi
fi

print_status "Query completed. Time range: $START_TIME to $END_TIME" 