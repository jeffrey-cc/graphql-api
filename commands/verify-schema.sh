#!/bin/bash

# ============================================================================
# SHARED GRAPHQL - VERIFY SPECIFIC SCHEMA
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Verify specific schema tables are properly tracked in GraphQL
# Usage: ./verify-schema.sh <tier> <environment> <schema_name>
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Verify Specific Schema Command

DESCRIPTION:
    Verifies that all tables from a specific database schema are properly
    tracked and available in the GraphQL API for the specified tier.

    Tests performed:
    - List all tables in the specified schema
    - Check if each table is tracked in GraphQL
    - Verify relationships for schema tables
    - Test sample queries for tracked tables
    - Report any missing or untracked tables

USAGE:
    ./verify-schema.sh <tier> <environment> <schema_name> [options]

ARGUMENTS:
    tier           One of: admin, operator, member
    environment    Either 'production' or 'development'
    schema_name    Database schema to verify (e.g., admin, public, operators, etc.)

OPTIONS:
    -h, --help     Show this help message
    --detailed     Show detailed verification information
    --fix          Attempt to track any untracked tables

EXAMPLES:
    ./verify-schema.sh admin development admin        # Verify admin schema
    ./verify-schema.sh admin development operators    # Verify operators schema
    ./verify-schema.sh operator development facilities # Verify facilities schema
    ./verify-schema.sh member development public      # Verify public schema

EXIT CODES:
    0    All schema tables are properly tracked
    1    Some tables are not tracked or error occurred
EOF
}

# Parse command line arguments
TIER=""
ENVIRONMENT=""
SCHEMA_NAME=""
DETAILED=false
FIX_ISSUES=false

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
        --fix)
            FIX_ISSUES=true
            shift
            ;;
        *)
            if [[ -z "$TIER" ]]; then
                TIER="$1"
            elif [[ -z "$ENVIRONMENT" ]]; then
                ENVIRONMENT="$1"
            elif [[ -z "$SCHEMA_NAME" ]]; then
                SCHEMA_NAME="$1"
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
if [[ -z "$TIER" || -z "$ENVIRONMENT" || -z "$SCHEMA_NAME" ]]; then
    log_error "All three arguments (tier, environment, schema_name) are required"
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

section_header "🔍 SCHEMA-SPECIFIC VERIFICATION - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "Schema: $SCHEMA_NAME"
log_info "Endpoint: $GRAPHQL_TIER_ENDPOINT"
log_info "Start Time: $(date '+%Y-%m-%d %H:%M:%S')"

# Start timing
start_timer

# Check basic connectivity
log_progress "Testing $TIER API connectivity..."
if ! test_graphql_connection "$TIER" "$ENVIRONMENT" >/dev/null 2>&1; then
    die "Cannot connect to $TIER GraphQL API"
fi
log_success "✅ Connectivity confirmed"

# Get all tracked tables from GraphQL
log_progress "Fetching tracked tables in GraphQL..."
TRACKED_TABLES=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/metadata" \
    -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
    -H "Content-Type: application/json" \
    -d '{"type": "export_metadata", "args": {}}' 2>/dev/null | \
    jq -r ".sources[0].tables[] | select(.table.schema == \"$SCHEMA_NAME\") | .table.name" 2>/dev/null | sort)

if [[ -z "$TRACKED_TABLES" ]]; then
    log_warning "No tables tracked for schema '$SCHEMA_NAME'"
else
    log_success "Found tracked tables in schema '$SCHEMA_NAME'"
fi

# Get all tables from the database schema using Hasura metadata API
log_progress "Fetching all tables from database schema '$SCHEMA_NAME'..."
SCHEMA_TABLES_RESPONSE=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/metadata" \
    -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
    -H "Content-Type: application/json" \
    -d "{\"type\": \"pg_get_source_tables\", \"args\": {\"source\": \"default\"}}" 2>/dev/null)

DB_TABLES=$(echo "$SCHEMA_TABLES_RESPONSE" | jq -r ".[] | select(.schema == \"$SCHEMA_NAME\") | .name" 2>/dev/null | sort)

if [[ -z "$DB_TABLES" ]]; then
    log_warning "No tables found in database schema '$SCHEMA_NAME' or unable to query database"
    log_detail "This might be due to permissions or the schema doesn't exist"
