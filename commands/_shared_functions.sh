#!/bin/bash

# ============================================================================
# SHARED GRAPHQL FUNCTIONS
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Tier-based parameterized functions for admin, operator, and member GraphQL
# APIs with Hasura introspection, relationship tracking, and deployment
# 
# Usage: configure_tier <admin|operator|member>
# ============================================================================

# Global constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SHARED_ROOT="$(dirname "$SCRIPT_DIR")"

# ANSI Color codes for consistent output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Error tracking
COMMAND_ERRORS=0
COMMAND_WARNINGS=0

# Timer for performance tracking
START_TIME=""

# ============================================================================
# TIER CONFIGURATION SYSTEM
# ============================================================================

configure_tier() {
    local tier="$1"
    
    case "$tier" in
        "admin")
            DB_TIER_PORT="7101"
            DB_TIER_CONTAINER="admin-postgres"
            DB_TIER_DATABASE="admin"
            DB_TIER_USER="admin"
            DB_TIER_PASSWORD="CCTech2024Admin!"
            GRAPHQL_TIER_PORT="8101"
            GRAPHQL_TIER_CONTAINER="admin-graphql-server"
            GRAPHQL_TIER_ADMIN_SECRET="CCTech2024Admin"
            GRAPHQL_TIER_VOLUME="admin_graphql_metadata"
            ;;
        "operator")
            DB_TIER_PORT="7102"
            DB_TIER_CONTAINER="operator-postgres"
            DB_TIER_DATABASE="operator"
            DB_TIER_USER="operator"
            DB_TIER_PASSWORD="CCTech2024Operator!"
            GRAPHQL_TIER_PORT="8102"
            GRAPHQL_TIER_CONTAINER="operator-graphql-server"
            GRAPHQL_TIER_ADMIN_SECRET="CCTech2024Operator"
            GRAPHQL_TIER_VOLUME="operator_graphql_metadata"
            ;;
        "member")
            DB_TIER_PORT="7103"
            DB_TIER_CONTAINER="member-postgres"
            DB_TIER_DATABASE="member"
            DB_TIER_USER="member"
            DB_TIER_PASSWORD="CCTech2024Member!"
            GRAPHQL_TIER_PORT="8103"
            GRAPHQL_TIER_CONTAINER="member-graphql-server"
            GRAPHQL_TIER_ADMIN_SECRET="CCTech2024Member"
            GRAPHQL_TIER_VOLUME="member_graphql_metadata"
            ;;
        *)
            log_error "Invalid tier: $tier. Must be admin, operator, or member"
            return 1
            ;;
    esac
    
    # Set tier-specific paths
    TIER_REPOSITORY_PATH="../${tier}-graqhql-api"
    TIER_CONFIG_DIR="$TIER_REPOSITORY_PATH/config"
    TIER_METADATA_DIR="$TIER_REPOSITORY_PATH/metadata"
    TIER_TESTING_DIR="$TIER_REPOSITORY_PATH/testing"
    
    # Export all variables for use by calling scripts
    export DB_TIER_PORT DB_TIER_CONTAINER DB_TIER_DATABASE DB_TIER_USER DB_TIER_PASSWORD
    export GRAPHQL_TIER_PORT GRAPHQL_TIER_CONTAINER GRAPHQL_TIER_ADMIN_SECRET GRAPHQL_TIER_VOLUME
    export TIER_REPOSITORY_PATH TIER_CONFIG_DIR TIER_METADATA_DIR TIER_TESTING_DIR
    
    log_debug "Configured tier: $tier"
    log_debug "Database: $DB_TIER_DATABASE at localhost:$DB_TIER_PORT"
    log_debug "GraphQL: $GRAPHQL_TIER_CONTAINER at localhost:$GRAPHQL_TIER_PORT"
    
    return 0
}

# ============================================================================
# ENDPOINT CONFIGURATION SYSTEM
# ============================================================================

