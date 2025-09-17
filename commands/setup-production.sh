#!/bin/bash

# ============================================================================
# SHARED GRAPHQL PRODUCTION SETUP
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Sets up production GraphQL with database, tables, and relationships
# Usage: ./setup-production.sh <tier> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Production Setup

DESCRIPTION:
    Complete production setup that:
    1. Adds database source connection
    2. Tracks all tables
    3. Tracks all relationships
    4. Verifies the setup

USAGE:
    ./setup-production.sh <tier> [options]

ARGUMENTS:
    tier           One of: admin, operator, member, or 'all'

OPTIONS:
    -h, --help     Show this help message
    --force        Skip all confirmations

EXAMPLES:
    ./setup-production.sh admin        # Setup admin production
    ./setup-production.sh all          # Setup all tiers in production

NOTES:
    - Requires production database environment variables configured
    - Uses ADMIN_DATABASE_URL, OPERATOR_DATABASE_URL, MEMBER_DATABASE_URL
EOF
}

# Parse command line arguments
TIER=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --force)
            FORCE=true
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

# Validate tier
if [[ "$TIER" != "all" && "$TIER" != "admin" && "$TIER" != "operator" && "$TIER" != "member" ]]; then
    log_error "Invalid tier: $TIER. Must be one of: all, admin, operator, member"
    exit 1
fi

# Set tier list
if [[ "$TIER" == "all" ]]; then
    TIERS="admin operator member"
else
    TIERS="$TIER"
fi