else
    DB_TABLE_COUNT=$(echo "$DB_TABLES" | wc -l | tr -d ' ')
    log_success "Found $DB_TABLE_COUNT tables in database schema '$SCHEMA_NAME'"
fi

# Compare tracked vs database tables
log_progress "Comparing tracked tables with database tables..."

UNTRACKED_TABLES=""
TRACKED_COUNT=0
UNTRACKED_COUNT=0
TOTAL_COUNT=0

if [[ ! -z "$DB_TABLES" ]]; then
    while IFS= read -r table; do
        TOTAL_COUNT=$((TOTAL_COUNT + 1))
        if echo "$TRACKED_TABLES" | grep -q "^$table$"; then
            TRACKED_COUNT=$((TRACKED_COUNT + 1))
            if [[ "$DETAILED" == "true" ]]; then
                log_success "  ✅ $SCHEMA_NAME.$table - Tracked"
            fi
        else
            UNTRACKED_COUNT=$((UNTRACKED_COUNT + 1))
            UNTRACKED_TABLES="${UNTRACKED_TABLES}${SCHEMA_NAME}.${table}\n"
            log_warning "  ⚠️  $SCHEMA_NAME.$table - NOT TRACKED"
        fi
    done <<< "$DB_TABLES"
fi

# Check relationships if tables are tracked
UNTRACKED_RELATIONSHIPS=""
RELATIONSHIP_COUNT=0
UNTRACKED_REL_COUNT=0

if [[ "$TRACKED_COUNT" -gt 0 ]]; then
    echo ""
    log_progress "Checking relationships for tracked tables..."

    # Get metadata with relationships
    METADATA=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/metadata" \
        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
        -H "Content-Type: application/json" \
        -d '{"type": "export_metadata", "args": {}}' 2>/dev/null)

    # Get foreign keys from database
    FK_QUERY='query {
      foreign_keys: __typename @include(if: false)
    }'

    # Use pg_get_source_tables to get foreign keys
    FK_RESPONSE=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/metadata" \
        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
        -H "Content-Type: application/json" \
        -d '{"type": "pg_get_source_tables", "args": {"source": "default"}}' 2>/dev/null)

    # Check each tracked table for relationships
    while IFS= read -r table; do
        [[ -z "$table" ]] && continue

        # Get relationships for this table from metadata
        TABLE_METADATA=$(echo "$METADATA" | jq ".sources[0].tables[] | select(.table.name == \"$table\" and .table.schema == \"$SCHEMA_NAME\")")

        OBJECT_RELS=$(echo "$TABLE_METADATA" | jq '.object_relationships[]?.name' 2>/dev/null | wc -l | tr -d ' ')
        ARRAY_RELS=$(echo "$TABLE_METADATA" | jq '.array_relationships[]?.name' 2>/dev/null | wc -l | tr -d ' ')
        TOTAL_RELS=$((OBJECT_RELS + ARRAY_RELS))

        if [[ "$DETAILED" == "true" ]]; then
            if [[ $TOTAL_RELS -gt 0 ]]; then
                log_success "  ✅ $SCHEMA_NAME.$table - $TOTAL_RELS relationships ($OBJECT_RELS object, $ARRAY_RELS array)"

                # Show relationship details if very detailed
                if [[ $OBJECT_RELS -gt 0 ]]; then
                    OBJECT_REL_NAMES=$(echo "$TABLE_METADATA" | jq -r '.object_relationships[].name' 2>/dev/null)
                    echo "$OBJECT_REL_NAMES" | while IFS= read -r rel_name; do
                        [[ -z "$rel_name" ]] && continue
                        log_detail "      → Object: $rel_name"
                    done
                fi

                if [[ $ARRAY_RELS -gt 0 ]]; then
                    ARRAY_REL_NAMES=$(echo "$TABLE_METADATA" | jq -r '.array_relationships[].name' 2>/dev/null)
                    echo "$ARRAY_REL_NAMES" | while IFS= read -r rel_name; do
                        [[ -z "$rel_name" ]] && continue
                        log_detail "      ← Array: $rel_name"
                    done
                fi
            else
                log_detail "  ℹ️  $SCHEMA_NAME.$table - No relationships"
            fi
        fi

        RELATIONSHIP_COUNT=$((RELATIONSHIP_COUNT + TOTAL_RELS))
    done <<< "$TRACKED_TABLES"
