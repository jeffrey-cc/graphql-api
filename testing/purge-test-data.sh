#!/bin/bash

# ============================================================================
# SHARED GRAPHQL DATA PURGE
# Community Connect Tech - Shared GraphQL API System  
# ============================================================================
# Purges test data from database while preserving schema and structure
# Usage: ./purge-test-data.sh <tier> <environment> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../commands/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Purge Test Data

DESCRIPTION:
    Purges test data from database while preserving schema and structure.
    Uses the shared database system's purge functionality with proper
    foreign key dependency handling.

USAGE:
    ./purge-test-data.sh <tier> <environment> [options]

ARGUMENTS:
    tier           One of: admin, operator, member
    environment    Either 'production' or 'development'

OPTIONS:
    -h, --help     Show this help message
    -f, --force    Skip confirmation prompts

EXAMPLES:
    ./purge-test-data.sh member development    # Purge member test data
    ./purge-test-data.sh admin production -f   # Force purge admin production data

NOTES:
    - Delegates to shared-database-sql purge system
    - Handles foreign key dependencies automatically
    - Preserves all table structures and relationships
    - Only removes data, not schema
EOF
}

# Parse command line arguments
TIER=""
ENVIRONMENT=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        *)
            if [[ -z "$TIER" ]]; then
                TIER="$1"
            elif [[ -z "$ENVIRONMENT" ]]; then
                ENVIRONMENT="$1"
            else
                log_error "Unknown argument: $1"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$TIER" || -z "$ENVIRONMENT" ]]; then
    log_error "Both tier and environment arguments are required"
    show_help
    exit 1
fi

# Configure tier and validate
if ! configure_tier "$TIER"; then
    die "Failed to configure tier: $TIER"
fi

validate_environment "$ENVIRONMENT"

# Check prerequisites
check_prerequisites

section_header "🧹 SHARED GRAPHQL DATA PURGE - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "Database: $DB_TIER_DATABASE at localhost:$DB_TIER_PORT"

# Production safety confirmation
if [[ "$ENVIRONMENT" == "production" && "$FORCE" != "true" ]]; then
    echo ""
    log_warning "⚠️  PRODUCTION DATA PURGE REQUESTED ⚠️"
    log_warning "This will delete ALL data from the production database"
    echo ""
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirm
    
    if [[ "$confirm" != "DELETE" ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
fi

# Start timing
start_timer

# Delegate to shared database system
log_progress "Delegating to shared database purge system..."

# Calculate absolute path to database-sql (sibling of graphql-api)
SHARED_DB_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")/database-sql"
SHARED_DB_PURGE="$SHARED_DB_DIR/testing/purge-data.sh"

if [[ ! -f "$SHARED_DB_PURGE" ]]; then
    die "Shared database purge script not found: $SHARED_DB_PURGE"
fi

# Execute shared database purge with tier parameters
log_detail "Executing: $SHARED_DB_PURGE $TIER $ENVIRONMENT"

if $FORCE; then
    echo "yes" | "$SHARED_DB_PURGE" "$TIER" "$ENVIRONMENT"
else
    "$SHARED_DB_PURGE" "$TIER" "$ENVIRONMENT"
fi

local purge_exit_code=$?

if [[ $purge_exit_code -eq 0 ]]; then
    log_success "Data purge completed successfully"
else
    die "Data purge failed with exit code $purge_exit_code"
fi

# Success summary
print_operation_summary "Data Purge" "$TIER" "$ENVIRONMENT"

log_success "Test data purged successfully!"
log_info "Database schema and structure preserved"
# Return success exit code
exit 0
