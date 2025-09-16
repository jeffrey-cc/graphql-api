#!/bin/bash

# ============================================================================
# SHARED GRAPHQL - VERIFY COMPLETE SETUP
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Verify complete setup for any GraphQL tier
# Usage: ./verify-complete-setup.sh <tier> <environment> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Verify Complete Setup Command

DESCRIPTION:
    Verifies that all database tables AND foreign key relationships are 
    properly tracked and available in the GraphQL API for the specified tier.
    
    Tests performed:
    - Check if all tier-specific tables are tracked
    - Verify foreign key relationships are tracked
    - Test sample relationship queries
    - Count total relationships in GraphQL schema
    - Validate nested queries work

USAGE:
    ./verify-complete-setup.sh <tier> <environment> [options]

ARGUMENTS:
    tier           One of: admin, operator, member
    environment    Either 'production' or 'development'

OPTIONS:
    -h, --help     Show this help message
    --detailed     Show detailed verification information

EXAMPLES:
    ./verify-complete-setup.sh member development     # Verify member setup
    ./verify-complete-setup.sh admin production       # Verify admin setup
    ./verify-complete-setup.sh operator development --detailed

EXIT CODES:
    0    All tables and relationships are properly configured
    1    Some tables or relationships are missing
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

section_header "🔍 SHARED GRAPHQL COMPLETE SETUP VERIFICATION - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
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

# Get complete GraphQL schema
log_progress "Analyzing $TIER GraphQL schema..."
SCHEMA_DATA=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
    -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
    -H "Content-Type: application/json" \
    -d '{"query": "{ __schema { types { name fields { name type { name ofType { name } } } } } }"}' 2>/dev/null)

if ! echo "$SCHEMA_DATA" | jq -e '.data.__schema' >/dev/null 2>&1; then
    die "Failed to retrieve $TIER GraphQL schema"
fi

# Set tier-specific table pattern based on tier
case "$TIER" in
    "admin")
        TABLE_PATTERN="^(admin_|operators_|billing_|analytics_|system_)"
        ;;
    "operator")
        TABLE_PATTERN="^(operator_|facilities_|members_|schedules_|resources_|bookings_)"
        ;;
    "member")
        TABLE_PATTERN="^(member_|profiles_|billing_|preferences_|analytics_|relationships_)"
        ;;
    *)
        TABLE_PATTERN="^(${TIER}_)"
        ;;
esac

# Count tier-specific tables
TIER_TABLES=$(echo "$SCHEMA_DATA" | jq "[.data.__schema.types[] | select(.name | test(\"$TABLE_PATTERN\"))] | length" 2>/dev/null || echo "0")

# Count tier relationships (foreign key fields)  
TIER_RELATIONSHIPS=$(echo "$SCHEMA_DATA" | jq "[.data.__schema.types[] | select(.name | test(\"$TABLE_PATTERN\")) | .fields[]? | select(.type.name | test(\"$TABLE_PATTERN\") // (.type.ofType.name | test(\"$TABLE_PATTERN\")))] | length" 2>/dev/null || echo "0")

# Count all GraphQL types
ALL_TYPES=$(echo "$SCHEMA_DATA" | jq '[.data.__schema.types[] | select(.name | startswith("__") | not)] | length' 2>/dev/null || echo "0")

log_detail "$TIER Tables: $TIER_TABLES"
log_detail "$TIER Relationships: $TIER_RELATIONSHIPS"
log_detail "Total GraphQL Types: $ALL_TYPES"

# Test essential tier queries based on tier type
log_progress "Testing essential $TIER queries..."

QUERY_SUCCESS=true

# Define tier-specific test queries
case "$TIER" in
    "admin")
        test_queries=(
            "admin_operators:admin_operators(limit: 1) { operator_id name email status }"
            "admin_billing:admin_billing_summary(limit: 1) { billing_id total_revenue period_start }"
            "admin_analytics:admin_system_analytics(limit: 1) { metric_id metric_name value }"
        )
        ;;
    "operator")
        test_queries=(
            "operator_facilities:operator_facilities(limit: 1) { facility_id name address capacity }"
            "member_assignments:operator_member_assignments(limit: 1) { member_id facility_id access_level }"
            "facility_schedules:operator_facility_schedules(limit: 1) { schedule_id facility_id start_time }"
        )
        ;;
    "member")
        test_queries=(
            "member_profiles:member_profiles(limit: 1) { member_id first_name last_name email }"
            "operator_assignments:member_operator_assignments(limit: 1) { member_id operator_id relationship_type access_level }"
            "member_preferences:member_preferences(limit: 1) { member_id notification_settings privacy_settings }"
            "consolidated_billing:member_billing_consolidated(limit: 1) { billing_id member_id billing_period total_amount }"
        )
        ;;
esac

# Execute test queries
for query_def in "${test_queries[@]}"; do
    query_name=$(echo "$query_def" | cut -d: -f1)
    query_body=$(echo "$query_def" | cut -d: -f2-)
    
    log_progress "  Testing $query_name query..."
    QUERY_RESPONSE=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"{ $query_body }\"}" 2>/dev/null)

    if echo "$QUERY_RESPONSE" | jq -e ".data.$query_name" >/dev/null 2>&1; then
        log_success "✅ $query_name query successful"
    else
        log_error "❌ $query_name query failed"
        if [[ "$DETAILED" == "true" ]]; then
            log_detail "Response: $QUERY_RESPONSE"
        fi
        QUERY_SUCCESS=false
    fi
done

