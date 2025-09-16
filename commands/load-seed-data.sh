#!/bin/bash

# ============================================================================
# SHARED GRAPHQL - LOAD SEED DATA
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Load seed data for any GraphQL tier
# Usage: ./load-seed-data.sh <tier> <environment> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Load Seed Data Command

DESCRIPTION:
    Load seed data for the specified GraphQL tier. This command delegates
    to the shared database system for actual data loading operations.
    
    This command will:
    - Validate GraphQL API connectivity
    - Delegate to shared database seed data loading
    - Verify data was loaded successfully
    - Test GraphQL access to loaded data

USAGE:
    ./load-seed-data.sh <tier> <environment> [options]

ARGUMENTS:
    tier           One of: admin, operator, member
    environment    Either 'production' or 'development'

OPTIONS:
    -h, --help     Show this help message
    --skip-verify  Skip data verification after loading

EXAMPLES:
    ./load-seed-data.sh member development     # Load member seed data
    ./load-seed-data.sh admin production       # Load admin seed data
    ./load-seed-data.sh operator development --skip-verify

NOTES:
    - Delegates to shared database system for actual data operations
    - Verifies GraphQL API can access loaded data
    - Safe for both development and production environments
EOF
}

# Parse command line arguments
TIER=""
ENVIRONMENT=""
SKIP_VERIFY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --skip-verify)
            SKIP_VERIFY=true
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

# Load tier-specific configuration
if ! load_tier_config "$TIER" "$ENVIRONMENT"; then
    log_warning "Could not load tier configuration, using defaults"
fi

# Configure endpoint based on environment
if ! configure_endpoint "$TIER" "$ENVIRONMENT"; then
    die "Failed to configure endpoint for $TIER ($ENVIRONMENT)"
fi

section_header "📊 SHARED GRAPHQL LOAD SEED DATA - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "GraphQL Endpoint: $GRAPHQL_TIER_ENDPOINT"
log_info "Start Time: $(date '+%Y-%m-%d %H:%M:%S')"

# Start timing
start_timer

# Check GraphQL API connectivity
log_progress "Checking $TIER GraphQL API connectivity..."
if ! test_graphql_connection "$TIER" "$ENVIRONMENT" >/dev/null 2>&1; then
    die "$TIER API is not accessible at $GRAPHQL_TIER_ENDPOINT"
fi
log_success "✅ GraphQL API connectivity confirmed"

# Find shared database system path
SHARED_DATABASE_PATH=""
for db_path in "../shared-database-sql" "../../shared-database-sql" "../../../shared-database-sql"; do
    if [[ -d "$SCRIPT_DIR/$db_path" ]]; then
        SHARED_DATABASE_PATH="$(cd "$SCRIPT_DIR/$db_path" && pwd)"
        break
    fi
done

if [[ -z "$SHARED_DATABASE_PATH" ]]; then
    die "Could not find shared database system. Please ensure shared-database-sql exists."
fi

log_info "Using shared database system: $SHARED_DATABASE_PATH"

# Delegate to shared database system for seed data loading
log_progress "Delegating to shared database system for seed data loading..."

LOAD_COMMAND="$SHARED_DATABASE_PATH/commands/load-seed-data.sh"
if [[ ! -f "$LOAD_COMMAND" ]]; then
    die "Shared database load command not found: $LOAD_COMMAND"
fi

if "$LOAD_COMMAND" "$TIER" "$ENVIRONMENT"; then
    log_success "✅ Seed data loaded successfully via shared database system"
else
    die "Failed to load seed data via shared database system"
fi

# Verify data was loaded (unless skipped)
if [[ "$SKIP_VERIFY" != "true" ]]; then
    log_progress "Verifying GraphQL API can access loaded data..."
    
    # Test GraphQL introspection to see if we have tables
    TABLES_RESPONSE=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/metadata" \
        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
        -H "Content-Type: application/json" \
        -d '{"type": "export_metadata", "args": {}}' 2>/dev/null || echo "FAILED")

    if [[ "$TABLES_RESPONSE" == *"sources"* ]]; then
        TABLE_COUNT=$(echo "$TABLES_RESPONSE" | jq '[.sources[].tables[]?] | length' 2>/dev/null || echo "0")
        log_success "✅ GraphQL API has access to $TABLE_COUNT tracked tables"
        
        # Test a simple query if we have tables
        if [[ "$TABLE_COUNT" -gt 0 ]]; then
            # Get first table name for testing
            FIRST_TABLE=$(echo "$TABLES_RESPONSE" | jq -r '.sources[].tables[0].table.name // empty' 2>/dev/null)
            FIRST_SCHEMA=$(echo "$TABLES_RESPONSE" | jq -r '.sources[].tables[0].table.schema // "public"' 2>/dev/null)
            
            if [[ -n "$FIRST_TABLE" ]]; then
                GRAPHQL_TABLE="${FIRST_SCHEMA}_${FIRST_TABLE}"
                
                log_progress "Testing data access via GraphQL..."
                DATA_TEST=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
                    -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
                    -H "Content-Type: application/json" \
                    -d "{\"query\": \"{ ${GRAPHQL_TABLE}_aggregate { aggregate { count } } }\"}" 2>/dev/null || echo "FAILED")
                
                if [[ "$DATA_TEST" == *"aggregate"* ]] && [[ "$DATA_TEST" != *"error"* ]]; then
                    RECORD_COUNT=$(echo "$DATA_TEST" | jq -r ".data.${GRAPHQL_TABLE}_aggregate.aggregate.count // \"0\"" 2>/dev/null)
                    log_success "✅ GraphQL data access verified ($RECORD_COUNT records in $FIRST_TABLE)"
                else
                    log_warning "⚠️  GraphQL data access test had issues"
                    log_detail "Table may not support aggregation or may be empty"
                fi
            fi
        fi
    else
        log_warning "⚠️  Could not verify GraphQL table access"
        log_detail "Metadata export may have failed, but data loading succeeded"
    fi
else
    log_info "Skipping data verification as requested"
fi

# Success summary
section_header "✅ SEED DATA LOADING COMPLETE"
log_success "Tier: $TIER"
log_success "Environment: $ENVIRONMENT"
log_info "Data loading operation completed successfully"

# Show useful next steps
log_info "💡 Next steps:"
log_detail "• Verify setup: ./verify-complete-setup.sh $TIER $ENVIRONMENT"
log_detail "• Test GraphQL: ./test-graphql.sh $TIER $ENVIRONMENT"
log_detail "• Check connections: ./test-connections.sh $TIER $ENVIRONMENT"

# Success summary
print_operation_summary "Seed Data Loading" "$TIER" "$ENVIRONMENT"

log_success "Seed data loading completed successfully! 🎉"
# Return success exit code
exit 0
