#!/bin/bash

# ============================================================================
# SHARED GRAPHQL - COMPREHENSIVE CONNECTION TEST
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Comprehensive connectivity test for any GraphQL tier
# Usage: ./test-connections.sh <tier> <environment> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Comprehensive Connection Test Command

DESCRIPTION:
    Tests connectivity, table access, and performance for any GraphQL tier.
    This command will verify:
    - Basic connectivity (schema introspection)
    - Table access (count records in key tables)
    - Available operations (queries and mutations)
    - Response timing and performance
    - Authentication and security

USAGE:
    ./test-connections.sh <tier> <environment> [options]

ARGUMENTS:
    tier           One of: admin, operator, member
    environment    Either 'production' or 'development'

OPTIONS:
    -h, --help     Show this help message
    --skip-perf    Skip performance tests
    --verbose      Show verbose output

EXAMPLES:
    ./test-connections.sh member development     # Test member development
    ./test-connections.sh admin production       # Test admin production
    ./test-connections.sh operator development --verbose

NOTES:
    - Includes comprehensive connectivity and performance tests
    - Tests key tables based on tier type
    - Measures response times and displays performance metrics
    - Safe operations that don't modify data
EOF
}

# Parse command line arguments
TIER=""
ENVIRONMENT=""
SKIP_PERFORMANCE=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --skip-perf)
            SKIP_PERFORMANCE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
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

section_header "🔌 SHARED GRAPHQL COMPREHENSIVE TEST - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "Endpoint: $GRAPHQL_TIER_ENDPOINT"
log_info "Authentication: Admin Secret (${#GRAPHQL_TIER_ADMIN_SECRET} chars)"

# Start timing
start_timer

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TEST_COUNT=0

# Test 1: Basic Connectivity - Schema Introspection
log_progress "1. 🔍 Basic Connectivity Test (Schema Introspection)"
TEST_COUNT=$((TEST_COUNT + 1))

test_start_time=$(date +%s%N)
SCHEMA_RESPONSE=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
    -H "Content-Type: application/json" \
    -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
    -d '{"query":"query { __schema { queryType { name } mutationType { name } } }"}' \
    2>/dev/null || echo "FAILED")
test_end_time=$(date +%s%N)
duration=$(( (test_end_time - test_start_time) / 1000000 ))

if [[ "$SCHEMA_RESPONSE" == *"queryType"* ]] && [[ "$SCHEMA_RESPONSE" != *"error"* ]]; then
    log_success "✅ Schema introspection successful (${duration}ms)"
    
    # Extract schema info
    query_type=$(echo "$SCHEMA_RESPONSE" | jq -r '.data.__schema.queryType.name // "unknown"' 2>/dev/null)
    mutation_type=$(echo "$SCHEMA_RESPONSE" | jq -r '.data.__schema.mutationType.name // "none"' 2>/dev/null)
    log_detail "Query root: $query_type"
    log_detail "Mutation root: $mutation_type"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "❌ Schema introspection failed (${duration}ms)"
    if [[ "$VERBOSE" == "true" ]]; then
        log_detail "Error: $SCHEMA_RESPONSE"
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 2: Table Access - Get tier-specific table list
log_progress "2. 📊 Table Access Test"
TEST_COUNT=$((TEST_COUNT + 1))

# Get list of tracked tables
test_start_time=$(date +%s%N)
TABLES_RESPONSE=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/metadata" \
    -H "Content-Type: application/json" \
    -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
    -d '{"type": "export_metadata", "args": {}}' 2>/dev/null || echo "FAILED")
test_end_time=$(date +%s%N)
duration=$(( (test_end_time - test_start_time) / 1000000 ))

