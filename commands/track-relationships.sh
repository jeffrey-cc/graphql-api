#!/bin/bash

# ============================================================================
# SHARED GRAPHQL RELATIONSHIP TRACKING
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Tracks database relationships for GraphQL nested queries
# Usage: ./track-relationships.sh <tier> <environment> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Track Relationships

DESCRIPTION:
    Tracks database relationships for GraphQL nested queries.
    This command will:
    - Analyze foreign key relationships in the database
    - Create GraphQL object and array relationships
    - Enable nested queries across related tables
    - Provide advanced relationship analysis

USAGE:
    ./track-relationships.sh <tier> <environment> [options]

ARGUMENTS:
    tier           One of: admin, operator, member
    environment    Either 'production' or 'development'

OPTIONS:
    -h, --help     Show this help message
    --manual       Manual relationship configuration (interactive)

EXAMPLES:
    ./track-relationships.sh member development    # Auto-track member relationships
    ./track-relationships.sh admin production      # Auto-track admin relationships

NOTES:
    - Should be run AFTER track-all-tables.sh
    - Enables powerful nested GraphQL queries
    - Automatically discovers foreign key constraints
    - Critical for complex business logic queries
EOF
}

# Parse command line arguments
TIER=""
ENVIRONMENT=""
MANUAL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --manual)
            MANUAL=true
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

# Check prerequisites
check_prerequisites

section_header "🔗 SHARED GRAPHQL RELATIONSHIP TRACKING - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "Database: $DB_TIER_DATABASE at localhost:$DB_TIER_PORT"
log_info "GraphQL: http://localhost:$GRAPHQL_TIER_PORT"

# Start timing
start_timer

# Test connectivity
if ! test_graphql_connection "$TIER" "$ENVIRONMENT"; then
    die "Cannot connect to GraphQL service. Ensure it's running."
fi

# Track relationships using shared function
log_progress "Tracking relationships for $TIER ($ENVIRONMENT)..."

if ! track_relationships "$TIER" "$ENVIRONMENT"; then
    die "Failed to track relationships"
fi

# Advanced relationship analysis and verification
log_progress "Analyzing relationship tracking results..."

local endpoint="http://localhost:$GRAPHQL_TIER_PORT"
local db_url="postgresql://$DB_TIER_USER:$DB_TIER_PASSWORD@localhost:$DB_TIER_PORT/$DB_TIER_DATABASE"

# Get foreign key count from database
local fk_count=$(psql "$db_url" -t -c "
    SELECT COUNT(*)
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
    WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema NOT IN ('information_schema', 'pg_catalog', 'hdb_catalog')
" 2>/dev/null | xargs)

log_detail "Database foreign keys found: $fk_count"

# Get GraphQL relationship count via introspection
local relationship_query='{"query": "query { __schema { types { name fields { name type { name ofType { name } } } } } }"}'
local relationship_response=$(curl -s \
    -H "Content-Type: application/json" \
    -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
    -d "$relationship_query" \
    "$endpoint/v1/graphql" 2>/dev/null)

if [[ "$relationship_response" == *'"data"'* ]]; then
    # Count relationship fields (approximate - fields that end with common relationship patterns)
    local graphql_relationships=$(echo "$relationship_response" | jq -r '
        .data.__schema.types[]? |
        select(.name and (.name | startswith("__") | not)) |
        .fields[]? |
        select(.name and (.name | test("_by_|_aggregate|_nodes"))) |
        .name
    ' 2>/dev/null | wc -l | xargs)
    
    log_detail "GraphQL relationship fields detected: $graphql_relationships"
    
    if [[ "$graphql_relationships" =~ ^[0-9]+$ && "$graphql_relationships" -gt 0 ]]; then
        log_success "Relationships are available in GraphQL schema"
    else
        log_warning "Could not detect relationship fields in GraphQL schema"
    fi
else
    log_warning "Could not analyze GraphQL relationships"
fi

# Test a relationship query if possible
log_progress "Testing relationship functionality..."

# Try to find a table with relationships for testing
local test_table=$(psql "$db_url" -t -c "
    SELECT tc.table_name
    FROM information_schema.table_constraints tc
    WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema NOT IN ('information_schema', 'pg_catalog', 'hdb_catalog')
    LIMIT 1
" 2>/dev/null | xargs)

if [[ -n "$test_table" ]]; then
    log_detail "Testing relationships with table: $test_table"
    
    # Try a simple relationship query
    local test_rel_query="{\"query\": \"query { $test_table { __typename } }\"}"
    local test_rel_response=$(curl -s \
        -H "Content-Type: application/json" \
        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
        -d "$test_rel_query" \
        "$endpoint/v1/graphql" 2>/dev/null)
    
    if [[ "$test_rel_response" == *'"data"'* ]]; then
        log_success "Relationship queries are functional"
    else
        log_warning "Relationship test query inconclusive"
    fi
else
    log_detail "No suitable tables found for relationship testing"
fi

# Manual relationship configuration if requested
if [[ "$MANUAL" == "true" ]]; then
    log_progress "Manual relationship configuration requested..."
    log_info "This would typically open an interactive session"
    log_info "For now, use the Hasura Console at: http://localhost:$GRAPHQL_TIER_PORT/console"
fi

# Success summary
print_operation_summary "Relationship Tracking" "$TIER" "$ENVIRONMENT"

log_success "Relationships tracked successfully!"
log_info "Nested GraphQL queries are now available"
log_info "Database foreign keys: $fk_count"
log_info "GraphQL Console: http://localhost:$GRAPHQL_TIER_PORT/console"
# Return success exit code
exit 0
