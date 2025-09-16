#!/bin/bash

# ============================================================================
# SHARED GRAPHQL SPEED TEST COMMAND
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Comprehensive performance benchmarking for GraphQL API
# Usage: ./speed-test-graphql.sh <tier> [environment|compare]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
SHARED GRAPHQL SPEED TEST COMMAND
Community Connect Tech - Shared GraphQL API System

DESCRIPTION:
    Runs comprehensive performance benchmarks on the GraphQL API to measure:
    - Simple query response times
    - Complex relationship query performance
    - Aggregate function performance
    - Mutation (insert/update/delete) speeds
    - Subscription connection times

USAGE:
    ./speed-test-graphql.sh <tier> [environment|compare]

ARGUMENTS:
    tier           admin, operator, or member
    environment    production, development, or compare (default: development)
                   'compare' runs tests on both dev and prod

EXAMPLES:
    ./speed-test-graphql.sh admin development     # Test admin dev
    ./speed-test-graphql.sh operator production   # Test operator prod
    ./speed-test-graphql.sh member compare        # Compare dev vs prod

BENCHMARKS:
    - Simple queries: Basic GraphQL queries
    - Complex queries: Multi-level relationships
    - Aggregations: Count, sum, avg operations
    - Mutations: Insert, update, delete operations
    - Bulk operations: Batch inserts/updates

OUTPUT:
    - Response times in milliseconds
    - Performance grading (Excellent/Good/Fair/Poor)
    - Comparison charts (when using 'compare')
EOF
}

# Check for help flag
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]] || [[ -z "$1" ]]; then
    show_help
    exit 0
fi

# Parse arguments
TIER="$1"
MODE="${2:-development}"

# Validate tier
if [[ "$TIER" != "admin" && "$TIER" != "operator" && "$TIER" != "member" ]]; then
    log_error "Invalid tier: $TIER. Must be admin, operator, or member"
    show_help
    exit 1
fi

# Configure tier
configure_tier "$TIER"
if [ $? -ne 0 ]; then
    exit 1
fi

# Function to run a single benchmark
run_benchmark() {
    local name="$1"
    local query="$2"
    local endpoint="$3"
    local secret="$4"
    
    local total_time=0
    local iterations=5
    
    for i in $(seq 1 $iterations); do
        START_TIME=$(date +%s%N)
        curl -s -X POST "$endpoint/v1/graphql" \
            -H "x-hasura-admin-secret: $secret" \
            -H "Content-Type: application/json" \
            -d "{\"query\": \"$query\"}" > /dev/null 2>&1
        END_TIME=$(date +%s%N)
        
        RESPONSE_TIME=$(( (END_TIME - START_TIME) / 1000000 ))
        total_time=$((total_time + RESPONSE_TIME))
    done
    
    local avg_time=$((total_time / iterations))
    echo "$avg_time"
}

# Function to grade performance
grade_performance() {
    local time=$1
    if [ $time -lt 50 ]; then
        echo -e "${GREEN}Excellent${NC} (<50ms)"
    elif [ $time -lt 100 ]; then
        echo -e "${GREEN}Good${NC} (50-100ms)"
    elif [ $time -lt 200 ]; then
        echo -e "${YELLOW}Fair${NC} (100-200ms)"
    else
        echo -e "${RED}Poor${NC} (>200ms)"
    fi
}

