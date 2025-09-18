#!/bin/bash

# ================================================================================
# Track All Tables via Database Introspection
# ================================================================================
# Uses database introspection to discover and track ALL tables across ALL schemas
# No dependency on external schema files - pure database-driven discovery
# Usage: ./track-all-tables-introspect.sh <tier> <environment>
# ================================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Parse arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <tier> <environment>"
    echo "Example: $0 admin development"
    exit 1
fi

TIER="$1"
ENVIRONMENT="$2"

# Configure tier settings
configure_tier "$TIER"

# Configure endpoint for the environment
if ! configure_endpoint "$TIER" "$ENVIRONMENT"; then
    die "Failed to configure endpoint for $TIER ($ENVIRONMENT)"
fi

section_header "🔍 INTROSPECTION-BASED TABLE TRACKING - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "GraphQL: $GRAPHQL_TIER_ENDPOINT"

# Test GraphQL connection
log_progress "Testing GraphQL connection..."
if ! test_graphql_connection "$TIER" "$ENVIRONMENT"; then
    die "GraphQL connection failed"
fi
log_success "GraphQL connection successful"

# Step 1: Purge all existing tracking (tables, relationships, views, enums)
log_progress "Purging all existing GraphQL tracking..."

# Get current metadata
log_detail "Exporting current metadata..."
current_metadata=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/metadata" \
  -H "X-Hasura-Admin-Secret: $GRAPHQL_TIER_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"type": "export_metadata", "args": {}}')

if [[ "$current_metadata" == *'"sources"'* ]]; then
    # Untrack all existing tables
    log_detail "Untracking all existing tables..."
    echo "$current_metadata" | jq -c '.sources[]?.tables[]?.table' 2>/dev/null | while read -r table_ref; do
        if [[ "$table_ref" != "null" && "$table_ref" != "" ]]; then
            untrack_query='{
              "type": "pg_untrack_table",
              "args": {
                "source": "default",
                "table": '$table_ref'
              }
            }'
            
            curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/metadata" \
              -H "X-Hasura-Admin-Secret: $GRAPHQL_TIER_ADMIN_SECRET" \
              -H "Content-Type: application/json" \
              -d "$untrack_query" >/dev/null 2>&1
        fi
    done
    log_success "Purged all existing tracking"
else
    log_detail "No existing tracking found"
fi

# Step 2: Discover all tables via database introspection
log_progress "Discovering tables via database introspection..."

introspection_query='{
  "type": "run_sql",
  "args": {
    "sql": "SELECT table_schema, table_name FROM information_schema.tables WHERE table_type = '\''BASE TABLE'\'' AND table_schema NOT IN ('\''information_schema'\'', '\''pg_catalog'\'', '\''pg_toast'\'', '\''hdb_catalog'\'') ORDER BY table_schema, table_name;"
  }
}'

log_detail "Querying database for all tables..."
response=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v2/query" \
  -H "X-Hasura-Admin-Secret: $GRAPHQL_TIER_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d "$introspection_query")

if [[ ! "$response" == *'"result_type":"TuplesOk"'* ]]; then
    log_error "Failed to introspect database tables"
    echo "Response: $response"
    die "Database introspection failed"
fi

# Parse discovered tables
tables_json=$(echo "$response" | jq '.result[1:][] | {schema: .[0], table: .[1]}' 2>/dev/null)
table_count=$(echo "$tables_json" | jq -s length 2>/dev/null)

if [[ "$table_count" == "0" || "$table_count" == "null" ]]; then
    log_warning "No tables discovered in database"
    log_info "Database may be empty or have permission issues"
    exit 0
fi

log_success "Discovered $table_count tables across multiple schemas"

# Step 3: Track each discovered table
log_progress "Tracking discovered tables..."

tracked_count=0
error_count=0

echo "$tables_json" | jq -r '@json' | while read -r table_json; do
    schema=$(echo "$table_json" | jq -r '.schema')
    table=$(echo "$table_json" | jq -r '.table')
    
    log_detail "Tracking $schema.$table..."
    
    track_query='{
      "type": "pg_track_table",
      "args": {
        "source": "default",
        "table": {
          "schema": "'$schema'",
          "name": "'$table'"
        }
      }
    }'
    
    track_response=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/metadata" \
      -H "X-Hasura-Admin-Secret: $GRAPHQL_TIER_ADMIN_SECRET" \
      -H "Content-Type: application/json" \
      -d "$track_query")
    
    if [[ "$track_response" == *'"message":"success"'* ]] || [[ "$track_response" == *'"already exists"'* ]]; then
        echo "  ✅ $schema.$table tracked successfully"
        ((tracked_count++))
    else
        echo "  ❌ Failed to track $schema.$table"
        echo "     Response: $track_response"
        ((error_count++))
    fi
done

# Step 4: Verify tracking results
log_progress "Verifying tracked tables..."

# Get current GraphQL schema to count tracked tables
schema_query='{"query": "{ __schema { types { name kind } } }"}'
schema_response=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
  -H "X-Hasura-Admin-Secret: $GRAPHQL_TIER_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d "$schema_query")

if [[ "$schema_response" == *'"data"'* ]]; then
    graphql_table_count=$(echo "$schema_response" | jq -r '.data.__schema.types[] | select(.kind == "OBJECT" and (.name | startswith("__") | not) and (.name | test("^[a-z_]+$")))' 2>/dev/null | wc -l | tr -d ' ')
    
    log_success "GraphQL schema now contains $graphql_table_count table types"
    
    if [[ "$graphql_table_count" -gt 0 ]]; then
        log_info "Sample available tables:"
        echo "$schema_response" | jq -r '.data.__schema.types[] | select(.kind == "OBJECT" and (.name | startswith("__") | not) and (.name | test("^[a-z_]+$"))) | .name' 2>/dev/null | head -5 | while read table; do
            log_detail "  - $table"
        done
    fi
else
    log_warning "Could not verify GraphQL schema"
fi

# Performance summary
end_timer

echo ""
section_header "🎯 INTROSPECTION TRACKING SUMMARY"
log_info "Tables discovered: $table_count"
log_info "Tables tracked: $tracked_count"
log_info "Errors: $error_count"

if [[ "$error_count" -eq 0 && "$tracked_count" -gt 0 ]]; then
    log_success "✅ All tables tracked successfully via introspection!"
    log_info "GraphQL API is ready for queries and mutations"
    log_info "Next step: Run track-relationships to enable nested queries"
else
    log_error "❌ Table tracking completed with issues"
    log_info "Some tables may not be available in GraphQL"
fi

exit 0