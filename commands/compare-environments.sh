#!/bin/bash

# ============================================================================
# SHARED GRAPHQL ENVIRONMENT COMPARISON
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Compares development vs production GraphQL environments
# Usage: ./compare-environments.sh <tier> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Environment Comparison

DESCRIPTION:
    Compares development vs production GraphQL environments to ensure
    consistency. This command will:
    - Compare GraphQL schema structures
    - Verify table and relationship tracking
    - Check query and mutation availability
    - Validate environment parity

USAGE:
    ./compare-environments.sh <tier> [options]

ARGUMENTS:
    tier           One of: admin, operator, member

OPTIONS:
    -h, --help     Show this help message
    --detailed     Show detailed differences

EXAMPLES:
    ./compare-environments.sh member        # Compare member environments
    ./compare-environments.sh admin --detailed  # Detailed admin comparison

NOTES:
    - Requires both development and production to be accessible
    - Helps ensure deployment consistency
    - Critical for maintaining environment parity
EOF
}

# Parse command line arguments
TIER=""
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
if [[ -z "$TIER" ]]; then
    log_error "Tier argument is required"
    show_help
    exit 1
fi

# Configure tier and validate
if ! configure_tier "$TIER"; then
    die "Failed to configure tier: $TIER"
fi

# Check prerequisites
check_prerequisites

section_header "⚖️  SHARED GRAPHQL ENVIRONMENT COMPARISON - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Comparing: development vs production"

# Start timing
start_timer

# Function to get GraphQL schema info
get_schema_info() {
    local environment="$1"
    local port=""
    
    # Load environment-specific configuration
    load_tier_config "$TIER" "$environment" || true
    
    # Determine endpoint based on environment
    if [[ "$environment" == "development" ]]; then
        port="$GRAPHQL_TIER_PORT"
        endpoint="http://localhost:$port"
    else
        # For production, we'd need the production endpoint
        # This would typically come from the tier's production.env
        if [[ -n "$HASURA_GRAPHQL_ENDPOINT" ]]; then
            endpoint="$HASURA_GRAPHQL_ENDPOINT"
        else
            log_error "Production endpoint not configured for $TIER"
            return 1
        fi
    fi
    
    log_detail "Testing $environment endpoint: $endpoint"
    
    # Test basic connectivity
    local admin_secret="${HASURA_GRAPHQL_ADMIN_SECRET:-$GRAPHQL_TIER_ADMIN_SECRET}"
    local introspection_query='{"query": "query { __schema { queryType { name } mutationType { name } subscriptionType { name } types { name kind } } }"}'
    
    local response=$(curl -s \
        -H "Content-Type: application/json" \
        -H "x-hasura-admin-secret: $admin_secret" \
        -d "$introspection_query" \
        "$endpoint/v1/graphql" 2>/dev/null)
    
    if [[ "$response" == *'"data"'* ]]; then
        echo "$response"
        return 0
    else
        log_error "Failed to get schema info from $environment: $response"
        return 1
    fi
}

# Get development schema
log_progress "Getting development schema information..."
DEV_SCHEMA=$(get_schema_info "development")
DEV_STATUS=$?

# Get production schema  
log_progress "Getting production schema information..."
PROD_SCHEMA=$(get_schema_info "production")
PROD_STATUS=$?

# Compare results
log_progress "Comparing environments..."

if [[ $DEV_STATUS -ne 0 ]]; then
    log_error "Could not access development environment"
    ((COMMAND_ERRORS++))
fi

if [[ $PROD_STATUS -ne 0 ]]; then
    log_error "Could not access production environment"
    ((COMMAND_ERRORS++))
fi

if [[ $DEV_STATUS -eq 0 && $PROD_STATUS -eq 0 ]]; then
    # Compare type counts
    local dev_types=$(echo "$DEV_SCHEMA" | jq -r '.data.__schema.types[] | select(.kind == "OBJECT" and (.name | startswith("__") | not)) | .name' 2>/dev/null | wc -l | xargs)
    local prod_types=$(echo "$PROD_SCHEMA" | jq -r '.data.__schema.types[] | select(.kind == "OBJECT" and (.name | startswith("__") | not)) | .name' 2>/dev/null | wc -l | xargs)
    
    log_detail "Development types: $dev_types"
    log_detail "Production types: $prod_types"
    
    if [[ "$dev_types" == "$prod_types" ]]; then
        log_success "Type count matches: $dev_types types"
    else
        log_warning "Type count mismatch: dev=$dev_types, prod=$prod_types"
        ((COMMAND_WARNINGS++))
    fi
    
    # Compare query/mutation availability
    local dev_has_query=$(echo "$DEV_SCHEMA" | jq -r '.data.__schema.queryType.name' 2>/dev/null)
    local prod_has_query=$(echo "$PROD_SCHEMA" | jq -r '.data.__schema.queryType.name' 2>/dev/null)
    
    if [[ "$dev_has_query" == "$prod_has_query" ]]; then
        log_success "Query types match: $dev_has_query"
    else
        log_warning "Query type mismatch: dev=$dev_has_query, prod=$prod_has_query"
        ((COMMAND_WARNINGS++))
    fi
    
    local dev_has_mutation=$(echo "$DEV_SCHEMA" | jq -r '.data.__schema.mutationType.name' 2>/dev/null)
    local prod_has_mutation=$(echo "$PROD_SCHEMA" | jq -r '.data.__schema.mutationType.name' 2>/dev/null)
    
    if [[ "$dev_has_mutation" == "$prod_has_mutation" ]]; then
        log_success "Mutation types match: $dev_has_mutation"
    else
        log_warning "Mutation type mismatch: dev=$dev_has_mutation, prod=$prod_has_mutation"
        ((COMMAND_WARNINGS++))
    fi
    
    # Detailed comparison if requested
    if [[ "$DETAILED" == "true" ]]; then
        log_progress "Generating detailed comparison..."
        
        local dev_type_list=$(echo "$DEV_SCHEMA" | jq -r '.data.__schema.types[] | select(.kind == "OBJECT" and (.name | startswith("__") | not)) | .name' 2>/dev/null | sort)
        local prod_type_list=$(echo "$PROD_SCHEMA" | jq -r '.data.__schema.types[] | select(.kind == "OBJECT" and (.name | startswith("__") | not)) | .name' 2>/dev/null | sort)
        
        # Find differences
        local dev_only=$(comm -23 <(echo "$dev_type_list") <(echo "$prod_type_list") 2>/dev/null)
        local prod_only=$(comm -13 <(echo "$dev_type_list") <(echo "$prod_type_list") 2>/dev/null)
        
        if [[ -n "$dev_only" ]]; then
            log_warning "Types only in development:"
            echo "$dev_only" | sed 's/^/  - /'
        fi
        
        if [[ -n "$prod_only" ]]; then
            log_warning "Types only in production:"
            echo "$prod_only" | sed 's/^/  - /'
        fi
        
        if [[ -z "$dev_only" && -z "$prod_only" ]]; then
            log_success "All types match between environments"
        fi
    fi
fi

# Success summary
print_operation_summary "Environment Comparison" "$TIER" "development vs production"

if [[ $COMMAND_ERRORS -eq 0 && $COMMAND_WARNINGS -eq 0 ]]; then
    log_success "Environments are in sync!"
elif [[ $COMMAND_ERRORS -eq 0 ]]; then
    log_warning "Environments have minor differences"
else
    log_error "Environment comparison failed"
fi
# Return success exit code
exit 0
