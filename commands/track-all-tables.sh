#!/bin/bash

# ============================================================================
# SHARED GRAPHQL TABLE TRACKING
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Tracks all database tables for GraphQL introspection
# Usage: ./track-all-tables.sh <tier> <environment> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Track All Tables

DESCRIPTION:
    Tracks all available tables in the database for GraphQL access.
    This command will:
    - Query all tables from the database
    - Track each table for GraphQL access
    - Enable introspection for all schemas

USAGE:
    ./track-all-tables.sh <tier> <environment> [options]

ARGUMENTS:
    tier           One of: admin, operator, member
    environment    Either 'production' or 'development'

OPTIONS:
    -h, --help     Show this help message
    --exclude-schema SCHEMA   Exclude specific schema from tracking

EXAMPLES:
    ./track-all-tables.sh member development    # Track all member tables
    ./track-all-tables.sh admin production      # Track all admin tables

NOTES:
    - This is typically run after deploy-graphql.sh
    - Only needs to be run once per database
    - Tables remain tracked until explicitly untracked
    - Automatically excludes system schemas
EOF
}

# Parse command line arguments
TIER=""
ENVIRONMENT=""
EXCLUDED_SCHEMAS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --exclude-schema)
            EXCLUDED_SCHEMAS+=("$2")
            shift 2
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

section_header "📋 SHARED GRAPHQL TABLE TRACKING - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
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

# Track all tables using shared function
log_progress "Tracking all tables for $TIER ($ENVIRONMENT)..."

if ! track_all_tables "$TIER" "$ENVIRONMENT"; then
    die "Failed to track tables"
fi

# Get table count for verification
log_progress "Verifying tracked tables..."

local endpoint="http://localhost:$GRAPHQL_TIER_PORT"
local introspection_query='{"query": "query { __schema { types { name kind } } }"}'

local response=$(curl -s \
    -H "Content-Type: application/json" \
    -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
    -d "$introspection_query" \
    "$endpoint/v1/graphql" 2>/dev/null)

if [[ "$response" == *'"data"'* ]]; then
    # Count table types in GraphQL schema
    local table_count=$(echo "$response" | jq -r '.data.__schema.types[] | select(.kind == "OBJECT" and (.name | startswith("__") | not)) | .name' 2>/dev/null | wc -l | xargs)
    
    if [[ "$table_count" =~ ^[0-9]+$ && "$table_count" -gt 0 ]]; then
        log_success "Verified: $table_count table types available in GraphQL schema"
    else
        log_warning "Could not count GraphQL table types"
    fi
else
    log_warning "Could not verify GraphQL schema"
fi

# Test a simple query to ensure tables are accessible
log_progress "Testing table accessibility..."

local test_query='{"query": "query { __type(name: \"Query\") { fields { name type { name } } } }"}'
local test_response=$(curl -s \
    -H "Content-Type: application/json" \
    -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
    -d "$test_query" \
    "$endpoint/v1/graphql" 2>/dev/null)

if [[ "$test_response" == *'"data"'* ]]; then
    local query_count=$(echo "$test_response" | jq -r '.data.__type.fields[]?.name' 2>/dev/null | wc -l | xargs)
    
    if [[ "$query_count" =~ ^[0-9]+$ && "$query_count" -gt 0 ]]; then
        log_success "Verified: $query_count queries available"
    else
        log_warning "Could not count available queries"
    fi
else
    log_warning "Could not verify query accessibility"
fi

# Success summary
print_operation_summary "Table Tracking" "$TIER" "$ENVIRONMENT"

log_success "All tables tracked successfully!"
log_info "Tables are now available for GraphQL queries"
log_info "Next step: Run track-relationships.sh to enable nested queries"
# Return success exit code
exit 0
