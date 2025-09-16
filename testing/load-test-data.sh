#!/bin/bash

# ============================================================================
# SHARED GRAPHQL TEST DATA LOADER
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Loads tier-specific test data for GraphQL API testing
# Usage: ./load-test-data.sh <tier> <environment> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../commands/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Load Test Data

DESCRIPTION:
    Loads tier-specific test data for GraphQL API testing.
    Delegates to the shared database system's test data loading
    functionality with proper tier-specific data sets.

USAGE:
    ./load-test-data.sh <tier> <environment> [options]

ARGUMENTS:
    tier           One of: admin, operator, member
    environment    Either 'production' or 'development'

OPTIONS:
    -h, --help     Show this help message

EXAMPLES:
    ./load-test-data.sh member development    # Load member test data
    ./load-test-data.sh admin production      # Load admin production test data

NOTES:
    - Delegates to shared-database-sql load system
    - Uses tier-specific test data from respective repositories
    - Handles foreign key dependencies automatically
    - Safe to run multiple times (uses upsert patterns)
EOF
}

# Parse command line arguments
TIER=""
ENVIRONMENT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
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

section_header "📥 SHARED GRAPHQL TEST DATA LOADER - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "Database: $DB_TIER_DATABASE at localhost:$DB_TIER_PORT"

# Start timing
start_timer

# Delegate to shared database system
log_progress "Delegating to shared database test data loader..."

SHARED_DB_LOADER="../shared-database-sql/testing/load-test-data.sh"

if [[ ! -f "$SHARED_DB_LOADER" ]]; then
    die "Shared database test data loader not found: $SHARED_DB_LOADER"
fi

# Execute shared database loader with tier parameters
log_detail "Executing: $SHARED_DB_LOADER $TIER $ENVIRONMENT"

"$SHARED_DB_LOADER" "$TIER" "$ENVIRONMENT"

local load_exit_code=$?

if [[ $load_exit_code -eq 0 ]]; then
    log_success "Test data loaded successfully"
else
    die "Test data loading failed with exit code $load_exit_code"
fi

# Verify data was loaded by checking some basic counts
log_progress "Verifying test data was loaded..."

local db_url="postgresql://$DB_TIER_USER:$DB_TIER_PASSWORD@localhost:$DB_TIER_PORT/$DB_TIER_DATABASE"

# Get table count with data
local tables_with_data=$(psql "$db_url" -t -c "
    SELECT COUNT(*)
    FROM (
        SELECT schemaname, tablename
        FROM pg_tables 
        WHERE schemaname NOT IN ('information_schema', 'pg_catalog', 'hdb_catalog', 'public')
    ) t
    JOIN LATERAL (
        SELECT CASE WHEN EXISTS (
            SELECT 1 FROM pg_class c 
            JOIN pg_namespace n ON n.oid = c.relnamespace 
            WHERE n.nspname = t.schemaname AND c.relname = t.tablename 
            AND c.reltuples > 0
        ) THEN 1 ELSE 0 END as has_data
    ) d ON d.has_data = 1
" 2>/dev/null | xargs)

if [[ "$tables_with_data" =~ ^[0-9]+$ && "$tables_with_data" -gt 0 ]]; then
    log_success "Verified: $tables_with_data tables contain test data"
else
    log_warning "Could not verify test data or no data found"
fi

# Success summary
print_operation_summary "Test Data Loading" "$TIER" "$ENVIRONMENT"

log_success "Test data loaded successfully!"
log_info "Ready for GraphQL API testing"
# Return success exit code
exit 0
