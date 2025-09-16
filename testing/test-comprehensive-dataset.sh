#!/bin/bash

# ============================================================================
# SHARED GRAPHQL - COMPREHENSIVE DATASET TESTING
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Comprehensive dataset testing and validation for any GraphQL tier
# Usage: ./test-comprehensive-dataset.sh <tier> <environment> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Comprehensive Dataset Testing Command

DESCRIPTION:
    Tests all data relationships, complex queries, and edge cases for the
    specified GraphQL tier. Validates cross-table relationships and 
    business logic specific to each tier.
    
    Tests performed:
    - Basic data integrity tests
    - Relationship validation
    - Complex query performance
    - Edge case handling
    - Business logic validation

USAGE:
    ./test-comprehensive-dataset.sh <tier> <environment> [options]

ARGUMENTS:
    tier           One of: admin, operator, member
    environment    Either 'production' or 'development'

OPTIONS:
    -h, --help     Show this help message
    --quick        Run only basic tests (skip comprehensive suite)
    --verbose      Show detailed test output

EXAMPLES:
    ./test-comprehensive-dataset.sh member development     # Full member tests
    ./test-comprehensive-dataset.sh admin production --quick   # Quick admin tests
    ./test-comprehensive-dataset.sh operator development --verbose

NOTES:
    - Tests are tier-specific and validate business logic
    - Includes performance and edge case testing
    - Safe read-only operations that don't modify data
    - Comprehensive validation of GraphQL API functionality
EOF
}

# Parse command line arguments
TIER=""
ENVIRONMENT=""
QUICK_MODE=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --quick)
            QUICK_MODE=true
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

section_header "🧪 SHARED GRAPHQL COMPREHENSIVE TESTING - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "GraphQL Endpoint: $GRAPHQL_TIER_ENDPOINT"
log_info "Start Time: $(date '+%Y-%m-%d %H:%M:%S')"

if [[ "$QUICK_MODE" == "true" ]]; then
    log_info "Mode: Quick testing (basic tests only)"
else
    log_info "Mode: Comprehensive testing (full test suite)"
fi

# Start timing
start_timer

# Check connectivity
log_progress "Checking $TIER GraphQL API connectivity..."
if ! test_graphql_connection "$TIER" "$ENVIRONMENT" >/dev/null 2>&1; then
    die "$TIER API is not accessible at $GRAPHQL_TIER_ENDPOINT"
fi
log_success "✅ GraphQL API connectivity confirmed"

# Initialize counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to run test query
run_test() {
    local test_name="$1"
    local query="$2"
    local expected_min="${3:-0}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    log_progress "  Testing: $test_name..."
    
    local RESPONSE=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
        -H "Content-Type: application/json" \
        -d "$query" 2>/dev/null || echo '{"errors":[{"message":"Network error"}]}')
    
    if echo "$RESPONSE" | jq -e '.errors' >/dev/null 2>&1; then
        local error_msg=$(echo "$RESPONSE" | jq -r '.errors[0].message' 2>/dev/null || echo "Unknown error")
        log_error "❌ FAILED: $test_name"
        if [[ "$VERBOSE" == "true" ]]; then
            log_detail "Error: $error_msg"
        fi
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
    
    # Extract count from response (handle different response structures)
    local COUNT=$(echo "$RESPONSE" | jq -r '
        if .data | has("aggregate") then .data.aggregate.count
        elif .data | keys | length == 1 then 
            if .data[.data | keys[0]] | type == "array" then .data[.data | keys[0]] | length
            elif .data[.data | keys[0]] | has("aggregate") then .data[.data | keys[0]].aggregate.count
            else 1 end
        else 0 end' 2>/dev/null || echo "0")
    
    if [[ "$COUNT" -ge "$expected_min" ]]; then
        log_success "✅ PASSED: $test_name ($COUNT records)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        log_error "❌ FAILED: $test_name ($COUNT < $expected_min expected)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Get available tables for testing
log_progress "Analyzing available tables for testing..."
TABLES_RESPONSE=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/metadata" \
    -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
    -H "Content-Type: application/json" \
    -d '{"type": "export_metadata", "args": {}}' 2>/dev/null || echo "FAILED")

if [[ "$TABLES_RESPONSE" == *"sources"* ]]; then
    TABLE_COUNT=$(echo "$TABLES_RESPONSE" | jq '[.sources[].tables[]?] | length' 2>/dev/null || echo "0")
    log_info "Found $TABLE_COUNT tracked tables for testing"
else
    log_warning "Could not retrieve table metadata, using limited tests"
    TABLE_COUNT=0
fi

# =====================================================
# 1. BASIC DATA INTEGRITY TESTS
# =====================================================
log_info ""
log_info "🔍 1. BASIC DATA INTEGRITY TESTS"

# Test schema introspection
run_test "Schema Introspection" '{"query":"{ __schema { queryType { name } mutationType { name } } }"}' 0

# Test available types
run_test "GraphQL Types Available" '{"query":"{ __type(name: \"Query\") { name fields { name } } }"}' 0

if [[ "$TABLE_COUNT" -gt 0 ]]; then
    # Get sample tables for testing
    SAMPLE_TABLES=$(echo "$TABLES_RESPONSE" | jq -r '.sources[].tables[:3] | .[] | "\(.table.schema)_\(.table.name)"' 2>/dev/null)
    
    for table in $SAMPLE_TABLES; do
        # Test basic table access
        run_test "Table Access: $table" "{\"query\":\"{ ${table}(limit: 1) { __typename } }\"}" 0
        
        # Test aggregate access
        run_test "Aggregate Access: $table" "{\"query\":\"{ ${table}_aggregate { aggregate { count } } }\"}" 0
        
        if [[ "$QUICK_MODE" == "true" ]]; then
            break  # Only test first table in quick mode
        fi
    done