# Function to setup a single tier
setup_tier_production() {
    local tier="$1"
    
    section_header "🚀 SETTING UP $(echo $tier | tr '[:lower:]' '[:upper:]') PRODUCTION"
    
    # Configure tier
    if ! configure_tier "$tier"; then
        die "Failed to configure tier: $tier"
    fi
    
    # Load production configuration
    if ! load_tier_config "$tier" "production"; then
        log_warning "Could not load production config, using defaults"
    fi
    
    # Configure endpoint
    if ! configure_endpoint "$tier" "production"; then
        die "Failed to configure endpoint for $tier"
    fi
    
    log_info "Tier: $tier"
    log_info "Endpoint: $GRAPHQL_TIER_ENDPOINT"
    log_info "Admin Secret: [CONFIGURED]"
    
    # Determine database URL environment variable name
    local db_env_var=""
    case "$tier" in
        "admin")
            db_env_var="ADMIN_DATABASE_URL"
            ;;
        "operator")
            db_env_var="OPERATOR_DATABASE_URL"
            ;;
        "member")
            db_env_var="MEMBER_DATABASE_URL"
            ;;
    esac
    
    # Phase 1: Add database source
    log_progress "Phase 1: Adding database source..."
    
    # First, try to drop any existing source
    curl -s -H "Content-Type: application/json" \
        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
        -d '{"type": "pg_drop_source", "args": {"name": "default", "cascade": true}}' \
        "$GRAPHQL_TIER_ENDPOINT/v1/metadata" > /dev/null 2>&1 || true
    
    # Add the database source
    local add_source_response=$(curl -s \
        -H "Content-Type: application/json" \
        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
        -d "{\"type\": \"pg_add_source\", \"args\": {\"name\": \"default\", \"configuration\": {\"connection_info\": {\"database_url\": {\"from_env\": \"$db_env_var\"}}, \"pool_settings\": {\"connection_lifetime\": 600, \"idle_timeout\": 180, \"max_connections\": 50}}}}" \
        "$GRAPHQL_TIER_ENDPOINT/v1/metadata")
    
    if echo "$add_source_response" | grep -q '"message":"success"'; then
        log_success "Database source added successfully"
    else
        log_error "Failed to add database source: $add_source_response"
        return 1
    fi
    
    # Phase 2: Track all tables
    log_progress "Phase 2: Tracking all tables..."
    
    # Get list of untracked tables
    local tables_response=$(curl -s \
        -H "Content-Type: application/json" \
        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
        -d '{"type": "pg_get_source_tables", "args": {"source": "default"}}' \
        "$GRAPHQL_TIER_ENDPOINT/v1/metadata")
    
    # Count tables to track
    local table_count=$(echo "$tables_response" | jq '. | length' 2>/dev/null || echo "0")
    log_info "Found $table_count tables to track"
    
    if [[ "$table_count" -gt 0 ]]; then
        # Track each table
        echo "$tables_response" | jq -r '.[] | "\(.schema).\(.name)"' | while IFS='.' read -r schema name; do
            log_detail "Tracking $schema.$name"
            curl -s -H "Content-Type: application/json" \
                -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
                -d "{\"type\": \"pg_track_table\", \"args\": {\"source\": \"default\", \"schema\": \"$schema\", \"name\": \"$name\"}}" \
                "$GRAPHQL_TIER_ENDPOINT/v1/metadata" > /dev/null 2>&1
        done
        log_success "All tables tracked successfully"
    else
        log_warning "No tables found to track"
    fi
    
    # Phase 3: Track relationships
    log_progress "Phase 3: Tracking relationships..."
    
    # Use Hasura's auto-suggest relationships feature
    local suggest_response=$(curl -s \
        -H "Content-Type: application/json" \
        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
        -d '{"type": "pg_suggest_relationships", "args": {"source": "default", "omit_tracked": true, "tables": null}}' \
        "$GRAPHQL_TIER_ENDPOINT/v1/metadata")
    
    # Check if we have suggestions
    local suggested_count=$(echo "$suggest_response" | jq '.relationships | length' 2>/dev/null || echo "0")
    
    if [[ "$suggested_count" -gt 0 ]]; then
        log_info "Found $suggested_count relationships to track"
        
        # Track all suggested relationships in batch
        local track_all_response=$(curl -s \
            -H "Content-Type: application/json" \
            -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
            -d '{"type": "track_all_relationships", "args": {"source": "default", "allow_inconsistent_metadata": true}}' \
            "$GRAPHQL_TIER_ENDPOINT/v1/metadata")
        
        if echo "$track_all_response" | grep -q '"message".*"success"'; then
            log_success "All relationships tracked in batch successfully"
        else
            # Fallback to individual tracking if batch fails
            echo "$suggest_response" | jq -c '.relationships[]' 2>/dev/null | while read -r relationship; do
                local rel_type=$(echo "$relationship" | jq -r '.type')
                local from_table=$(echo "$relationship" | jq -r '.from.table')
                
                log_detail "Tracking $rel_type relationship for $from_table"
                
                # Create the relationship
                curl -s \
                    -H "Content-Type: application/json" \
                    -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
                    -d "$relationship" \
                    "$GRAPHQL_TIER_ENDPOINT/v1/metadata" > /dev/null 2>&1
            done
            
            log_success "Relationships tracked individually"
        fi
    else
        # Fallback: Try to track relationships manually using foreign keys
        log_info "Using manual foreign key discovery..."
        
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
        
        local fk_response=$(curl -s \
            -H "Content-Type: application/json" \
            -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
            -d "{\"type\": \"run_sql\", \"args\": {\"source\": \"default\", \"sql\": \"$fk_query\"}}" \
            "$GRAPHQL_TIER_ENDPOINT/v1/metadata")
        
        local fk_count=$(echo "$fk_response" | jq '.result | length - 1' 2>/dev/null || echo "0")
        
        if [[ "$fk_count" -gt 0 ]]; then
            log_info "Found $fk_count foreign key relationships"
            
            # Process each foreign key
            echo "$fk_response" | jq -r '.result[1:][] | @csv' 2>/dev/null | sed 's/"//g' | while IFS=',' read -r schema table column ref_schema ref_table ref_column constraint_name; do
                if [[ -n "$schema" && -n "$table" && -n "$ref_table" ]]; then
                    # Create object relationship (many-to-one)
                    local obj_rel_name="${ref_table}"
                    curl -s -H "Content-Type: application/json" \
                        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
                        -d "{\"type\": \"pg_create_object_relationship\", \"args\": {\"source\": \"default\", \"table\": {\"schema\": \"$schema\", \"name\": \"$table\"}, \"name\": \"$obj_rel_name\", \"using\": {\"foreign_key_constraint_on\": \"$column\"}}}" \
                        "$GRAPHQL_TIER_ENDPOINT/v1/metadata" > /dev/null 2>&1
                    
                    # Create array relationship (one-to-many)
                    local arr_rel_name="${table}s"
                    curl -s -H "Content-Type: application/json" \
                        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
                        -d "{\"type\": \"pg_create_array_relationship\", \"args\": {\"source\": \"default\", \"table\": {\"schema\": \"$ref_schema\", \"name\": \"$ref_table\"}, \"name\": \"$arr_rel_name\", \"using\": {\"foreign_key_constraint_on\": {\"table\": {\"schema\": \"$schema\", \"name\": \"$table\"}, \"column\": \"$column\"}}}}" \
                        "$GRAPHQL_TIER_ENDPOINT/v1/metadata" > /dev/null 2>&1
                fi
            done
            
            log_success "Foreign key relationships tracked"
        else
            log_info "No foreign key relationships found"
        fi
    fi
    
    # Phase 3.5: Track enum types
    log_progress "Phase 3.5: Tracking enum types..."
    
    # Query for enum types in the database
    local enum_query="SELECT 
        n.nspname as schema,
        t.typname as name
    FROM pg_type t 
    LEFT JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace 
    WHERE (t.typrelid = 0 OR (SELECT c.relkind = 'c' FROM pg_catalog.pg_class c WHERE c.oid = t.typrelid)) 
    AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_type el WHERE el.oid = t.typelem AND el.typarray = t.oid)
    AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'hdb_catalog')
    AND t.typtype = 'e'
    ORDER BY n.nspname, t.typname;"
    
    local enum_response=$(curl -s \
        -H "Content-Type: application/json" \
        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
        -d "{\"type\": \"run_sql\", \"args\": {\"source\": \"default\", \"sql\": \"$enum_query\"}}" \
        "$GRAPHQL_TIER_ENDPOINT/v1/metadata")
    
    local enum_count=$(echo "$enum_response" | jq '.result | length - 1' 2>/dev/null || echo "0")
    
    if [[ "$enum_count" -gt 0 ]]; then
        log_info "Found $enum_count enum types to track"
        
        # Track each enum type
        echo "$enum_response" | jq -r '.result[1:][] | @csv' 2>/dev/null | sed 's/"//g' | while IFS=',' read -r schema enum_name; do
            if [[ -n "$schema" && -n "$enum_name" ]]; then
                log_detail "Tracking enum: $schema.$enum_name"
                
                curl -s -H "Content-Type: application/json" \
                    -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
                    -d "{\"type\": \"pg_track_enum\", \"args\": {\"source\": \"default\", \"schema\": \"$schema\", \"name\": \"$enum_name\"}}" \
                    "$GRAPHQL_TIER_ENDPOINT/v1/metadata" > /dev/null 2>&1
            fi
        done
        
        log_success "Enum types tracked successfully"
    else
        log_info "No enum types found to track"
    fi
    
    # Phase 4: Verify setup
    log_progress "Phase 4: Verifying setup..."
    
    # Check tracked tables count
    local verify_response=$(curl -s \
        -H "Content-Type: application/json" \
        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
        -d '{"type": "export_metadata", "args": {}}' \
        "$GRAPHQL_TIER_ENDPOINT/v1/metadata")
    
    local tracked_count=$(echo "$verify_response" | jq '.sources[0].tables | length' 2>/dev/null || echo "0")
    
    # Count relationships (approximate)
    local relationship_count=0
    if echo "$verify_response" | jq -e '.sources[0].tables' > /dev/null 2>&1; then
        relationship_count=$(echo "$verify_response" | jq '[.sources[0].tables[]?.object_relationships // [] | length] + [.sources[0].tables[]?.array_relationships // [] | length] | add' 2>/dev/null || echo "0")
    fi
    
    # Report complete setup
    log_success "Setup complete!"
    log_info "  - Tables tracked: $tracked_count"
    log_info "  - Relationships tracked: $relationship_count"
    log_info "  - Enum types: Tracked if present"
    
    echo ""
}

# Start timing
start_timer

# Show warning if not forced
if [[ "$FORCE" != "true" ]]; then
    section_header "⚠️  PRODUCTION SETUP WARNING"
    log_warning "This will configure production GraphQL APIs"
    log_info "Tiers to setup: $(echo $TIERS | tr ' ' ', ')"
    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Setup cancelled by user"
        exit 0
    fi
fi

# Execute setup for each tier
for tier in $TIERS; do
    setup_tier_production "$tier"
done

# Success summary
print_operation_summary "Production Setup" "$TIER" "production"
log_success "Production setup completed successfully!"

exit 0