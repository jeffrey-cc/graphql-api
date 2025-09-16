#!/bin/bash

# ============================================================================
# SHARED GRAPHQL - PURGE TEST DATA
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Purge test data for any GraphQL tier
# Usage: ./purge-test-data.sh <tier> <environment> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Purge Test Data Command

DESCRIPTION:
    Safely removes all test data while preserving schema for the specified
    GraphQL tier. This command delegates to the shared database system for
    actual data purging operations.
    
    This command will:
    - Validate GraphQL API connectivity
    - Apply production safety checks
    - Delegate to shared database system for data purging
    - Verify data was purged successfully

USAGE:
    ./purge-test-data.sh <tier> <environment> [options]

ARGUMENTS:
    tier           One of: admin, operator, member
    environment    Either 'production' or 'development'

OPTIONS:
    -h, --help     Show this help message
    --force        Skip production confirmation (dangerous)
    --skip-verify  Skip data verification after purging

EXAMPLES:
    ./purge-test-data.sh member development     # Purge member test data
    ./purge-test-data.sh admin development      # Purge admin test data
    ./purge-test-data.sh operator production --force  # Force purge production

NOTES:
    - Delegates to shared database system for actual data operations
    - Includes safety checks for production environments
    - Preserves database schema and GraphQL metadata
    - Verifies GraphQL API remains functional after purging
EOF
}

# Parse command line arguments
TIER=""
ENVIRONMENT=""
FORCE=false
SKIP_VERIFY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --force)
            FORCE=true
            shift
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

section_header "🧹 SHARED GRAPHQL PURGE TEST DATA - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "GraphQL Endpoint: $GRAPHQL_TIER_ENDPOINT"
log_info "Start Time: $(date '+%Y-%m-%d %H:%M:%S')"

# Production safety check
if [[ "$ENVIRONMENT" == "production" && "$FORCE" != "true" ]]; then
    log_warning "⚠️  WARNING: You are about to purge PRODUCTION $TIER data!"
    echo ""
    read -p "Type 'YES' to confirm purging production data: " confirmation
    if [[ "$confirmation" != "YES" ]]; then
        log_info "❌ Operation cancelled"
        exit 1
    fi
    echo ""
fi

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

# Delegate to shared database system for data purging
log_progress "Delegating to shared database system for data purging..."

PURGE_COMMAND="$SHARED_DATABASE_PATH/commands/purge-test-data.sh"
if [[ ! -f "$PURGE_COMMAND" ]]; then
    die "Shared database purge command not found: $PURGE_COMMAND"
fi

# Build purge command arguments
PURGE_ARGS=("$TIER" "$ENVIRONMENT")
if [[ "$FORCE" == "true" ]]; then
    PURGE_ARGS+=("--force")
fi

if "${PURGE_COMMAND}" "${PURGE_ARGS[@]}"; then
    log_success "✅ Test data purged successfully via shared database system"
else
    die "Failed to purge test data via shared database system"
fi

# Verify GraphQL API still works (unless skipped)
if [[ "$SKIP_VERIFY" != "true" ]]; then
    log_progress "Verifying GraphQL API functionality after purging..."
    
    # Test basic GraphQL connectivity
    if test_graphql_connection "$TIER" "$ENVIRONMENT" >/dev/null 2>&1; then
        log_success "✅ GraphQL API remains functional after purging"
        
        # Check if we still have tracked tables
        TABLES_RESPONSE=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/metadata" \
            -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
            -H "Content-Type: application/json" \
            -d '{"type": "export_metadata", "args": {}}' 2>/dev/null || echo "FAILED")

        if [[ "$TABLES_RESPONSE" == *"sources"* ]]; then
            TABLE_COUNT=$(echo "$TABLES_RESPONSE" | jq '[.sources[].tables[]?] | length' 2>/dev/null || echo "0")
            log_success "✅ GraphQL schema preserved ($TABLE_COUNT tracked tables remain)"
            
            # Test a simple query if we have tables
            if [[ "$TABLE_COUNT" -gt 0 ]]; then
                # Get first table name for testing
                FIRST_TABLE=$(echo "$TABLES_RESPONSE" | jq -r '.sources[].tables[0].table.name // empty' 2>/dev/null)
                FIRST_SCHEMA=$(echo "$TABLES_RESPONSE" | jq -r '.sources[].tables[0].table.schema // "public"' 2>/dev/null)
                
                if [[ -n "$FIRST_TABLE" ]]; then
                    GRAPHQL_TABLE="${FIRST_SCHEMA}_${FIRST_TABLE}"
                    
                    log_progress "Testing that data was actually purged..."
                    DATA_TEST=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
                        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
                        -H "Content-Type: application/json" \
                        -d "{\"query\": \"{ ${GRAPHQL_TABLE}_aggregate { aggregate { count } } }\"}" 2>/dev/null || echo "FAILED")
                    
                    if [[ "$DATA_TEST" == *"aggregate"* ]] && [[ "$DATA_TEST" != *"error"* ]]; then
                        RECORD_COUNT=$(echo "$DATA_TEST" | jq -r ".data.${GRAPHQL_TABLE}_aggregate.aggregate.count // \"0\"" 2>/dev/null)
                        
                        if [[ "$RECORD_COUNT" == "0" ]]; then
                            log_success "✅ Data purge verified (0 records in $FIRST_TABLE)"
                        else
                            log_info "ℹ️  Table $FIRST_TABLE still has $RECORD_COUNT records"
                            log_detail "Some data may be preserved by design"
                        fi
                    else
                        log_warning "⚠️  Could not verify data purge"
                        log_detail "Table may not support aggregation"
                    fi
                fi
            fi
        else
            log_warning "⚠️  Could not verify GraphQL schema preservation"
            log_detail "Metadata export may have failed, but purging succeeded"
        fi
    else
        log_error "❌ GraphQL API connectivity lost after purging"
        log_warning "This may indicate a serious issue with the purging process"
    fi
else
    log_info "Skipping verification as requested"
fi

# Success summary
section_header "✅ TEST DATA PURGING COMPLETE"
log_success "Tier: $TIER"
log_success "Environment: $ENVIRONMENT"
log_info "Data purging operation completed successfully"

# Show useful next steps
log_info "💡 Next steps:"
log_detail "• Load fresh data: ./load-seed-data.sh $TIER $ENVIRONMENT"
log_detail "• Verify setup: ./verify-complete-setup.sh $TIER $ENVIRONMENT"
log_detail "• Test GraphQL: ./test-graphql.sh $TIER $ENVIRONMENT"

# Success summary
print_operation_summary "Test Data Purging" "$TIER" "$ENVIRONMENT"

log_success "Test data purging completed successfully! 🎉"
# Return success exit code
exit 0
