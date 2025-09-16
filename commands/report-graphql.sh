#!/bin/bash

# ============================================================================
# SHARED GRAPHQL REPORT COMMAND  
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Generates comprehensive GraphQL API status report
# Usage: ./report-graphql.sh <tier> [environment]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
SHARED GRAPHQL REPORT COMMAND
Community Connect Tech - Shared GraphQL API System

DESCRIPTION:
    Generates a comprehensive status report for the GraphQL API including:
    - Connection status and health
    - Table and relationship counts
    - Schema analysis
    - Performance metrics
    - Configuration details

USAGE:
    ./report-graphql.sh <tier> [environment]

ARGUMENTS:
    tier           admin, operator, or member
    environment    production or development (default: development)

EXAMPLES:
    ./report-graphql.sh admin development     # Admin dev report
    ./report-graphql.sh operator production   # Operator prod report
    ./report-graphql.sh member development    # Member dev report

OUTPUT:
    - Console display with formatted report
    - Table counts by schema
    - Relationship analysis
    - API endpoint information
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
print_header "📊 GRAPHQL API REPORT - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Environment: $ENVIRONMENT"
log_info "Report Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Load environment configuration
load_environment "$TIER" "$ENVIRONMENT"
if [ $? -ne 0 ]; then
    exit 1
fi

# Section: Connection Status
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📡 CONNECTION STATUS${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

log_info "Endpoint: $GRAPHQL_ENDPOINT"
log_info "Container: $GRAPHQL_TIER_CONTAINER"
log_info "Port: $GRAPHQL_TIER_PORT"

# Check health
if curl -s -f -o /dev/null "${GRAPHQL_ENDPOINT}/healthz"; then
    log_success "API Status: ONLINE"
else
    log_error "API Status: OFFLINE"
    ((COMMAND_ERRORS++))
fi

# Check database connectivity
DB_CHECK=$(curl -s -X POST "${GRAPHQL_ENDPOINT}/v1/metadata" \
    -H "x-hasura-admin-secret: ${GRAPHQL_TIER_ADMIN_SECRET}" \
    -H "Content-Type: application/json" \
    -d '{"type": "export_metadata", "args": {}}' 2>/dev/null)

if [ ! -z "$DB_CHECK" ]; then
    log_success "Database Connection: ACTIVE"
else
    log_error "Database Connection: FAILED"
    ((COMMAND_ERRORS++))
fi

echo ""

# Section: Metadata Analysis
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📋 METADATA ANALYSIS${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Export metadata
METADATA=$(curl -s -X POST "${GRAPHQL_ENDPOINT}/v1/metadata" \
    -H "x-hasura-admin-secret: ${GRAPHQL_TIER_ADMIN_SECRET}" \
    -H "Content-Type: application/json" \
    -d '{"type": "export_metadata", "args": {}}')

if [ ! -z "$METADATA" ]; then
    # Count tables
    TOTAL_TABLES=$(echo "$METADATA" | jq -r '.sources[0].tables | length' 2>/dev/null || echo "0")
    log_info "Total Tables Tracked: $TOTAL_TABLES"
    
    # Count by schema
    echo ""
    log_info "Tables by Schema:"
    echo "$METADATA" | jq -r '.sources[0].tables | group_by(.table.schema) | .[] | "\(.[ 0].table.schema): \(length)"' 2>/dev/null | while read line; do
        echo "  • $line"
    done || echo "  Unable to analyze schemas"
    
    # Count relationships
    echo ""
    OBJECT_RELS=$(echo "$METADATA" | jq '[.sources[0].tables[].object_relationships // [] | length] | add' 2>/dev/null || echo "0")
    ARRAY_RELS=$(echo "$METADATA" | jq '[.sources[0].tables[].array_relationships // [] | length] | add' 2>/dev/null || echo "0")
    TOTAL_RELS=$((OBJECT_RELS + ARRAY_RELS))
    
    log_info "Relationships:"
    echo "  • Object Relationships: $OBJECT_RELS"
    echo "  • Array Relationships: $ARRAY_RELS"
    echo "  • Total Relationships: $TOTAL_RELS"
else
    log_error "Unable to export metadata"
    ((COMMAND_ERRORS++))
fi

echo ""

# Section: Performance Metrics
if [ "$ENVIRONMENT" == "development" ]; then
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}⚡ PERFORMANCE METRICS${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Simple query test
    START_TIME=$(date +%s%N)
    curl -s -X POST "${GRAPHQL_ENDPOINT}/v1/graphql" \
        -H "x-hasura-admin-secret: ${GRAPHQL_TIER_ADMIN_SECRET}" \
        -H "Content-Type: application/json" \
        -d '{"query": "query { __typename }"}' > /dev/null 2>&1
    END_TIME=$(date +%s%N)
    RESPONSE_TIME=$(( (END_TIME - START_TIME) / 1000000 ))
    
    log_info "Simple Query Response: ${RESPONSE_TIME}ms"
    
    # Docker container stats (if running)
    if [ "$ENVIRONMENT" == "development" ]; then
        CONTAINER_STATS=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" "$GRAPHQL_TIER_CONTAINER" 2>/dev/null || echo "")
        if [ ! -z "$CONTAINER_STATS" ]; then
            echo ""
            log_info "Container Resources:"
            echo "$CONTAINER_STATS" | tail -n +2 | while read line; do
                echo "  $line"
            done
        fi
    fi
    echo ""
fi

# Section: Configuration
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}⚙️  CONFIGURATION${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "Database: $DB_TIER_DATABASE"
log_info "Database Port: $DB_TIER_PORT"
log_info "GraphQL Port: $GRAPHQL_TIER_PORT"

if [ "$ENVIRONMENT" == "development" ]; then
    log_info "Console: ${GRAPHQL_ENDPOINT}/console"
fi

echo ""

# Print summary
print_summary

# Final status
echo ""
if [ $COMMAND_ERRORS -eq 0 ]; then
    log_success "Report generated successfully!"
else
    log_error "Report completed with $COMMAND_ERRORS error(s)"
fi

exit $COMMAND_ERRORS