#!/bin/bash

# ============================================================================
# SHARED GRAPHQL SMART RELATIONSHIP TRACKING COMMAND
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Tracks foreign key relationships with intelligent naming conventions
# Usage: ./track-relationships-smart.sh <tier> [environment]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
SHARED GRAPHQL SMART RELATIONSHIP TRACKING COMMAND
Community Connect Tech - Shared GraphQL API System

DESCRIPTION:
    Tracks foreign key relationships with intelligent naming conventions.
    Uses context-aware naming to ensure frontend compatibility.
    
    Naming Rules:
    - company_id -> operator_company (when referencing operator_companies)
    - user_id -> user (standard removal of _id)
    - assigned_to_id -> assigned_to (keeps context)
    - created_by_id -> created_by (keeps context)
    - member_id -> member (for member references)
    - facility_id -> facility (for facility references)
    
    This ensures frontend compatibility with expected relationship names.

USAGE:
    ./track-relationships-smart.sh <tier> [environment]

ARGUMENTS:
    tier           admin, operator, or member
    environment    production or development (default: development)

EXAMPLES:
    ./track-relationships-smart.sh admin development
    ./track-relationships-smart.sh operator production
    ./track-relationships-smart.sh member development

FEATURES:
    - Automatic foreign key discovery
    - Smart naming based on context
    - Handles multiple FKs to same table
    - Frontend-compatible names
    - Idempotent operation
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
print_header "🧠 SMART RELATIONSHIP TRACKING - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Environment: $ENVIRONMENT"
echo ""

# Load environment configuration
load_environment "$TIER" "$ENVIRONMENT"
if [ $? -ne 0 ]; then
    exit 1
fi

# Function to generate smart relationship name
get_smart_relationship_name() {
    local fk_column="$1"
    local referenced_table="$2"
    local referenced_schema="$3"
    
    # Remove _id suffix if present
    local base_name="${fk_column%_id}"
    
    # Special cases for tier-specific naming
    case "$referenced_table" in
        "operator_companies")
            echo "operator_company"
            ;;
        "admin_users")
            if [[ "$fk_column" == "created_by_id" ]]; then
                echo "created_by_user"
            elif [[ "$fk_column" == "updated_by_id" ]]; then
                echo "updated_by_user"
            elif [[ "$fk_column" == "assigned_to_id" ]]; then
                echo "assigned_to_user"
            else
                echo "${base_name}_user"
            fi
            ;;
        "members")
            echo "member"
            ;;
        "facilities")
            echo "facility"
            ;;
        "operators")
            echo "operator"
            ;;
        "principals")
            # For identity system
            if [[ "$fk_column" == "member_id" ]]; then
                echo "member"
            elif [[ "$fk_column" == "operator_id" ]]; then
                echo "operator"
            else
                echo "${base_name}"
            fi
            ;;
        *)
            # Default: use base name without _id
            echo "$base_name"
            ;;
    esac
}

# Function to track a relationship
track_relationship() {
    local schema="$1"
    local table="$2"
    local fk_column="$3"
    local ref_schema="$4"
    local ref_table="$5"
    local ref_column="$6"
    
    # Generate smart name
    local rel_name=$(get_smart_relationship_name "$fk_column" "$ref_table" "$ref_schema")
    
    log_step "Tracking: ${schema}.${table}.${fk_column} → ${ref_schema}.${ref_table} as '${rel_name}'"
    
    # Create the relationship
    RESPONSE=$(curl -s -X POST "${GRAPHQL_ENDPOINT}/v1/metadata" \
        -H "x-hasura-admin-secret: ${GRAPHQL_TIER_ADMIN_SECRET}" \
        -H "Content-Type: application/json" \
        -d "{
            \"type\": \"pg_create_object_relationship\",
            \"args\": {
                \"source\": \"${TIER}_database\",
                \"table\": {
                    \"schema\": \"$schema\",
                    \"name\": \"$table\"
                },
                \"name\": \"$rel_name\",
                \"using\": {
                    \"foreign_key_constraint_on\": \"$fk_column\"
                }
            }
        }")
    
    if echo "$RESPONSE" | jq -e '.message == "success"' >/dev/null 2>&1; then
        log_success "Created relationship: $rel_name"
        return 0
    elif echo "$RESPONSE" | grep -q "already exists"; then
        log_info "Relationship already exists: $rel_name"
        return 0
    else
        log_error "Failed to create relationship: $rel_name"
        log_debug "Response: $RESPONSE"
        return 1
    fi
}

# Get foreign keys from database
log_section "Discovering Foreign Keys"

if [ "$ENVIRONMENT" == "development" ]; then
    # Query database for foreign keys
    FK_QUERY="SELECT 
        tc.table_schema,
        tc.table_name,
        kcu.column_name,
        ccu.table_schema AS ref_schema,
        ccu.table_name AS ref_table,
        ccu.column_name AS ref_column
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
        AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage ccu
        ON ccu.constraint_name = tc.constraint_name
        AND ccu.table_schema = tc.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
        AND tc.table_schema NOT IN ('pg_catalog', 'information_schema', 'hasura', 'hdb_catalog')
    ORDER BY tc.table_schema, tc.table_name, kcu.column_name;"
    
    FOREIGN_KEYS=$(PGPASSWORD="$DB_TIER_PASSWORD" psql -h localhost -p "$DB_TIER_PORT" -U "$DB_TIER_USER" -d "$DB_TIER_DATABASE" -t -A -F"|" -c "$FK_QUERY" 2>/dev/null)
    
    if [ -z "$FOREIGN_KEYS" ]; then
        log_warning "No foreign keys found in database"
        exit 0
    fi
    
    # Count foreign keys
    FK_COUNT=$(echo "$FOREIGN_KEYS" | wc -l)
    log_info "Found $FK_COUNT foreign key(s) to process"
    echo ""
    
    # Track each foreign key
    SUCCESS_COUNT=0
    FAIL_COUNT=0
    
    log_section "Creating Smart Relationships"
    
    echo "$FOREIGN_KEYS" | while IFS='|' read -r schema table fk_column ref_schema ref_table ref_column; do
        if track_relationship "$schema" "$table" "$fk_column" "$ref_schema" "$ref_table" "$ref_column"; then
            ((SUCCESS_COUNT++))
        else
            ((FAIL_COUNT++))
            ((COMMAND_ERRORS++))
        fi
    done
else
    log_warning "Smart relationship tracking uses database introspection (development only)"
    log_info "For production, relationships should be tracked via metadata"
    exit 0
fi

# Print summary
print_summary

# Final status
echo ""
if [ $COMMAND_ERRORS -eq 0 ]; then
    log_success "Smart relationship tracking completed successfully!"
    log_info "Created $SUCCESS_COUNT relationship(s) with intelligent naming"
else
    log_error "Tracking completed with $COMMAND_ERRORS error(s)"
fi

exit $COMMAND_ERRORS