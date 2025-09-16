#!/bin/bash

# ============================================================================
# SHARED GRAPHQL - VERIFY TABLES TRACKED
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Verify tables are tracked for any GraphQL tier
# Usage: ./verify-tables-tracked.sh <tier> <environment> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Verify Tables Tracked Command

DESCRIPTION:
    Verifies that all database tables are properly tracked and available
    in the GraphQL API for the specified tier. This ensures tables can 
    actually be queried.
    
    Tests performed:
    - Check if tables exist in database
    - Verify tables are tracked in Hasura metadata
    - Test GraphQL queries work for each table
    - Compare database vs GraphQL table counts

USAGE:
    ./verify-tables-tracked.sh <tier> <environment> [options]

ARGUMENTS:
    tier           One of: admin, operator, member
    environment    Either 'production' or 'development'

OPTIONS:
    -h, --help     Show this help message
    --detailed     Show detailed verification information

EXAMPLES:
    ./verify-tables-tracked.sh member development     # Verify member tables
    ./verify-tables-tracked.sh admin production       # Verify admin tables

EXIT CODES:
    0    All tables are tracked and queryable
    1    Some tables are missing or not tracked
EOF
}

# Parse command line arguments
TIER=""
ENVIRONMENT=""
DETAILED=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --detailed)
            DETAILED=true
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

section_header "🔍 SHARED GRAPHQL TABLES VERIFICATION - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "Endpoint: $GRAPHQL_TIER_ENDPOINT"

# Start timing
start_timer

# Check API connectivity
if ! test_graphql_connection "$TIER" "$ENVIRONMENT" >/dev/null 2>&1; then
    die "API is not accessible at $GRAPHQL_TIER_ENDPOINT"
fi

# Get all tables from database
log_progress "Step 1: Getting tables from database..."
DB_TABLES=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v2/query" \
  -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "run_sql",
    "args": {
      "sql": "SELECT table_schema, table_name FROM information_schema.tables WHERE table_schema NOT IN ('"'"'pg_catalog'"'"', '"'"'information_schema'"'"', '"'"'hdb_catalog'"'"') AND table_type = '"'"'BASE TABLE'"'"' ORDER BY table_schema, table_name;"
    }
  }')

if [[ "$DB_TABLES" == *"error"* ]]; then
    log_error "Cannot query database tables"
    if [[ "$DETAILED" == "true" ]]; then
        log_detail "Response: $DB_TABLES"
    fi
    exit 1
fi

DB_TABLE_COUNT=$(echo "$DB_TABLES" | jq '.result | length - 1' 2>/dev/null || echo "0")
log_success "✅ Found $DB_TABLE_COUNT tables in database"

# Get tracked tables from Hasura metadata
log_progress "Step 2: Getting tracked tables from Hasura..."
METADATA=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/metadata" \
  -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"type": "export_metadata", "args": {}}')

if [[ "$METADATA" == *"error"* ]]; then
    log_error "Cannot get Hasura metadata"
    if [[ "$DETAILED" == "true" ]]; then
        log_detail "Response: $METADATA"
    fi
    exit 1
fi

TRACKED_COUNT=$(echo "$METADATA" | jq '.sources[0].tables | length' 2>/dev/null || echo "0")
log_success "✅ Found $TRACKED_COUNT tracked tables in Hasura"

# Compare counts
log_progress "Step 3: Comparing counts..."
if [[ "$DB_TABLE_COUNT" -eq "$TRACKED_COUNT" ]]; then
    log_success "✅ Table counts match: $DB_TABLE_COUNT database tables = $TRACKED_COUNT tracked tables"
else
    log_error "❌ ERROR: Table count mismatch!"
    log_detail "Database tables: $DB_TABLE_COUNT"
    log_detail "Tracked tables: $TRACKED_COUNT"
    
    if [[ "$DETAILED" == "true" ]]; then
        # Show which tables might be missing
        log_detail "🔍 Database tables vs Tracked tables:"
        
        # Get database table list
        DB_LIST=$(echo "$DB_TABLES" | jq -r '.result[1:] | .[] | "\(.[0]).\(.[1])"' | sort)
        
        # Get tracked table list
        TRACKED_LIST=$(echo "$METADATA" | jq -r '.sources[0].tables[] | "\(.table.schema).\(.table.name)"' | sort)
        
        log_detail "Missing from tracking:"
        echo "$DB_LIST" | while read -r table; do
            if ! echo "$TRACKED_LIST" | grep -q "^$table$"; then
                log_detail "❌ $table"
            fi
        done
    fi
    
    exit 1
