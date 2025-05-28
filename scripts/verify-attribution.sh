#!/bin/bash

# Attribution Verification Script
# Provided by Tidal <support@tidalcloud.com>
# Verifies which files have Tidal attribution and generates a status report

set -e

# Configuration
ATTRIBUTION_TEXT="Provided by Tidal"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FORMAT="table"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Verifies Tidal attribution status across all relevant project files.

OPTIONS:
    -f, --format FORMAT Output format: table, json, csv (default: table)
    -h, --help          Show this help message

EXAMPLES:
    $0                  Show table format report
    $0 --format json    Generate JSON report
    $0 --format csv     Generate CSV report

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Function to check if file has attribution
has_attribution() {
    local file="$1"
    grep -q "$ATTRIBUTION_TEXT" "$file" 2>/dev/null
}

# Function to get file type
get_file_type() {
    local file="$1"
    local basename=$(basename "$file")
    local extension="${basename##*.}"
    
    case "$extension" in
        sh) echo "Shell Script" ;;
        tf) echo "Terraform" ;;
        tfvars) echo "Terraform Variables" ;;
        json) echo "JSON" ;;
        md) echo "Markdown" ;;
        txt) echo "Text" ;;
        env) echo "Environment" ;;
        *) 
            if head -n1 "$file" 2>/dev/null | grep -q "^#!"; then
                echo "Script"
            else
                echo "Other"
            fi
            ;;
    esac
}

# Function to generate table report
generate_table_report() {
    local files=("$@")
    local total=0
    local with_attribution=0
    local without_attribution=0
    
    print_status "$BLUE" "🔍 Tidal Attribution Status Report"
    print_status "$BLUE" "=================================="
    echo ""
    
    printf "%-50s %-15s %-10s\n" "FILE" "TYPE" "STATUS"
    printf "%-50s %-15s %-10s\n" "$(printf '%*s' 50 | tr ' ' '-')" "$(printf '%*s' 15 | tr ' ' '-')" "$(printf '%*s' 10 | tr ' ' '-')"
    
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            local file_type=$(get_file_type "$file")
            local status
            local color
            
            if has_attribution "$file"; then
                status="✅ YES"
                color="$GREEN"
                ((with_attribution++))
            else
                status="❌ NO"
                color="$RED"
                ((without_attribution++))
            fi
            
            printf "%-50s %-15s " "$file" "$file_type"
            print_status "$color" "$status"
            ((total++))
        fi
    done
    
    echo ""
    print_status "$BLUE" "📊 Summary:"
    print_status "$GREEN" "   Total files: $total"
    print_status "$GREEN" "   With attribution: $with_attribution"
    print_status "$RED" "   Without attribution: $without_attribution"
    
    if [[ $without_attribution -eq 0 ]]; then
        print_status "$GREEN" "🎉 All files have attribution!"
    else
        print_status "$YELLOW" "⚠️  $without_attribution files need attribution"
        echo ""
        print_status "$YELLOW" "💡 Run ./scripts/add-attribution.sh to add missing attributions"
    fi
}

# Function to generate JSON report
generate_json_report() {
    local files=("$@")
    local json_output='{"files":[],"summary":{}}'
    local total=0
    local with_attribution=0
    local without_attribution=0
    
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            local file_type=$(get_file_type "$file")
            local has_attr=false
            
            if has_attribution "$file"; then
                has_attr=true
                ((with_attribution++))
            else
                ((without_attribution++))
            fi
            
            json_output=$(echo "$json_output" | jq --arg file "$file" --arg type "$file_type" --argjson attr "$has_attr" \
                '.files += [{"file": $file, "type": $type, "has_attribution": $attr}]')
            ((total++))
        fi
    done
    
    json_output=$(echo "$json_output" | jq --argjson total "$total" --argjson with "$with_attribution" --argjson without "$without_attribution" \
        '.summary = {"total": $total, "with_attribution": $with, "without_attribution": $without}')
    
    echo "$json_output" | jq .
}

# Function to generate CSV report
generate_csv_report() {
    local files=("$@")
    
    echo "File,Type,Has Attribution"
    
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            local file_type=$(get_file_type "$file")
            local has_attr="No"
            
            if has_attribution "$file"; then
                has_attr="Yes"
            fi
            
            echo "$file,$file_type,$has_attr"
        fi
    done
}

# Main execution
main() {
    cd "$PROJECT_ROOT"
    
    # Collect all relevant files
    local files=()
    
    # Add specific files and patterns
    for pattern in \
        "README.md" \
        ".gitignore" \
        "scripts/*.sh" \
        "terraform/*.tf" \
        "terraform/demo-app/*.tf" \
        "terraform/demo-app/*.tfvars" \
        "terraform/logging-setup/*.tf" \
        "config/*.txt" \
        "config/*.json" \
        "config/*.env"; do
        
        for file in $pattern; do
            if [[ -f "$file" ]]; then
                files+=("$file")
            fi
        done
    done
    
    # Generate report based on format
    case "$OUTPUT_FORMAT" in
        table)
            generate_table_report "${files[@]}"
            ;;
        json)
            generate_json_report "${files[@]}"
            ;;
        csv)
            generate_csv_report "${files[@]}"
            ;;
        *)
            echo "Unknown output format: $OUTPUT_FORMAT"
            echo "Supported formats: table, json, csv"
            exit 1
            ;;
    esac
}

# Check dependencies
if ! command -v jq &> /dev/null; then
    print_status "$RED" "❌ jq is required but not installed. Please install jq first."
    exit 1
fi

# Run main function
main 