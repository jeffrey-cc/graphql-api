#!/bin/bash

# ============================================================================
# SHARED GRAPHQL DATABASE AUDIT COMMAND
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Compares database objects with tracked GraphQL API tables
# Usage: ./audit-database.sh <tier> [environment|compare]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
SHARED GRAPHQL DATABASE AUDIT COMMAND
Community Connect Tech - Shared GraphQL API System

DESCRIPTION:
    Compares database objects between the source database and what's 
    tracked in the GraphQL API. Helps identify:
    - Untracked tables
    - Missing relationships
    - Schema inconsistencies
    - Environment differences

USAGE:
    ./audit-database.sh <tier> [environment|compare]

ARGUMENTS:
    tier           admin, operator, or member
    environment    production, development, or compare (default: development)
                   'compare' audits both dev and prod

EXAMPLES:
    ./audit-database.sh admin development      # Audit admin dev
    ./audit-database.sh operator production    # Audit operator prod
    ./audit-database.sh member compare         # Compare dev vs prod

OUTPUT:
    - Lists all database tables and their tracking status
    - Shows foreign keys and relationship tracking
    - Highlights any discrepancies
EOF
}

# Check for help flag
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]] || [[ -z "$1" ]]; then
    show_help
    exit 0
fi

# Parse arguments
TIER="$1"
ENVIRONMENT="${2:-development}"

# Validate tier
if [[ "$TIER" != "admin" && "$TIER" != "operator" && "$TIER" != "member" ]]; then
    log_error "Invalid tier: $TIER. Must be admin, operator, or member"
    show_help
    exit 1
fi

# Handle compare mode
if [[ "$ENVIRONMENT" == "compare" ]]; then
    echo -e "${MAGENTA}${BOLD}🔍 Running database audit on both environments for comparison...${NC}"
    echo ""
    
    # Run development audit
    echo -e "${BLUE}🔷 DEVELOPMENT ENVIRONMENT AUDIT${NC}"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    $0 "$TIER" development 2>&1 | sed 's/^/[DEV] /'
    
    echo ""
    echo ""
    
    # Run production audit
    echo -e "${GREEN}🔶 PRODUCTION ENVIRONMENT AUDIT${NC}"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    $0 "$TIER" production 2>&1 | sed 's/^/[PROD] /'
    
    echo ""
    echo -e "${MAGENTA}${BOLD}📊 Comparison complete! Review the audits above for any discrepancies.${NC}"
    exit 0
fi

# Validate environment
if [[ "$ENVIRONMENT" != "production" && "$ENVIRONMENT" != "development" ]]; then
    log_error "Invalid environment: $ENVIRONMENT. Must be production, development, or compare"
    show_help
    exit 1
fi

# Configure tier
configure_tier "$TIER"
if [ $? -ne 0 ]; then
    exit 1
fi

# Start timer
start_timer

# Print header
print_header "🔍 DATABASE AUDIT - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Environment: $ENVIRONMENT"
echo ""

# Load environment configuration
load_environment "$TIER" "$ENVIRONMENT"
if [ $? -ne 0 ]; then
    exit 1
fi

# Function to get database tables
get_database_tables() {
    # Query database directly for all tables
    QUERY="SELECT schemaname, tablename FROM pg_catalog.pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema', 'pg_toast', 'hasura', 'hdb_catalog') ORDER BY schemaname, tablename;"
    
    if [ "$ENVIRONMENT" == "development" ]; then
        # For local development, query database directly
        PGPASSWORD="$DB_TIER_PASSWORD" psql -h localhost -p "$DB_TIER_PORT" -U "$DB_TIER_USER" -d "$DB_TIER_DATABASE" -t -c "$QUERY" 2>/dev/null | sed 's/|/./g' | tr -s ' ' | sed 's/^ //g' | sed 's/ $//g'
    else
        # For production, we need to use the API or metadata export
        echo ""
    fi
}

# Function to get tracked tables
get_tracked_tables() {
    # Export metadata and extract tracked tables
    METADATA=$(curl -s -X POST "${GRAPHQL_ENDPOINT}/v1/metadata" \
        -H "x-hasura-admin-secret: ${GRAPHQL_TIER_ADMIN_SECRET}" \
        -H "Content-Type: application/json" \
        -d '{"type": "export_metadata", "args": {}}' 2>/dev/null)
    
    echo "$METADATA" | jq -r '.sources[0].tables[] | "\(.table.schema).\(.table.name)"' 2>/dev/null | sort
}

# Section: Database Tables
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📚 DATABASE TABLES${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

DB_TABLES=$(get_database_tables)
if [ -z "$DB_TABLES" ] && [ "$ENVIRONMENT" == "production" ]; then
    log_warning "Cannot query production database directly (using API data only)"
    DB_TABLES=""
else
    DB_TABLE_COUNT=$(echo "$DB_TABLES" | grep -c . || echo "0")
    log_info "Total database tables: $DB_TABLE_COUNT"
fi

echo ""

# Section: Tracked Tables
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📋 TRACKED TABLES IN GRAPHQL${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

TRACKED_TABLES=$(get_tracked_tables)
TRACKED_COUNT=$(echo "$TRACKED_TABLES" | grep -c . || echo "0")
log_info "Total tracked tables: $TRACKED_COUNT"

echo ""

# Section: Comparison
if [ ! -z "$DB_TABLES" ]; then
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}🔄 TRACKING STATUS${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Find untracked tables
    UNTRACKED=""
    for table in $DB_TABLES; do
        if ! echo "$TRACKED_TABLES" | grep -q "^$table$"; then
            UNTRACKED="$UNTRACKED$table\n"
        fi
    done
    
    if [ ! -z "$UNTRACKED" ]; then
        log_warning "Untracked tables found:"
        echo -e "$UNTRACKED" | sed 's/^/  ❌ /g'
        ((COMMAND_WARNINGS++))
    else
        log_success "All database tables are tracked!"
    fi
    echo ""
fi

# Section: Foreign Keys and Relationships
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}🔗 RELATIONSHIPS${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Get relationship counts from metadata
METADATA=$(curl -s -X POST "${GRAPHQL_ENDPOINT}/v1/metadata" \
    -H "x-hasura-admin-secret: ${GRAPHQL_TIER_ADMIN_SECRET}" \
    -H "Content-Type: application/json" \
    -d '{"type": "export_metadata", "args": {}}' 2>/dev/null)

OBJECT_RELS=$(echo "$METADATA" | jq '[.sources[0].tables[].object_relationships // [] | length] | add' 2>/dev/null || echo "0")
ARRAY_RELS=$(echo "$METADATA" | jq '[.sources[0].tables[].array_relationships // [] | length] | add' 2>/dev/null || echo "0")
TOTAL_RELS=$((OBJECT_RELS + ARRAY_RELS))

log_info "Object relationships: $OBJECT_RELS"
log_info "Array relationships: $ARRAY_RELS"
log_info "Total relationships: $TOTAL_RELS"

echo ""

# Print summary
print_summary

# Final status
echo ""
if [ $COMMAND_ERRORS -eq 0 ]; then
    log_success "Database audit completed successfully!"
    
    if [ $COMMAND_WARNINGS -gt 0 ]; then
        echo ""
        log_warning "Review warnings above for potential improvements"
        log_info "To track missing tables, run: ./track-all-tables.sh $TIER $ENVIRONMENT"
    fi
else
    log_error "Audit completed with $COMMAND_ERRORS error(s)"
fi

exit $COMMAND_ERRORS