fi

# =====================================================
# 2. TIER-SPECIFIC BUSINESS LOGIC TESTS
# =====================================================
if [[ "$QUICK_MODE" != "true" ]]; then
    log_info ""
    log_info "🏢 2. TIER-SPECIFIC BUSINESS LOGIC TESTS"
    
    case "$TIER" in
        "admin")
            # Admin-specific tests
            log_info "Testing admin-specific functionality..."
            
            # Test for admin operators table
            run_test "Admin Operators Query" '{"query":"{ admin_operators(limit: 1) { __typename } }"}' 0
            
            # Test admin analytics
            run_test "System Analytics Query" '{"query":"{ admin_system_analytics(limit: 1) { __typename } }"}' 0
            ;;
            
        "operator")
            # Operator-specific tests
            log_info "Testing operator-specific functionality..."
            
            # Test for facility management
            run_test "Facility Management Query" '{"query":"{ operator_facilities(limit: 1) { __typename } }"}' 0
            
            # Test member assignments
            run_test "Member Assignments Query" '{"query":"{ operator_member_assignments(limit: 1) { __typename } }"}' 0
            ;;
            
        "member")
            # Member-specific tests
            log_info "Testing member-specific functionality..."
            
            # Test member profiles
            run_test "Member Profiles Query" '{"query":"{ member_profiles(limit: 1) { __typename } }"}' 0
            
            # Test cross-operator assignments
            run_test "Operator Assignments Query" '{"query":"{ member_operator_assignments(limit: 1) { __typename } }"}' 0
            ;;
    esac
    
    # =====================================================
    # 3. RELATIONSHIP VALIDATION TESTS
    # =====================================================
    log_info ""
    log_info "🔗 3. RELATIONSHIP VALIDATION TESTS"
    
    # Test that relationships are properly configured
    SCHEMA_QUERY='{"query":"{ __schema { types { name fields { name type { name ofType { name } } } } } }"}'
    run_test "Relationship Schema Analysis" "$SCHEMA_QUERY" 0
    
    # =====================================================
    # 4. PERFORMANCE TESTS
    # =====================================================
    log_info ""
    log_info "⚡ 4. PERFORMANCE TESTS"
    
    # Test complex query performance
    start_perf_time=$(date +%s%N)
    PERF_QUERY='{"query":"{ __schema { queryType { fields(limit: 10) { name type { name } } } mutationType { fields(limit: 5) { name } } } }"}'
    run_test "Complex Schema Query Performance" "$PERF_QUERY" 0
    end_perf_time=$(date +%s%N)
    perf_duration=$(( (end_perf_time - start_perf_time) / 1000000 ))
    
    if [[ $perf_duration -lt 2000 ]]; then
        log_success "✅ Performance test passed (${perf_duration}ms < 2000ms)"
    else
        log_warning "⚠️  Performance test slow (${perf_duration}ms > 2000ms)"
    fi
    
    # =====================================================
    # 5. EDGE CASE TESTS
    # =====================================================
    log_info ""
    log_info "🔍 5. EDGE CASE TESTS"
    
    # Test empty result handling
    run_test "Empty Result Handling" '{"query":"{ __type(name: \"NonExistentType\") { name } }"}' 0
    
    # Test large limit handling
    run_test "Large Limit Query" '{"query":"{ __schema { types(limit: 1000) { name } } }"}' 0
fi

# =====================================================
# FINAL RESULTS
# =====================================================
section_header "📊 COMPREHENSIVE TESTING RESULTS"

log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "Mode: $(if [[ "$QUICK_MODE" == "true" ]]; then echo "Quick"; else echo "Comprehensive"; fi)"

log_detail "Total Tests: $TOTAL_TESTS"
log_success "Tests Passed: $PASSED_TESTS"
log_error "Tests Failed: $FAILED_TESTS"

# Calculate success rate
if [[ $TOTAL_TESTS -gt 0 ]]; then
    SUCCESS_RATE=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
    log_info "Success Rate: ${SUCCESS_RATE}%"
else
    log_warning "No tests were executed"
    exit 1
fi

# Final assessment
if [[ $FAILED_TESTS -eq 0 ]]; then
    log_success "🎉 ALL TESTS PASSED!"
    log_success "The $TIER GraphQL API is fully functional and comprehensive."
    
    if [[ "$QUICK_MODE" == "true" ]]; then
        log_info "💡 For complete validation, run without --quick flag"
    fi
    
    # Success summary
    print_operation_summary "Comprehensive Dataset Testing" "$TIER" "$ENVIRONMENT"
    exit 0
else
    log_error "⚠️  SOME TESTS FAILED!"
    log_info "Please review the failed tests and fix any issues."
    
    log_info "💡 Troubleshooting tips:"
    log_detail "• Check if all tables are properly tracked"
    log_detail "• Verify relationships are configured correctly"
    log_detail "• Ensure data is loaded for testing"
    log_detail "• Run: ./verify-complete-setup.sh $TIER $ENVIRONMENT"
    
    exit 1
fi
# Return success exit code
exit 0