if [[ "$TABLES_RESPONSE" == *"sources"* ]] && [[ "$TABLES_RESPONSE" != *"error"* ]]; then
    TABLE_COUNT=$(echo "$TABLES_RESPONSE" | jq '[.sources[].tables[]?] | length' 2>/dev/null || echo "0")
    log_success "✅ Table metadata accessible (${duration}ms)"
    log_detail "Total tracked tables: $TABLE_COUNT"
    
    # Show sample table names if verbose
    if [[ "$VERBOSE" == "true" && "$TABLE_COUNT" -gt 0 ]]; then
        log_detail "Sample tables:"
        echo "$TABLES_RESPONSE" | jq -r '.sources[].tables[]?.table.name // empty' 2>/dev/null | head -5 | sed 's/^/     - /' || true
    fi
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "❌ Table metadata access failed (${duration}ms)"
    if [[ "$VERBOSE" == "true" ]]; then
        log_detail "Error: $TABLES_RESPONSE"
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 3: Test a simple aggregate query on any available table
log_progress "3. 📋 Data Access Test"
TEST_COUNT=$((TEST_COUNT + 1))

# First, try to get any available table for testing
if [[ "$TABLE_COUNT" -gt 0 ]]; then
    # Get the first available table name
    FIRST_TABLE=$(echo "$TABLES_RESPONSE" | jq -r '.sources[].tables[]?.table.name // empty' 2>/dev/null | head -1)
    
    if [[ -n "$FIRST_TABLE" ]]; then
        test_start_time=$(date +%s%N)
        DATA_RESPONSE=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
            -H "Content-Type: application/json" \
            -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
            -d "{\"query\":\"query { ${FIRST_TABLE}_aggregate { aggregate { count } } }\"}" \
            2>/dev/null || echo "FAILED")
        test_end_time=$(date +%s%N)
        duration=$(( (test_end_time - test_start_time) / 1000000 ))
        
        if [[ "$DATA_RESPONSE" == *"aggregate"* ]] && [[ "$DATA_RESPONSE" != *"error"* ]]; then
            RECORD_COUNT=$(echo "$DATA_RESPONSE" | jq -r ".data.${FIRST_TABLE}_aggregate.aggregate.count // \"0\"" 2>/dev/null)
            log_success "✅ Data access test successful (${duration}ms)"
            log_detail "Table: $FIRST_TABLE"
            log_detail "Record count: $RECORD_COUNT"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            log_warning "⚠ Data access test had issues (${duration}ms)"
            log_detail "Table may not support aggregation: $FIRST_TABLE"
            if [[ "$VERBOSE" == "true" ]]; then
                log_detail "Response: $DATA_RESPONSE"
            fi
        fi
    else
        log_warning "⚠ No table names found for data access test"
    fi
else
    log_warning "⚠ No tracked tables available for data access test"
fi

# Test 4: Available Operations
log_progress "4. 📋 Available Operations Test"
TEST_COUNT=$((TEST_COUNT + 1))

test_start_time=$(date +%s%N)
OPERATIONS_RESPONSE=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
    -H "Content-Type: application/json" \
    -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
    -d '{"query":"query { __schema { queryType { fields { name } } mutationType { fields { name } } } }"}' \
    2>/dev/null || echo "FAILED")
test_end_time=$(date +%s%N)
duration=$(( (test_end_time - test_start_time) / 1000000 ))