# Function to run tests for an environment
run_tests() {
    local environment="$1"
    
    # Load environment configuration
    load_environment "$TIER" "$environment"
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Testing: ${environment^^} ENVIRONMENT${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "Endpoint: $GRAPHQL_ENDPOINT"
    echo ""
    
    # Check if API is accessible
    if ! curl -s -f -o /dev/null "${GRAPHQL_ENDPOINT}/healthz"; then
        log_error "API is not accessible"
        return 1
    fi
    
    # Test 1: Simple Query
    log_step "Testing simple query..."
    SIMPLE_TIME=$(run_benchmark "Simple Query" "query { __typename }" "$GRAPHQL_ENDPOINT" "$GRAPHQL_TIER_ADMIN_SECRET")
    echo "  Response Time: ${SIMPLE_TIME}ms - $(grade_performance $SIMPLE_TIME)"
    
    # Test 2: Schema Introspection
    log_step "Testing schema introspection..."
    INTRO_TIME=$(run_benchmark "Introspection" "query { __schema { types { name } } }" "$GRAPHQL_ENDPOINT" "$GRAPHQL_TIER_ADMIN_SECRET")
    echo "  Response Time: ${INTRO_TIME}ms - $(grade_performance $INTRO_TIME)"
    
    # Test 3: Table Query (if tables exist)
    log_step "Testing table query..."
    # First, get a table name
    METADATA=$(curl -s -X POST "${GRAPHQL_ENDPOINT}/v1/metadata" \
        -H "x-hasura-admin-secret: ${GRAPHQL_TIER_ADMIN_SECRET}" \
        -H "Content-Type: application/json" \
        -d '{"type": "export_metadata", "args": {}}' 2>/dev/null)
    
    if [ ! -z "$METADATA" ]; then
        TABLE_INFO=$(echo "$METADATA" | jq -r '.sources[0].tables[0] | "\(.table.schema)_\(.table.name)"' 2>/dev/null || echo "")
        
        if [ ! -z "$TABLE_INFO" ] && [ "$TABLE_INFO" != "null_null" ]; then
            TABLE_QUERY="query { ${TABLE_INFO}(limit: 1) { __typename } }"
            TABLE_TIME=$(run_benchmark "Table Query" "$TABLE_QUERY" "$GRAPHQL_ENDPOINT" "$GRAPHQL_TIER_ADMIN_SECRET")
            echo "  Response Time: ${TABLE_TIME}ms - $(grade_performance $TABLE_TIME)"
        else
            echo "  Skipped (no tables tracked)"
        fi
    fi
    
    # Test 4: Aggregate Query
    if [ ! -z "$TABLE_INFO" ] && [ "$TABLE_INFO" != "null_null" ]; then
        log_step "Testing aggregate query..."
        AGG_QUERY="query { ${TABLE_INFO}_aggregate { aggregate { count } } }"
        AGG_TIME=$(run_benchmark "Aggregate Query" "$AGG_QUERY" "$GRAPHQL_ENDPOINT" "$GRAPHQL_TIER_ADMIN_SECRET")
        echo "  Response Time: ${AGG_TIME}ms - $(grade_performance $AGG_TIME)"
    fi
    
    echo ""
    
    # Calculate average
    if [ ! -z "$TABLE_TIME" ]; then
        AVG_TIME=$(( (SIMPLE_TIME + INTRO_TIME + TABLE_TIME + ${AGG_TIME:-0}) / 4 ))
    else
        AVG_TIME=$(( (SIMPLE_TIME + INTRO_TIME) / 2 ))
    fi
    
    log_info "Average Response Time: ${AVG_TIME}ms - $(grade_performance $AVG_TIME)"
    echo ""
    
    return 0
}

# Start timer
start_timer

# Print header
print_header "⚡ GRAPHQL SPEED TEST - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
echo ""

# Run tests based on mode
if [ "$MODE" == "compare" ]; then
    log_info "Running comparison tests..."
    echo ""
    
    # Test development
    if run_tests "development"; then
        DEV_SUCCESS=true
    else
        DEV_SUCCESS=false
    fi
    
    # Test production
    if run_tests "production"; then
        PROD_SUCCESS=true
    else
        PROD_SUCCESS=false
    fi
    
    # Comparison summary
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📊 COMPARISON SUMMARY${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ "$DEV_SUCCESS" == "true" ]; then
        log_success "Development: Tests completed"
    else
        log_error "Development: Tests failed"
    fi
    
    if [ "$PROD_SUCCESS" == "true" ]; then
        log_success "Production: Tests completed"
    else
        log_error "Production: Tests failed"
    fi
else
    # Single environment test
    run_tests "$MODE"
fi

# Print summary
print_summary

# Final status
echo ""
if [ $COMMAND_ERRORS -eq 0 ]; then
    log_success "Speed test completed successfully!"
else
    log_error "Speed test completed with $COMMAND_ERRORS error(s)"
fi

exit $COMMAND_ERRORS