configure_endpoint() {
    local tier="$1"
    local environment="$2"
    
    # Default to localhost for development
    if [[ "$environment" == "development" ]]; then
        GRAPHQL_TIER_ENDPOINT="http://localhost:$GRAPHQL_TIER_PORT"
    elif [[ "$environment" == "production" ]]; then
        # For production, try to get endpoint from environment file
        local env_file="$TIER_CONFIG_DIR/production.env"
        if [[ -f "$env_file" ]]; then
            # Source the file to get HASURA_ENDPOINT
            local endpoint_value=$(grep "^HASURA_ENDPOINT=" "$env_file" | cut -d'=' -f2-)
            # Remove quotes and expand variables if needed
            endpoint_value=$(eval echo "$endpoint_value")
            GRAPHQL_TIER_ENDPOINT="$endpoint_value"
        else
            log_warning "Production environment file not found: $env_file"
            # Fallback for production - common Hasura cloud pattern
            GRAPHQL_TIER_ENDPOINT="https://${tier}-graphql-api.hasura.app"
        fi
    else
        log_error "Invalid environment: $environment"
        return 1
    fi
    
    # Export the endpoint variable
    export GRAPHQL_TIER_ENDPOINT
    
    log_debug "Endpoint configured: $GRAPHQL_TIER_ENDPOINT"
    return 0
}

# ============================================================================
# LOGGING & OUTPUT FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${CYAN}ℹ️  INFO${NC}: $1" >&1
}

log_success() {
    echo -e "${GREEN}✅ SUCCESS${NC}: $1" >&1
}

log_warning() {
    echo -e "${YELLOW}⚠️  WARNING${NC}: $1" >&2
    ((COMMAND_WARNINGS++))
}

log_error() {
    echo -e "${RED}❌ ERROR${NC}: $1" >&2
    ((COMMAND_ERRORS++))
}

log_section() {
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log_step() {
    echo -e "${BLUE}➤${NC} $1"
}

log_progress() {
    echo -e "${MAGENTA}⏳${NC} $1"
}

log_detail() {
    echo -e "   ${1}"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}🔍 DEBUG${NC}: $1" >&2
    fi
}