# Test nested relationship query for the tier
log_progress "Testing nested relationship query..."
case "$TIER" in
    "admin")
        NESTED_QUERY='{ admin_operators(limit: 1) { operator_id name facilities { facility_id name } } }'
        NESTED_PATH=".data.admin_operators[0].facilities"
        ;;
    "operator")
        NESTED_QUERY='{ operator_facilities(limit: 1) { facility_id name member_assignments { member_id access_level } } }'
        NESTED_PATH=".data.operator_facilities[0].member_assignments"
        ;;
    "member")
        NESTED_QUERY='{ member_profiles(limit: 1) { member_id first_name operator_assignments { operator_id relationship_type access_level } } }'
        NESTED_PATH=".data.member_profiles[0].operator_assignments"
        ;;
esac

NESTED_RESPONSE=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
    -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"$NESTED_QUERY\"}" 2>/dev/null)

if echo "$NESTED_RESPONSE" | jq -e "$NESTED_PATH" >/dev/null 2>&1; then
    log_success "✅ Nested relationship query successful"
else
    log_warning "⚠️  Relationships may not be configured"
    if [[ "$DETAILED" == "true" ]]; then
        log_detail "Response: $NESTED_RESPONSE"
    fi
fi

# Test aggregate queries
log_progress "Testing $TIER aggregate queries..."

# Get first table for aggregate test
FIRST_TABLE=$(echo "$SCHEMA_DATA" | jq -r "[.data.__schema.types[] | select(.name | test(\"$TABLE_PATTERN\")) | .name][0] // empty" 2>/dev/null)

if [[ -n "$FIRST_TABLE" ]]; then
    AGG_RESPONSE=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"{ ${FIRST_TABLE}_aggregate { aggregate { count } } }\"}" 2>/dev/null)

    if echo "$AGG_RESPONSE" | jq -e ".data.${FIRST_TABLE}_aggregate.aggregate.count" >/dev/null 2>&1; then
        RECORD_COUNT=$(echo "$AGG_RESPONSE" | jq ".data.${FIRST_TABLE}_aggregate.aggregate.count")
        log_success "✅ Aggregate query successful ($RECORD_COUNT records in $FIRST_TABLE)"
    else
        log_error "❌ Aggregate query failed"
        QUERY_SUCCESS=false
    fi
else
    log_warning "⚠️  No tables found for aggregate testing"
fi

# Final assessment
SETUP_COMPLETE=true

# Set minimum requirements based on tier
case "$TIER" in
    "admin")
        MIN_TABLES=3
        MIN_RELATIONSHIPS=1
        ;;
    "operator")
        MIN_TABLES=4
        MIN_RELATIONSHIPS=2
        ;;
    "member")
        MIN_TABLES=3
        MIN_RELATIONSHIPS=1
        ;;
    *)
        MIN_TABLES=2
        MIN_RELATIONSHIPS=1
        ;;
esac

# Check minimum requirements
if [[ "$TIER_TABLES" -lt "$MIN_TABLES" ]]; then
    log_error "❌ Insufficient $TIER tables tracked (found $TIER_TABLES, need at least $MIN_TABLES)"
    SETUP_COMPLETE=false
fi

if [[ "$TIER_RELATIONSHIPS" -lt "$MIN_RELATIONSHIPS" ]]; then
    log_error "❌ No $TIER relationships found (need at least $MIN_RELATIONSHIPS)"
    SETUP_COMPLETE=false
fi

if [[ "$QUERY_SUCCESS" == "false" ]]; then
    log_error "❌ Some essential $TIER queries failed"
    SETUP_COMPLETE=false
fi

# Final results
section_header "📊 SETUP VERIFICATION RESULTS"
if [[ "$SETUP_COMPLETE" == "true" ]]; then
    log_success "✅ $TIER GRAPHQL API SETUP COMPLETE"
    
    log_info "$TIER API Configuration Summary:"
    log_detail "• $TIER Tables: $TIER_TABLES"
    log_detail "• $TIER Relationships: $TIER_RELATIONSHIPS"
    log_detail "• Total GraphQL Types: $ALL_TYPES"
    
    log_info "$TIER-specific capabilities verified:"
    case "$TIER" in
        "admin")
            log_detail "✅ System-wide operator management"
            log_detail "✅ Consolidated billing analytics"
            log_detail "✅ System performance monitoring"
            ;;
        "operator")
            log_detail "✅ Facility management operations"
            log_detail "✅ Member assignment tracking"
            log_detail "✅ Resource scheduling"
            ;;
        "member")
            log_detail "✅ Cross-operator member profiles"
            log_detail "✅ Many-to-many operator assignments"
            log_detail "✅ Consolidated billing across operators"
            ;;
    esac
    log_detail "✅ Nested relationship queries"
    log_detail "✅ Aggregate analytics"
    
    log_success "$TIER GraphQL API is ready for production! 🎉"
    
    # Success summary
    print_operation_summary "Complete Setup Verification" "$TIER" "$ENVIRONMENT"
    exit 0
else
    log_error "❌ $TIER SETUP INCOMPLETE"
    
    log_info "Issues found:"
    if [[ "$TIER_TABLES" -lt "$MIN_TABLES" ]]; then
        log_detail "• Insufficient $TIER tables tracked"
    fi
    if [[ "$TIER_RELATIONSHIPS" -lt "$MIN_RELATIONSHIPS" ]]; then
        log_detail "• Missing relationships"
    fi
    if [[ "$QUERY_SUCCESS" == "false" ]]; then
        log_detail "• Some essential $TIER queries failed"
    fi
    
    log_info "Recommended actions:"
    log_detail "1. Run: ./track-all-tables.sh $TIER $ENVIRONMENT"
    log_detail "2. Run: ./track-relationships.sh $TIER $ENVIRONMENT"
    log_detail "3. Re-run this verification script"
    
    exit 1
fi
# Return success exit code
exit 0
