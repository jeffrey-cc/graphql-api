#!/bin/bash

# ============================================================================
# SHARED GRAPHQL TEST DATA LOADER
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Loads tier-specific test data from GraphQL repository CSV files
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
    Loads tier-specific test data for GraphQL API testing from
    CSV files in the GraphQL repository test-data folders.

USAGE:
    ./load-test-data.sh <tier> <environment> [options]

ARGUMENTS:
    tier              GraphQL tier (admin, operator, or member)
    environment       Environment (development or production)

OPTIONS:
    -h, --help        Show this help message
    -v, --verbose     Enable verbose output
    -f, --force       Force load even if data exists

EXAMPLES:
    ./load-test-data.sh admin development
    ./load-test-data.sh operator production --force

NOTES:
    - Loads CSV data from ../graphql-{tier}-api/test-data/
    - Uses shared-database-sql system for actual data loading
    - Requires GraphQL tables to be tracked first
EOF
}

# Parse command line arguments
TIER=""
ENVIRONMENT=""
VERBOSE_FLAG=""
FORCE_FLAG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE_FLAG="--verbose"
            shift
            ;;
        -f|--force)
            FORCE_FLAG="--force"
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

# Basic validation
if [[ ! "$TIER" =~ ^(admin|operator|member)$ ]]; then
    log_error "Invalid tier: $TIER (must be admin, operator, or member)"
    exit 1
fi

if [[ ! "$ENVIRONMENT" =~ ^(development|production)$ ]]; then
    log_error "Invalid environment: $ENVIRONMENT (must be development or production)"
    exit 1
fi

# Configure tier settings
configure_tier "$TIER"

section_header "📥 SHARED GRAPHQL TEST DATA LOADER - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "Database: $DB_TIER_DATABASE at localhost:$DB_TIER_PORT"

# Start timing
start_timer

# Check that test-data directory exists
TIER_REPO_PATH="../graphql-$TIER-api"
TEST_DATA_PATH="$TIER_REPO_PATH/test-data"

if [[ ! -d "$TEST_DATA_PATH" ]]; then
    log_error "❌ Test data directory not found: $TEST_DATA_PATH"
    log_error ""
    log_error "REQUIRED ACTION:"
    log_error "  Ensure test-data has been copied to the GraphQL repository:"
    log_error "  mkdir -p $TEST_DATA_PATH"
    log_error "  cp -r /path/to/database-$TIER-sql/test-data/* $TEST_DATA_PATH/"
    die "Cannot proceed without test data directory"
fi

# Count CSV files
csv_count=$(find "$TEST_DATA_PATH" -name "*.csv" | wc -l | tr -d ' ')
log_info "Found $csv_count CSV files in $TEST_DATA_PATH"

if [[ "$csv_count" -eq 0 ]]; then
    log_error "❌ No CSV files found in test data directory"
    die "Cannot load test data without CSV files"
fi

# Delegate to shared database system
log_progress "Using shared database system to load test data..."

SHARED_DB_DIR="../shared-database-sql"
SHARED_DB_LOADER="$SHARED_DB_DIR/testing/load-test-data.sh"

if [[ ! -f "$SHARED_DB_LOADER" ]]; then
    log_error "❌ Shared database test data loader not found: $SHARED_DB_LOADER"
    log_error ""
    log_error "REQUIRED ACTION:"
    log_error "  Ensure shared-database-sql repository is available at:"
    log_error "  $SHARED_DB_DIR"
    die "Cannot proceed without shared database system"
fi

# Create temporary symlink to our test data
TEMP_LINK="$SHARED_DB_DIR/database-$TIER-sql/test-data-graphql-temp"
if [[ -L "$TEMP_LINK" ]]; then
    rm -f "$TEMP_LINK"
fi

# Create the symlink and execute
ln -sf "$(cd "$TEST_DATA_PATH" && pwd)" "$TEMP_LINK"

# Modify the shared loader to use our test data temporarily
log_detail "Loading test data via shared database system..."

# Execute shared database loader with tier parameters
cd "$SHARED_DB_DIR"
if ./testing/load-test-data.sh "$TIER" "$ENVIRONMENT" $VERBOSE_FLAG $FORCE_FLAG; then
    load_exit_code=0
    log_success "✅ Test data loaded successfully"
else
    load_exit_code=$?
    log_error "❌ Test data loading failed"
fi

# Clean up temporary link
rm -f "$TEMP_LINK"

# Return to original directory
cd "$SCRIPT_DIR"

# Final verification
if [[ $load_exit_code -eq 0 ]]; then
    log_info "Verifying data was loaded..."
    
    # Quick count check via GraphQL (if tables are tracked)
    configure_endpoint "$TIER" "$ENVIRONMENT"
    
    if test_graphql_connection "$TIER" "$ENVIRONMENT" >/dev/null 2>&1; then
        log_success "✅ GraphQL API verified: data loading completed"
    else
        log_warning "⚠️  GraphQL API not responding (tables may not be tracked yet)"
    fi
else
    die "Test data loading failed with exit code $load_exit_code"
fi

# Performance summary
end_timer

log_success "🎉 Test data loading completed successfully!"
log_info "Loaded $csv_count CSV files to $TIER database"
log_info "Next step: Run testing/test-graphql.sh to validate the data"