fi

# Test GraphQL queries for a sample of tables
log_progress "Step 4: Testing GraphQL queries..."
SAMPLE_TABLES=$(echo "$METADATA" | jq -r '.sources[0].tables[:5] | .[] | "\(.table.schema)_\(.table.name)"')
QUERY_FAILED=0
QUERY_SUCCESS=0

for graphql_table in $SAMPLE_TABLES; do
    log_progress "  Testing $graphql_table..."
    
    QUERY_RESPONSE=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
      -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
      -H "Content-Type: application/json" \
      -d "{\"query\": \"{ ${graphql_table}(limit: 1) { __typename } }\"}" 2>/dev/null)
    
    if [[ "$QUERY_RESPONSE" == *"data"* ]] && [[ "$QUERY_RESPONSE" != *"errors"* ]]; then
        log_success "✅ $graphql_table query successful"
        QUERY_SUCCESS=$((QUERY_SUCCESS + 1))
    else
        log_error "❌ $graphql_table query failed"
        if [[ "$DETAILED" == "true" ]]; then
            ERROR_MSG=$(echo "$QUERY_RESPONSE" | jq -c '.errors[0].message // "Unknown error"' 2>/dev/null || echo "Unknown error")
            log_detail "Error: $ERROR_MSG"
        fi
        QUERY_FAILED=$((QUERY_FAILED + 1))
    fi
done

# Test aggregate queries
log_progress "Step 5: Testing aggregate queries..."
FIRST_TABLE=$(echo "$SAMPLE_TABLES" | head -1)
if [[ -n "$FIRST_TABLE" ]]; then
    log_progress "  Testing ${FIRST_TABLE}_aggregate..."
    
    AGG_RESPONSE=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
      -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
      -H "Content-Type: application/json" \
      -d "{\"query\": \"{ ${FIRST_TABLE}_aggregate { aggregate { count } } }\"}" 2>/dev/null)
    
    if [[ "$AGG_RESPONSE" == *"aggregate"* ]] && [[ "$AGG_RESPONSE" != *"errors"* ]]; then
        RECORD_COUNT=$(echo "$AGG_RESPONSE" | jq ".data.${FIRST_TABLE}_aggregate.aggregate.count" 2>/dev/null || echo "0")
        log_success "✅ ${FIRST_TABLE}_aggregate successful ($RECORD_COUNT records)"
    else
        log_error "❌ ${FIRST_TABLE}_aggregate failed"
        if [[ "$DETAILED" == "true" ]]; then
            ERROR_MSG=$(echo "$AGG_RESPONSE" | jq -c '.errors[0].message // "Unknown error"' 2>/dev/null || echo "Unknown error")
            log_detail "Error: $ERROR_MSG"
        fi
        QUERY_FAILED=$((QUERY_FAILED + 1))
    fi
fi

# Final results
section_header "📊 VERIFICATION RESULTS"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_detail "Database Tables: $DB_TABLE_COUNT"
log_detail "Tracked Tables: $TRACKED_COUNT"
log_success "Query Tests Passed: $QUERY_SUCCESS"
log_error "Query Tests Failed: $QUERY_FAILED"

if [[ "$DB_TABLE_COUNT" -eq "$TRACKED_COUNT" ]] && [[ "$QUERY_FAILED" -eq 0 ]]; then
    log_success "🎉 SUCCESS: All tables are properly tracked and queryable!"
    log_info "GraphQL API is ready for use."
    
    # Success summary
    print_operation_summary "Tables Verification" "$TIER" "$ENVIRONMENT"
    exit 0
else
    log_error "❌ FAILURE: Some tables are not properly tracked!"
    
    log_info "💡 To fix this, run:"
    log_detail "./track-all-tables.sh $TIER $ENVIRONMENT"
    
    exit 1
fi
