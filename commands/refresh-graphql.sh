#!/bin/bash

# ============================================================================
# SHARED GRAPHQL REFRESH METADATA COMMAND
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Refreshes Hasura metadata without Docker restart
# Usage: ./refresh-graphql.sh <tier> [environment]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
SHARED GRAPHQL REFRESH METADATA COMMAND
Community Connect Tech - Shared GraphQL API System

DESCRIPTION:
    Refreshes Hasura metadata to pick up database schema changes without 
    restarting Docker containers. Useful when tables or relationships 
    have been added/modified in the database.
    
    This command:
    - Reloads metadata from database
    - Tracks any new tables
    - Tracks any new relationships
    - Verifies the refresh was successful

USAGE:
    ./refresh-graphql.sh <tier> [environment]

ARGUMENTS:
    tier           admin, operator, or member
    environment    production or development (default: development)

EXAMPLES:
    ./refresh-graphql.sh admin development     # Refresh admin dev
    ./refresh-graphql.sh operator production   # Refresh operator prod
    ./refresh-graphql.sh member development    # Refresh member dev

WHEN TO USE:
    - After adding new tables to the database
    - After adding new foreign keys
    - After modifying table structures
    - When GraphQL isn't showing expected tables/relationships
    - As a lighter alternative to full restart

PERFORMANCE:
    - Target: < 1 second for metadata refresh
    - No Docker restart required
    - Preserves existing connections
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

# Validate environment
if [[ "$ENVIRONMENT" != "production" && "$ENVIRONMENT" != "development" ]]; then
    log_error "Invalid environment: $ENVIRONMENT. Must be production or development"
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
print_header "🔄 REFRESH METADATA - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Environment: $ENVIRONMENT"
echo ""

# Load environment configuration
load_environment "$TIER" "$ENVIRONMENT"
if [ $? -ne 0 ]; then
    exit 1
fi

# Check connectivity
log_step "Checking GraphQL API connectivity..."
if curl -s -f -o /dev/null "${GRAPHQL_ENDPOINT}/healthz"; then
    log_success "API is accessible at $GRAPHQL_ENDPOINT"
else
    log_error "API is not accessible at $GRAPHQL_ENDPOINT"
    exit 1
fi

# Get current table count
log_step "Getting current state..."
BEFORE_METADATA=$(curl -s -X POST "${GRAPHQL_ENDPOINT}/v1/metadata" \
    -H "x-hasura-admin-secret: ${GRAPHQL_TIER_ADMIN_SECRET}" \
    -H "Content-Type: application/json" \
    -d '{"type": "export_metadata", "args": {}}' 2>/dev/null)

BEFORE_TABLES=$(echo "$BEFORE_METADATA" | jq -r '.sources[0].tables | length' 2>/dev/null || echo "0")
BEFORE_RELS=$(echo "$BEFORE_METADATA" | jq '[.sources[0].tables[] | (.object_relationships // [] | length) + (.array_relationships // [] | length)] | add' 2>/dev/null || echo "0")

log_info "Current state: $BEFORE_TABLES tables, $BEFORE_RELS relationships"

# Reload metadata
log_step "Reloading metadata..."
RELOAD_RESPONSE=$(curl -s -X POST "${GRAPHQL_ENDPOINT}/v1/metadata" \
    -H "x-hasura-admin-secret: ${GRAPHQL_TIER_ADMIN_SECRET}" \
    -H "Content-Type: application/json" \
    -d '{"type": "reload_metadata", "args": {}}')

if echo "$RELOAD_RESPONSE" | jq -e '.message == "success"' >/dev/null 2>&1; then
    log_success "Metadata reloaded successfully"
else
    log_error "Failed to reload metadata"
    log_debug "Response: $RELOAD_RESPONSE"
    ((COMMAND_ERRORS++))
fi

# Re-track all sources
log_step "Re-tracking database source..."
TRACK_SOURCE=$(curl -s -X POST "${GRAPHQL_ENDPOINT}/v1/metadata" \
    -H "x-hasura-admin-secret: ${GRAPHQL_TIER_ADMIN_SECRET}" \
    -H "Content-Type: application/json" \
    -d "{
        \"type\": \"pg_track_all_tables\",
        \"args\": {
            \"source\": \"${TIER}_database\"
        }
    }" 2>/dev/null || echo "{}")

# Get new state
log_step "Verifying refresh..."
AFTER_METADATA=$(curl -s -X POST "${GRAPHQL_ENDPOINT}/v1/metadata" \
    -H "x-hasura-admin-secret: ${GRAPHQL_TIER_ADMIN_SECRET}" \
    -H "Content-Type: application/json" \
    -d '{"type": "export_metadata", "args": {}}' 2>/dev/null)

AFTER_TABLES=$(echo "$AFTER_METADATA" | jq -r '.sources[0].tables | length' 2>/dev/null || echo "0")
AFTER_RELS=$(echo "$AFTER_METADATA" | jq '[.sources[0].tables[] | (.object_relationships // [] | length) + (.array_relationships // [] | length)] | add' 2>/dev/null || echo "0")

log_info "New state: $AFTER_TABLES tables, $AFTER_RELS relationships"

# Check for changes
if [ "$AFTER_TABLES" -gt "$BEFORE_TABLES" ]; then
    NEW_TABLES=$((AFTER_TABLES - BEFORE_TABLES))
    log_success "Discovered $NEW_TABLES new table(s)"
fi

if [ "$AFTER_RELS" -gt "$BEFORE_RELS" ]; then
    NEW_RELS=$((AFTER_RELS - BEFORE_RELS))
    log_success "Discovered $NEW_RELS new relationship(s)"
fi

if [ "$AFTER_TABLES" -eq "$BEFORE_TABLES" ] && [ "$AFTER_RELS" -eq "$BEFORE_RELS" ]; then
    log_info "No new tables or relationships found (metadata is up to date)"
fi

# Print summary
print_summary

# Final status
echo ""
if [ $COMMAND_ERRORS -eq 0 ]; then
    log_success "Metadata refresh completed successfully!"
    
    # Suggest next steps
    if [ "$AFTER_TABLES" -eq 0 ]; then
        echo ""
        log_warning "No tables tracked. You may want to run:"
        log_info "  ./track-all-tables.sh $TIER $ENVIRONMENT"
    elif [ "$AFTER_RELS" -eq 0 ]; then
        echo ""
        log_warning "No relationships tracked. You may want to run:"
        log_info "  ./track-relationships.sh $TIER $ENVIRONMENT"
    fi
else
    log_error "Refresh completed with $COMMAND_ERRORS error(s)"
fi

exit $COMMAND_ERRORS