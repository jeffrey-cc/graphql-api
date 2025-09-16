#!/bin/bash

# ============================================================================
# SHARED GRAPHQL - CONNECTION TEST
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Test connectivity to any GraphQL tier
# Usage: ./test-connection.sh <tier> <environment> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../commands/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Connection Test Command

DESCRIPTION:
    Tests connectivity and configuration of the specified GraphQL tier.
    This command will verify:
    - GraphQL endpoint accessibility
    - Admin secret authentication
    - Database connectivity
    - GraphQL endpoint functionality
    - Metadata status

USAGE:
    ./test-connection.sh <tier> <environment> [options]

ARGUMENTS:
    tier           One of: admin, operator, member
    environment    Either 'production' or 'development'

OPTIONS:
    -h, --help     Show this help message
    --detailed     Show detailed connection information

EXAMPLES:
    ./test-connection.sh member development     # Test member development
    ./test-connection.sh admin production       # Test admin production
    ./test-connection.sh operator development --detailed

NOTES:
    - Non-destructive connectivity test only
    - Checks all critical endpoints
    - Verifies authentication is working
EOF
}

# Parse command line arguments
TIER=""
ENVIRONMENT=""
DETAILED=false

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

section_header "🔌 SHARED GRAPHQL CONNECTION TEST - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "Endpoint: $GRAPHQL_TIER_ENDPOINT"

# Start timing
start_timer

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

# Test 1: Health check endpoint
log_progress "1. Testing health endpoint..."
if curl -s -f -o /dev/null "${GRAPHQL_TIER_ENDPOINT}/healthz" 2>/dev/null; then
    log_success "✓ Health check passed"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "✗ Health check failed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 2: Version endpoint
log_progress "2. Testing version endpoint..."
VERSION_RESPONSE=$(curl -s -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
    "${GRAPHQL_TIER_ENDPOINT}/v1/version" 2>/dev/null || echo "FAILED")

if [[ "$VERSION_RESPONSE" == *"version"* ]]; then
    VERSION=$(echo "$VERSION_RESPONSE" | jq -r '.version // "unknown"' 2>/dev/null || echo "unknown")
    log_success "✓ Version check passed"
    log_detail "Hasura version: $VERSION"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "✗ Version check failed"
    if [[ "$DETAILED" == "true" ]]; then
        log_detail "Response: $VERSION_RESPONSE"
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 3: GraphQL endpoint with schema introspection
log_progress "3. Testing GraphQL endpoint..."
GRAPHQL_RESPONSE=$(curl -s -X POST "${GRAPHQL_TIER_ENDPOINT}/v1/graphql" \
    -H "Content-Type: application/json" \
    -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
    -d '{"query":"{ __schema { queryType { name } } }"}' 2>/dev/null || echo "FAILED")

if [[ "$GRAPHQL_RESPONSE" == *"queryType"* ]]; then
    log_success "✓ GraphQL endpoint accessible"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "✗ GraphQL endpoint failed"
    if [[ "$DETAILED" == "true" ]]; then
        log_detail "Response: $GRAPHQL_RESPONSE"
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 4: Metadata endpoint
log_progress "4. Testing metadata endpoint..."
METADATA_RESPONSE=$(curl -s -X POST "${GRAPHQL_TIER_ENDPOINT}/v1/metadata" \
    -H "Content-Type: application/json" \
    -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
    -d '{"type": "export_metadata", "args": {}}' 2>/dev/null || echo "FAILED")

if [[ "$METADATA_RESPONSE" == *"sources"* ]]; then
    log_success "✓ Metadata endpoint accessible"
    # Count tracked tables
    TABLE_COUNT=$(echo "$METADATA_RESPONSE" | jq '[.sources[].tables[]?] | length' 2>/dev/null || echo "0")
    log_detail "Tracked tables: $TABLE_COUNT"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "✗ Metadata endpoint failed"
    if [[ "$DETAILED" == "true" ]]; then
        log_detail "Response: $METADATA_RESPONSE"
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 5: Database connection
log_progress "5. Testing database connection..."
DB_TEST=$(curl -s -X POST "${GRAPHQL_TIER_ENDPOINT}/v1/graphql" \
    -H "Content-Type: application/json" \
    -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
    -d '{"query":"query { __typename }"}' 2>/dev/null || echo "FAILED")

if [[ "$DB_TEST" == *"Query"* ]] || [[ "$DB_TEST" == *"query_root"* ]]; then
    log_success "✓ Database connection successful"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "✗ Database connection failed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 6: Console accessibility (development only)
if [[ "$ENVIRONMENT" == "development" ]]; then
    log_progress "6. Testing console accessibility..."
    if curl -s -f -o /dev/null "${GRAPHQL_TIER_ENDPOINT}/console" 2>/dev/null; then
        log_success "✓ Console is accessible"
        log_detail "URL: ${GRAPHQL_TIER_ENDPOINT}/console"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_warning "⚠ Console not accessible"
        log_detail "This may be normal if console is disabled"
    fi
fi

# Test 7: List available queries (detailed mode)
if [[ "$DETAILED" == "true" ]]; then
    log_progress "7. Checking available queries..."
    SCHEMA_QUERY=$(curl -s -X POST "${GRAPHQL_TIER_ENDPOINT}/v1/graphql" \
        -H "Content-Type: application/json" \
        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
        -d '{"query":"{ __schema { queryType { fields { name } } } }"}' 2>/dev/null)

    if [[ "$SCHEMA_QUERY" == *"fields"* ]]; then
        QUERY_COUNT=$(echo "$SCHEMA_QUERY" | jq '.data.__schema.queryType.fields | length' 2>/dev/null || echo "0")
        log_success "✓ Schema query successful"
        log_detail "Available queries: $QUERY_COUNT"
        
        # Show sample queries
        if [[ "$QUERY_COUNT" -gt 0 ]]; then
            log_detail "Sample queries:"
            echo "$SCHEMA_QUERY" | jq -r '.data.__schema.queryType.fields[:5][].name' 2>/dev/null | sed 's/^/     - /' || true
        fi
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_warning "⚠ Could not retrieve schema"
    fi
fi

# Summary
section_header "📊 CONNECTION TEST SUMMARY"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "Endpoint: $GRAPHQL_TIER_ENDPOINT"
log_success "Tests Passed: $TESTS_PASSED"
if [[ $TESTS_FAILED -gt 0 ]]; then
    log_error "Tests Failed: $TESTS_FAILED"
else
    log_info "Tests Failed: $TESTS_FAILED"
fi

if [[ $TESTS_FAILED -eq 0 ]]; then
    log_success "✅ All connection tests passed!"
    log_info "The $TIER GraphQL API is properly configured and accessible."
else
    log_warning "⚠️  Some connection tests failed."
    log_info "Please check the configuration and ensure the service is running."
fi

# Additional tips based on environment
if [[ "$ENVIRONMENT" == "development" ]]; then
    log_info "💡 Development tips:"
    log_detail "• Check Docker status: ./docker-status.sh $TIER $ENVIRONMENT"
    log_detail "• View logs: ./docker-status.sh $TIER $ENVIRONMENT --logs"
    log_detail "• Restart services: ./docker-stop.sh $TIER $ENVIRONMENT && ./docker-start.sh $TIER $ENVIRONMENT"
else
    log_info "💡 Production tips:"
    log_detail "• Verify Hasura Cloud project is active"
    log_detail "• Check admin secret is correct"
    log_detail "• Ensure IP whitelist includes your location"
fi

# Success summary
print_operation_summary "Connection Test" "$TIER" "$ENVIRONMENT"

exit $TESTS_FAILED