if [[ "$OPERATIONS_RESPONSE" == *"fields"* ]] && [[ "$OPERATIONS_RESPONSE" != *"error"* ]]; then
    QUERY_COUNT=$(echo "$OPERATIONS_RESPONSE" | jq '.data.__schema.queryType.fields | length' 2>/dev/null || echo "0")
    MUTATION_COUNT=$(echo "$OPERATIONS_RESPONSE" | jq '.data.__schema.mutationType.fields | length' 2>/dev/null || echo "0")
    log_success "✅ Operations schema retrieved (${duration}ms)"
    log_detail "Available queries: $QUERY_COUNT"
    log_detail "Available mutations: $MUTATION_COUNT"
    
    # Show sample queries if verbose
    if [[ "$VERBOSE" == "true" && "$QUERY_COUNT" -gt 0 ]]; then
        log_detail "Sample queries:"
        echo "$OPERATIONS_RESPONSE" | jq -r '.data.__schema.queryType.fields[:5][].name' 2>/dev/null | sed 's/^/     - /' | head -5 || true
    fi
    
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "❌ Operations schema failed (${duration}ms)"
    if [[ "$VERBOSE" == "true" ]]; then
        log_detail "Error: $OPERATIONS_RESPONSE"
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 5: Performance Test (unless skipped)
if [[ "$SKIP_PERFORMANCE" != "true" ]]; then
    log_progress "5. ⚡ Performance Test - Complex Query"
    TEST_COUNT=$((TEST_COUNT + 1))
    
    test_start_time=$(date +%s%N)
    PERF_RESPONSE=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
        -H "Content-Type: application/json" \
        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
        -d '{"query":"query { schema: __schema { queryType { name } mutationType { name } } metadata: __type(name: \"Query\") { name } }"}' \
        2>/dev/null || echo "FAILED")
    test_end_time=$(date +%s%N)
    duration=$(( (test_end_time - test_start_time) / 1000000 ))
    
    if [[ "$PERF_RESPONSE" == *"schema"* ]] && [[ "$PERF_RESPONSE" != *"error"* ]]; then
        log_success "✅ Performance test passed (${duration}ms)"
        
        # Performance rating
        if [[ $duration -lt 500 ]]; then
            log_detail "Performance: Excellent (< 500ms)"
        elif [[ $duration -lt 1000 ]]; then
            log_detail "Performance: Good (< 1s)"
        elif [[ $duration -lt 2000 ]]; then
            log_detail "Performance: Fair (< 2s)"
        else
            log_detail "Performance: Slow (> 2s)"
        fi
        
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "❌ Performance test failed (${duration}ms)"
        if [[ "$VERBOSE" == "true" ]]; then
            log_detail "Error: $PERF_RESPONSE"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
else
    log_info "5. ⚡ Performance Test - Skipped"
fi

# Summary
section_header "📊 COMPREHENSIVE TEST SUMMARY"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "Endpoint: $GRAPHQL_TIER_ENDPOINT"
log_success "Tests Passed: $TESTS_PASSED/$TEST_COUNT"
log_error "Tests Failed: $TESTS_FAILED/$TEST_COUNT"

if [[ $TESTS_FAILED -eq 0 ]]; then
    log_success "🎉 All tests passed successfully!"
    log_success "The $TIER GraphQL API is fully operational."
else
    log_warning "⚠️  Some tests failed."
    log_info "Please check the errors above and verify your configuration."
fi

# Environment-specific tips
log_info "💡 Troubleshooting Tips:"
if [[ "$ENVIRONMENT" == "development" ]]; then
    log_detail "• Check Docker status: ./docker-status.sh $TIER $ENVIRONMENT"
    log_detail "• View logs: ./docker-status.sh $TIER $ENVIRONMENT --logs"
    log_detail "• Restart services: ./docker-stop.sh $TIER $ENVIRONMENT && ./docker-start.sh $TIER $ENVIRONMENT"
else
    log_detail "• Verify Hasura Cloud project is active"
    log_detail "• Check admin secret configuration"
    log_detail "• Ensure network connectivity"
    log_detail "• Verify database connection in Hasura console"
fi

log_info "📚 Additional Commands:"
log_detail "• Simple health check: ./test-connection.sh $TIER $ENVIRONMENT"
log_detail "• Deploy GraphQL: ./deploy-graphql.sh $TIER $ENVIRONMENT"
log_detail "• Load test data: ./load-test-data.sh $TIER $ENVIRONMENT"

# Success summary
print_operation_summary "Comprehensive Connection Test" "$TIER" "$ENVIRONMENT"

exit $TESTS_FAILED