fi

# Summary
echo ""
section_header "📊 VERIFICATION SUMMARY"
log_info "Schema: $SCHEMA_NAME"
log_info "Total Tables in Database: $TOTAL_COUNT"
log_success "Tracked Tables: $TRACKED_COUNT"
log_success "Total Relationships: $RELATIONSHIP_COUNT"
if [[ $UNTRACKED_COUNT -gt 0 ]]; then
    log_error "Untracked Tables: $UNTRACKED_COUNT"
    echo ""
    log_warning "The following tables are NOT tracked in GraphQL:"
    echo -e "$UNTRACKED_TABLES" | while IFS= read -r table; do
        [[ -z "$table" ]] && continue
        echo "  - $table"
    done
fi

# Test sample queries for tracked tables
if [[ "$TRACKED_COUNT" -gt 0 ]] && [[ "$DETAILED" == "true" ]]; then
    echo ""
    log_progress "Testing sample queries for tracked tables..."

    # Test up to 3 tables
    SAMPLE_COUNT=0
    echo "$TRACKED_TABLES" | head -3 | while IFS= read -r table; do
        [[ -z "$table" ]] && continue
        SAMPLE_COUNT=$((SAMPLE_COUNT + 1))

        # Convert table name to GraphQL format (schema_tablename)
        GRAPHQL_NAME="${SCHEMA_NAME}_${table}"

        log_progress "  Testing query for $GRAPHQL_NAME..."
        QUERY_RESPONSE=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
            -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
            -H "Content-Type: application/json" \
            -d "{\"query\": \"{ $GRAPHQL_NAME(limit: 1) { __typename } }\"}" 2>/dev/null)

        if echo "$QUERY_RESPONSE" | jq -e ".data.$GRAPHQL_NAME" >/dev/null 2>&1; then
            log_success "    ✅ Query successful"
        else
            ERROR_MSG=$(echo "$QUERY_RESPONSE" | jq -r '.errors[0].message' 2>/dev/null || echo "Unknown error")
            log_warning "    ⚠️  Query failed: $ERROR_MSG"
        fi
    done
fi

# Attempt to fix issues if requested
if [[ "$FIX_ISSUES" == "true" ]] && [[ $UNTRACKED_COUNT -gt 0 ]]; then
    echo ""
    log_progress "Attempting to track untracked tables..."

    echo -e "$UNTRACKED_TABLES" | while IFS= read -r table_full; do
        [[ -z "$table_full" ]] && continue

        # Extract just the table name (remove schema prefix)
        table_name=$(echo "$table_full" | cut -d'.' -f2)

        log_progress "  Tracking $table_full..."

        TRACK_RESPONSE=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/metadata" \
            -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
            -H "Content-Type: application/json" \
            -d "{
                \"type\": \"pg_track_table\",
                \"args\": {
                    \"source\": \"default\",
                    \"table\": {
                        \"schema\": \"$SCHEMA_NAME\",
                        \"name\": \"$table_name\"
                    }
                }
            }" 2>/dev/null)

        if echo "$TRACK_RESPONSE" | jq -e '.message' >/dev/null 2>&1; then
            log_success "    ✅ Successfully tracked $table_full"
        else
            ERROR_MSG=$(echo "$TRACK_RESPONSE" | jq -r '.error' 2>/dev/null || echo "Unknown error")
            log_error "    ❌ Failed to track: $ERROR_MSG"
        fi
    done

    log_info ""
    log_info "Run this script again to verify all tables are now tracked"
fi

# Final result
echo ""
end_timer
if [[ $UNTRACKED_COUNT -eq 0 ]]; then
    log_success "✅ All tables in schema '$SCHEMA_NAME' are properly tracked!"
    exit 0
else
    log_error "❌ Schema verification failed: $UNTRACKED_COUNT tables are not tracked"
    if [[ "$FIX_ISSUES" != "true" ]]; then
        log_info "Run with --fix flag to attempt tracking untracked tables"
    fi
    exit 1
fi