# Section headers for command output
section_header() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}$1${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ============================================================================
# TIMER FUNCTIONS
# ============================================================================

start_timer() {
    START_TIME=$(date +%s.%N)
}

end_timer() {
    if [[ -n "$START_TIME" ]]; then
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $START_TIME" | bc 2>/dev/null || echo "0")
        echo -e "${GREEN}⏱️  Operation completed in ${BOLD}${duration}s${NC}"
    fi
}

# ============================================================================
# ERROR HANDLING FUNCTIONS
# ============================================================================

die() {
    local exit_code=${2:-1}
    log_error "$1"
    echo ""
    echo -e "${RED}Command failed with $COMMAND_ERRORS error(s) and $COMMAND_WARNINGS warning(s)${NC}"
    echo -e "${YELLOW}Use -h flag for help information${NC}"
    exit $exit_code
}

check_command_success() {
    local exit_code=$?
    local operation="$1"
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "$operation failed with exit code $exit_code"
        return $exit_code
    fi
    
    log_success "$operation completed successfully"
    return 0
}

# ============================================================================
# ENVIRONMENT VALIDATION FUNCTIONS  
# ============================================================================

validate_environment() {
    local environment="$1"
    
    if [[ "$environment" != "development" && "$environment" != "production" ]]; then
        die "Invalid environment: $environment. Must be 'development' or 'production'"
    fi
    
    log_debug "Environment validated: $environment"
    return 0
}

load_tier_config() {
    local tier="$1"
    local environment="$2"
    
    local env_file="$TIER_CONFIG_DIR/${environment}.env"
    
    if [[ -f "$env_file" ]]; then
        log_debug "Loading environment file: $env_file"
        source "$env_file"
        
        # Override admin secret if defined in config file (for production)
        if [[ -n "$HASURA_GRAPHQL_ADMIN_SECRET" ]]; then
            GRAPHQL_TIER_ADMIN_SECRET="$HASURA_GRAPHQL_ADMIN_SECRET"
            log_debug "Using admin secret from config file"
        fi
    else
        log_warning "Environment file not found: $env_file"
        return 1
    fi
    
    return 0
}

# ============================================================================
# HASURA API FUNCTIONS
# ============================================================================

execute_hasura_api() {
    local endpoint="$1"
    local admin_secret="$2"
    local query="$3"
    local operation_name="$4"
    
    log_debug "Executing Hasura API: $operation_name"
    log_debug "Endpoint: $endpoint"
    log_debug "Query: $query"
    
    local response=$(curl -s \
        -H "Content-Type: application/json" \
        -H "x-hasura-admin-secret: $admin_secret" \
        -d "$query" \
        "$endpoint/v1/metadata" 2>/dev/null)
    
    local curl_exit_code=$?
    
    if [[ $curl_exit_code -ne 0 ]]; then
        log_error "Failed to connect to Hasura API (curl exit code: $curl_exit_code)"
        return 1
    fi
    
    if [[ -z "$response" ]]; then
        log_error "Empty response from Hasura API"
        return 1
    fi
    
    # Check for Hasura API errors
    if echo "$response" | grep -q '"code"'; then
        log_error "Hasura API error in $operation_name:"
        echo "$response" | jq -r '.error // .message // .' 2>/dev/null || echo "$response"
        return 1
    fi
    
    echo "$response"
    return 0
}

reload_metadata() {
    local tier="$1"
    local environment="$2"
    
    local endpoint="$GRAPHQL_TIER_ENDPOINT"
    
    log_progress "Reloading metadata for $tier ($environment)..."
    
    local response=$(execute_hasura_api "$endpoint" "$GRAPHQL_TIER_ADMIN_SECRET" \
        '{"type": "reload_metadata", "args": {"reload_remote_schemas": true, "reload_sources": true}}' \
        "Metadata reload")
    
    if [[ $? -eq 0 ]]; then
        log_success "Metadata reloaded successfully"
        return 0
    else
        log_error "Failed to reload metadata"
        return 1
    fi
}

test_graphql_connection() {
    local tier="$1"
    local environment="$2"
    
    local endpoint="$GRAPHQL_TIER_ENDPOINT"
    
    log_progress "Testing GraphQL connection for $tier ($environment)..."
    
    # Test with simple introspection query
    local response=$(curl -s \
        -H "Content-Type: application/json" \
        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
        -d '{"query": "query { __schema { queryType { name } } }"}' \
        "$endpoint/v1/graphql" 2>/dev/null)
    
    local curl_exit_code=$?
    
    if [[ $curl_exit_code -ne 0 ]]; then
        log_error "Failed to connect to GraphQL endpoint"
        return 1
    fi
    
    if echo "$response" | grep -q '"data"'; then
        log_success "GraphQL connection successful"
        return 0
    else
        log_error "GraphQL connection failed: $response"
        return 1
    fi
}

# ============================================================================
# DOCKER MANAGEMENT FUNCTIONS
# ============================================================================

check_docker_running() {
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running"
        return 1
    fi
    return 0
}

get_container_status() {
    local container_name="$1"
    
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "^$container_name"; then
        echo "running"
    elif docker ps -a --format "table {{.Names}}\t{{.Status}}" | grep -q "^$container_name"; then
        echo "stopped"
    else
        echo "not_exists"
    fi
}

wait_for_graphql_service() {
    local tier="$1"
    local max_attempts=30
    local attempt=1
    
    log_progress "Waiting for $tier GraphQL service to start..."
    
    while [[ $attempt -le $max_attempts ]]; do
        if test_graphql_connection "$tier" "development" >/dev/null 2>&1; then
            log_success "GraphQL service is ready"
            return 0
        fi
        
        log_detail "Attempt $attempt/$max_attempts - waiting for service..."
        sleep 2
        ((attempt++))
    done
    
    log_error "GraphQL service failed to start after $max_attempts attempts"
    return 1
}

# ============================================================================
# TABLE AND RELATIONSHIP TRACKING FUNCTIONS
# ============================================================================

track_all_tables() {
    local tier="$1"
    local environment="$2"
    
    log_progress "Tracking all tables for $tier ($environment)..."
    
    local endpoint="$GRAPHQL_TIER_ENDPOINT"
    local source_name="default"  # Hasura default source name
    
    # First, ensure the database source exists and is configured
    log_detail "Checking database source configuration..."
    
    # Get current metadata to see what sources exist
    local metadata_response=$(execute_hasura_api "$endpoint" "$GRAPHQL_TIER_ADMIN_SECRET" \
        '{"type": "export_metadata", "args": {}}' \
        "Export metadata")
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to export metadata"
        return 1
    fi
    
    # Check if we have any sources configured
    local sources_count=$(echo "$metadata_response" | jq '.sources | length' 2>/dev/null || echo "0")
    
    if [[ "$sources_count" == "0" || "$sources_count" == "null" ]]; then
        log_warning "No database sources configured, cannot track tables"
        log_info "Database source must be configured before tracking tables"
        return 1
    fi
    
    # Get untracked tables using pg_dump_table_info API
    log_detail "Getting untracked tables..."
    
    local untracked_response=$(execute_hasura_api "$endpoint" "$GRAPHQL_TIER_ADMIN_SECRET" \
        "{\"type\": \"pg_get_source_tables\", \"args\": {\"source\": \"$source_name\"}}" \
        "Get source tables")
    
    if [[ $? -ne 0 ]]; then
        # Fallback: Try using SQL query to get tables
        log_detail "Trying SQL query approach..."
        
        local sql_response=$(execute_hasura_api "$endpoint" "$GRAPHQL_TIER_ADMIN_SECRET" \
            "{\"type\": \"run_sql\", \"args\": {\"source\": \"$source_name\", \"sql\": \"SELECT schemaname, tablename FROM pg_tables WHERE schemaname NOT IN ('information_schema', 'pg_catalog', 'hdb_catalog', 'hdb_views') ORDER BY schemaname, tablename;\"}}" \
            "Get tables via SQL")
        
        if [[ $? -ne 0 ]]; then
            log_warning "Could not get table list, performing metadata reload..."
            
            # Last resort: Just reload metadata
            local reload_response=$(execute_hasura_api "$endpoint" "$GRAPHQL_TIER_ADMIN_SECRET" \
                '{"type": "reload_metadata", "args": {"reload_remote_schemas": true, "reload_sources": true}}' \
                "Reload metadata")
            
            if [[ $? -eq 0 ]]; then
                log_success "Metadata reloaded successfully"
                return 0
            else
                log_error "Failed to reload metadata"
                return 1
            fi
        fi
        
        # Parse SQL response
        local tables=$(echo "$sql_response" | jq -r '.result[1:][]? | @csv' 2>/dev/null | sed 's/"//g')
    else
        # Parse untracked tables response
        local tables=$(echo "$untracked_response" | jq -r '.tables[]? | "\(.table_schema),\(.table_name)"' 2>/dev/null)
    fi
    
    if [[ -z "$tables" ]]; then
        log_info "No untracked tables found"
        return 0
    fi
    
    local tracked_count=0
    local failed_count=0
    local already_tracked=0
    
    # Track each table individually
    while IFS=',' read -r schema table; do
        if [[ -n "$schema" && -n "$table" ]]; then
            log_detail "Tracking: $schema.$table"
            
            local track_response=$(execute_hasura_api "$endpoint" "$GRAPHQL_TIER_ADMIN_SECRET" \
                "{\"type\": \"pg_track_table\", \"args\": {\"source\": \"$source_name\", \"schema\": \"$schema\", \"name\": \"$table\"}}" \
                "Track table $schema.$table")
            
            if [[ $? -eq 0 ]]; then
                ((tracked_count++))
            else
                # Check if already tracked
                if echo "$track_response" | grep -q "already tracked" 2>/dev/null; then
                    ((already_tracked++))
                else
                    ((failed_count++))
                fi
            fi
        fi
    done <<< "$tables"
    
    if [[ $tracked_count -gt 0 ]]; then
        log_success "Tracked $tracked_count new tables"
    fi
    if [[ $already_tracked -gt 0 ]]; then
        log_info "$already_tracked tables were already tracked"
    fi
    if [[ $failed_count -gt 0 ]]; then
        log_warning "$failed_count tables failed to track"
    fi
    
    return 0
}

track_relationships() {
    local tier="$1"
    local environment="$2"
    
    log_progress "Tracking relationships for $tier ($environment)..."
    
    local endpoint="$GRAPHQL_TIER_ENDPOINT"
    local source_name="default"
    
    # Get current metadata to analyze foreign keys
    log_detail "Analyzing foreign key relationships..."
    
    # Get foreign keys from database
    local fk_query="SELECT
        tc.table_schema,
        tc.table_name,
        kcu.column_name,
        ccu.table_schema AS foreign_table_schema,
        ccu.table_name AS foreign_table_name,
        ccu.column_name AS foreign_column_name,
        tc.constraint_name
    FROM information_schema.table_constraints AS tc
    JOIN information_schema.key_column_usage AS kcu
        ON tc.constraint_name = kcu.constraint_name
        AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage AS ccu
        ON ccu.constraint_name = tc.constraint_name
        AND ccu.table_schema = tc.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
        AND tc.table_schema NOT IN ('information_schema', 'pg_catalog', 'hdb_catalog')
    ORDER BY tc.table_schema, tc.table_name;"
    
    local fk_response=$(execute_hasura_api "$endpoint" "$GRAPHQL_TIER_ADMIN_SECRET" \
        "{\"type\": \"run_sql\", \"args\": {\"source\": \"$source_name\", \"sql\": \"$fk_query\"}}" \
        "Get foreign keys")
    
    if [[ $? -ne 0 ]]; then
        log_warning "Could not get foreign keys, trying metadata-based approach..."
        
        # Try pg_suggest_relationships API
        local suggest_response=$(execute_hasura_api "$endpoint" "$GRAPHQL_TIER_ADMIN_SECRET" \
            "{\"type\": \"pg_suggest_relationships\", \"args\": {\"source\": \"$source_name\", \"omit_tracked\": true}}" \
            "Suggest relationships")
        
        if [[ $? -ne 0 ]]; then
            # Final fallback: reload metadata
            local reload_response=$(execute_hasura_api "$endpoint" "$GRAPHQL_TIER_ADMIN_SECRET" \
                '{"type": "reload_metadata", "args": {"reload_remote_schemas": true, "reload_sources": true}}' \
                "Reload metadata")
            
            if [[ $? -eq 0 ]]; then
                log_success "Metadata reloaded for relationship discovery"
                return 0
            else
                log_error "Failed to process relationships"
                return 1
            fi
        fi
        
        # Process suggested relationships
        local relationships=$(echo "$suggest_response" | jq -r '.relationships[]?' 2>/dev/null)
        
        if [[ -n "$relationships" ]]; then
            log_info "Found suggested relationships to track"
            # Would process each relationship here
            return 0
        else
            log_info "No new relationships to track"
            return 0
        fi
    fi
    
    # Parse foreign key results
    local fks=$(echo "$fk_response" | jq -r '.result[1:][]? | @csv' 2>/dev/null | sed 's/"//g')
    
    if [[ -z "$fks" ]]; then
        log_info "No foreign key relationships found"
        return 0
    fi
    
    local tracked_count=0
    local failed_count=0
    
    # Track each relationship
    while IFS=',' read -r schema table column ref_schema ref_table ref_column constraint_name; do
        if [[ -n "$schema" && -n "$table" && -n "$ref_table" ]]; then
            # Create relationship name based on constraint
            local rel_name="${table}_${ref_table}"
            
            log_detail "Creating relationship: $schema.$table -> $ref_schema.$ref_table"
            
            # Object relationship (many-to-one)
            local obj_rel_response=$(execute_hasura_api "$endpoint" "$GRAPHQL_TIER_ADMIN_SECRET" \
                "{\"type\": \"pg_create_object_relationship\", \"args\": {\"source\": \"$source_name\", \"table\": {\"schema\": \"$schema\", \"name\": \"$table\"}, \"name\": \"$ref_table\", \"using\": {\"foreign_key_constraint_on\": \"$column\"}}}" \
                "Create object relationship")
            
            if [[ $? -eq 0 ]]; then
                ((tracked_count++))
            fi
            
            # Array relationship (one-to-many, from referenced table back)
            local arr_rel_response=$(execute_hasura_api "$endpoint" "$GRAPHQL_TIER_ADMIN_SECRET" \
                "{\"type\": \"pg_create_array_relationship\", \"args\": {\"source\": \"$source_name\", \"table\": {\"schema\": \"$ref_schema\", \"name\": \"$ref_table\"}, \"name\": \"${table}s\", \"using\": {\"foreign_key_constraint_on\": {\"table\": {\"schema\": \"$schema\", \"name\": \"$table\"}, \"column\": \"$column\"}}}}" \
                "Create array relationship")
            
            if [[ $? -eq 0 ]]; then
                ((tracked_count++))
            else
                ((failed_count++))
            fi
        fi
    done <<< "$fks"
    
    if [[ $tracked_count -gt 0 ]]; then
        log_success "Created $tracked_count relationships"
    fi
    if [[ $failed_count -gt 0 ]]; then
        log_warning "$failed_count relationships failed (may already exist)"
    fi
    
    return 0
}

# ============================================================================
# COMPREHENSIVE SUMMARY FUNCTION
# ============================================================================

print_operation_summary() {
    local operation="$1"
    local tier="$2"
    local environment="$3"
    
    echo ""
    section_header "🎯 OPERATION SUMMARY"
    log_info "Operation: $operation"
    log_info "Tier: $tier"
    log_info "Environment: $environment"
    log_info "Errors: $COMMAND_ERRORS"
    log_info "Warnings: $COMMAND_WARNINGS"
    
    if [[ $COMMAND_ERRORS -eq 0 ]]; then
        log_success "Operation completed successfully"
    else
        log_error "Operation completed with errors"
    fi
    
    end_timer
}

# ============================================================================
# SHARED SYSTEM DISCOVERY
# ============================================================================

discover_tier_repository() {
    local tier="$1"
    
    if [[ ! -d "$TIER_REPOSITORY_PATH" ]]; then
        log_error "Tier repository not found: $TIER_REPOSITORY_PATH"
        return 1
    fi
    
    log_debug "Found tier repository: $TIER_REPOSITORY_PATH"
    return 0
}

check_prerequisites() {
    # Check Docker
    if ! check_docker_running; then
        die "Docker is required but not running"
    fi
    
    # Check psql
    if ! command -v psql >/dev/null 2>&1; then
        die "PostgreSQL client (psql) is required but not installed"
    fi
    
    # Check curl
    if ! command -v curl >/dev/null 2>&1; then
        die "curl is required but not installed"
    fi
    
    # Check jq (for JSON parsing)
    if ! command -v jq >/dev/null 2>&1; then
        log_warning "jq not found - JSON output may be less readable"
    fi
    
    log_debug "All prerequisites checked"
    return 0
}

# ============================================================================
# INITIALIZATION
# ============================================================================

log_debug "Shared GraphQL functions loaded"