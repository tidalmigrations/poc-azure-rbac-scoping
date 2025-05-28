#!/bin/bash

# Automated Attribution Script
# Provided by Tidal <support@tidalcloud.com>
# Adds Tidal attribution to all relevant files in the project

set -e

# Configuration
ATTRIBUTION_TEXT="Provided by Tidal <support@tidalcloud.com>"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=false
VERBOSE=false

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

Automatically adds Tidal attribution to all relevant files in the project.

OPTIONS:
    -d, --dry-run       Show what would be changed without making changes
    -v, --verbose       Show detailed output
    -h, --help          Show this help message

EXAMPLES:
    $0                  Add attribution to all files
    $0 --dry-run        Preview changes without applying them
    $0 --verbose        Show detailed processing information

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
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

# Function to check if file already has attribution
has_attribution() {
    local file="$1"
    grep -q "Provided by Tidal" "$file" 2>/dev/null
}

# Function to add attribution to shell scripts
add_shell_attribution() {
    local file="$1"
    local temp_file=$(mktemp)
    
    if has_attribution "$file"; then
        print_status "$YELLOW" "  ⚠️  Already has attribution: $file"
        return 0
    fi
    
    # Read the file and add attribution after shebang and existing header
    {
        # Copy shebang if it exists
        if head -n1 "$file" | grep -q "^#!"; then
            head -n1 "$file"
            echo "# $ATTRIBUTION_TEXT"
            tail -n +2 "$file"
        else
            echo "# $ATTRIBUTION_TEXT"
            cat "$file"
        fi
    } > "$temp_file"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        mv "$temp_file" "$file"
        chmod --reference="$file" "$temp_file" 2>/dev/null || true
    else
        rm "$temp_file"
    fi
    
    print_status "$GREEN" "  ✅ Updated: $file"
}

# Function to add attribution to Terraform files
add_terraform_attribution() {
    local file="$1"
    local temp_file=$(mktemp)
    
    if has_attribution "$file"; then
        print_status "$YELLOW" "  ⚠️  Already has attribution: $file"
        return 0
    fi
    
    # Add attribution at the top of Terraform files
    {
        echo "# $ATTRIBUTION_TEXT"
        echo ""
        cat "$file"
    } > "$temp_file"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        mv "$temp_file" "$file"
    else
        rm "$temp_file"
    fi
    
    print_status "$GREEN" "  ✅ Updated: $file"
}

# Function to add attribution to JSON files
add_json_attribution() {
    local file="$1"
    
    if has_attribution "$file"; then
        print_status "$YELLOW" "  ⚠️  Already has attribution: $file"
        return 0
    fi
    
    # For JSON files, we'll add a comment field if it's a configuration object
    # or add it as a comment at the top if the JSON parser allows
    local temp_file=$(mktemp)
    
    if jq --arg attr "$ATTRIBUTION_TEXT" '. + {"_attribution": $attr}' "$file" > "$temp_file" 2>/dev/null; then
        if [[ "$DRY_RUN" == "false" ]]; then
            mv "$temp_file" "$file"
        else
            rm "$temp_file"
        fi
        print_status "$GREEN" "  ✅ Updated: $file (added _attribution field)"
    else
        # If jq fails, add as comment at top (for JSON with comments)
        {
            echo "// $ATTRIBUTION_TEXT"
            cat "$file"
        } > "$temp_file"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            mv "$temp_file" "$file"
        else
            rm "$temp_file"
        fi
        print_status "$GREEN" "  ✅ Updated: $file (added comment)"
    fi
}

# Function to add attribution to configuration files
add_config_attribution() {
    local file="$1"
    local temp_file=$(mktemp)
    
    if has_attribution "$file"; then
        print_status "$YELLOW" "  ⚠️  Already has attribution: $file"
        return 0
    fi
    
    # Add attribution at the top of config files
    {
        echo "# $ATTRIBUTION_TEXT"
        echo ""
        cat "$file"
    } > "$temp_file"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        mv "$temp_file" "$file"
    else
        rm "$temp_file"
    fi
    
    print_status "$GREEN" "  ✅ Updated: $file"
}

# Function to add attribution to markdown files
add_markdown_attribution() {
    local file="$1"
    local temp_file=$(mktemp)
    
    if has_attribution "$file"; then
        print_status "$YELLOW" "  ⚠️  Already has attribution: $file"
        return 0
    fi
    
    # Add attribution at the end of markdown files
    {
        cat "$file"
        echo ""
        echo "---"
        echo ""
        echo "## Attribution"
        echo ""
        echo "$ATTRIBUTION_TEXT"
    } > "$temp_file"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        mv "$temp_file" "$file"
    else
        rm "$temp_file"
    fi
    
    print_status "$GREEN" "  ✅ Updated: $file"
}

# Function to determine file type and add appropriate attribution
process_file() {
    local file="$1"
    local basename=$(basename "$file")
    local extension="${basename##*.}"
    
    [[ "$VERBOSE" == "true" ]] && print_status "$BLUE" "Processing: $file"
    
    # Skip certain files
    case "$basename" in
        terraform.tfstate*|*.backup|tfplan|.terraform.lock.hcl)
            [[ "$VERBOSE" == "true" ]] && print_status "$YELLOW" "  ⏭️  Skipping state/lock file: $file"
            return 0
            ;;
    esac
    
    # Handle specific files by name first
    case "$basename" in
        .gitignore|.dockerignore|.eslintignore)
            add_config_attribution "$file"
            return 0
            ;;
    esac
    
    # Determine file type and process accordingly
    case "$extension" in
        sh)
            add_shell_attribution "$file"
            ;;
        tf|tfvars)
            add_terraform_attribution "$file"
            ;;
        json)
            add_json_attribution "$file"
            ;;
        md)
            add_markdown_attribution "$file"
            ;;
        txt|env)
            add_config_attribution "$file"
            ;;
        *)
            # Check if file starts with shebang
            if head -n1 "$file" 2>/dev/null | grep -q "^#!"; then
                add_shell_attribution "$file"
            else
                [[ "$VERBOSE" == "true" ]] && print_status "$YELLOW" "  ⏭️  Skipping unknown file type: $file"
            fi
            ;;
    esac
}

# Main execution
main() {
    print_status "$BLUE" "🚀 Tidal Attribution Tool"
    print_status "$BLUE" "========================"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "$YELLOW" "🔍 DRY RUN MODE - No files will be modified"
    fi
    
    echo ""
    
    cd "$PROJECT_ROOT"
    
    # Find all relevant files
    local files_found=0
    local files_processed=0
    
    # Process specific directories and files
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
                ((files_found++))
                process_file "$file"
                ((files_processed++))
            fi
        done
    done
    
    echo ""
    print_status "$GREEN" "📊 Summary:"
    print_status "$GREEN" "   Files found: $files_found"
    print_status "$GREEN" "   Files processed: $files_processed"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        print_status "$YELLOW" "💡 Run without --dry-run to apply changes"
    else
        echo ""
        print_status "$GREEN" "✅ Attribution process complete!"
    fi
}

# Check dependencies
if ! command -v jq &> /dev/null; then
    print_status "$RED" "❌ jq is required but not installed. Please install jq first."
    exit 1
fi

# Run main function
main 