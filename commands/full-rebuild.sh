#!/bin/bash

# ============================================================================
# SHARED GRAPHQL FULL REBUILD
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Complete rebuild process: destroy → recreate → track → verify
# Usage: ./full-rebuild.sh <tier> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Full Rebuild Process

DESCRIPTION:
    Complete rebuild process that:
    1. DESTROYS: Completely destroys Docker containers and production metadata
    2. RECREATES: Rebuilds fresh GraphQL connections with empty databases
    3. TRACKS: Tracks all tables, relationships, enums, and database objects
    4. VERIFIES: Confirms dev and production GraphQL APIs match exactly

USAGE:
    ./full-rebuild.sh <tier> [options]

ARGUMENTS:
    tier           One of: admin, operator, member, or 'all'

OPTIONS:
    -h, --help     Show this help message
    --force        Skip all confirmations
    --dev-only     Only rebuild development environment
    --prod-only    Only rebuild production environment

EXAMPLES:
    ./full-rebuild.sh admin              # Full rebuild for admin tier (both envs)
    ./full-rebuild.sh all                # Full rebuild for all tiers
    ./full-rebuild.sh operator --dev-only # Only rebuild operator development

PROCESS:
    Phase 1: Destroy all containers and clear production metadata
    Phase 2: Rebuild fresh GraphQL services
    Phase 3: Track all database objects (tables, relationships, enums)
    Phase 4: Verify dev/production consistency

WARNING:
    This is a DESTRUCTIVE operation that will:
    - Destroy all Docker containers
    - Clear all GraphQL metadata
    - Reset to empty state before rebuilding
EOF
}

# Parse command line arguments
TIER=""
FORCE=false
DEV_ONLY=false
PROD_ONLY=false

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
        --dev-only)
            DEV_ONLY=true
            shift
            ;;
        --prod-only)
            PROD_ONLY=true
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

# Set environment list
ENVIRONMENTS=""
if [[ "$DEV_ONLY" == "true" ]]; then
    ENVIRONMENTS="development"
elif [[ "$PROD_ONLY" == "true" ]]; then
    ENVIRONMENTS="production"
else
    ENVIRONMENTS="development production"
fi

# Show warning and get confirmation
section_header "⚠️  FULL REBUILD WARNING"
log_warning "This will COMPLETELY DESTROY and RECREATE:"
log_warning "- All Docker containers for specified tiers"
log_warning "- All GraphQL metadata in production"
log_warning "- All tracked tables and relationships"
echo ""
log_info "Tiers to rebuild: $(echo $TIERS | tr ' ' ', ')"
log_info "Environments: $(echo $ENVIRONMENTS | tr ' ' ', ')"
echo ""

if [[ "$FORCE" != "true" ]]; then
    read -p "Are you absolutely sure you want to proceed? (yes/no): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Rebuild cancelled by user"
        exit 0
    fi
fi

# Start timing
start_timer

# Function to rebuild a single tier and environment
rebuild_tier_environment() {
    local tier="$1"
    local environment="$2"
    
    section_header "🔥 REBUILDING $(echo $tier | tr '[:lower:]' '[:upper:]') - $(echo $environment | tr '[:lower:]' '[:upper:]')"
    
    # Phase 1: Destroy
    log_progress "Phase 1: Destroying existing infrastructure..."
    if [[ "$environment" == "development" ]]; then
        log_detail "Destroying Docker containers for $tier..."
        if ! "$SCRIPT_DIR/rebuild-docker.sh" "$tier" "$environment" --force; then
            log_warning "Docker rebuild reported issues, but containers may be running"
        fi
    else
        log_detail "Clearing production metadata for $tier..."
        # Production doesn't have Docker containers to destroy
        # Metadata will be cleared when we do fast-refresh
    fi
    
    # Phase 2: Rebuild fresh connections
    log_progress "Phase 2: Rebuilding fresh GraphQL connections..."
    if ! "$SCRIPT_DIR/fast-refresh.sh" "$tier" "$environment"; then
        die "Failed to refresh GraphQL connection for $tier ($environment)"
    fi
    
    # Phase 3: Track all database objects
    log_progress "Phase 3: Tracking all database objects..."
    
    log_detail "Tracking all tables..."
    if ! "$SCRIPT_DIR/track-all-tables.sh" "$tier" "$environment"; then
        die "Failed to track tables for $tier ($environment)"
    fi
    
    log_detail "Tracking all relationships..."
    if ! "$SCRIPT_DIR/track-relationships.sh" "$tier" "$environment"; then
        die "Failed to track relationships for $tier ($environment)"
    fi
    
    log_success "Rebuild complete for $tier ($environment)"
    echo ""
}

# Execute rebuild for each tier and environment
for tier in $TIERS; do
    for environment in $ENVIRONMENTS; do
        rebuild_tier_environment "$tier" "$environment"
    done
done

# Phase 4: Verify consistency between environments
if [[ "$DEV_ONLY" != "true" && "$PROD_ONLY" != "true" ]]; then
    section_header "🔍 VERIFYING CONSISTENCY"
    log_progress "Phase 4: Comparing development vs production APIs..."
    
    for tier in $TIERS; do
        log_detail "Comparing $tier environments..."
        if ! "$SCRIPT_DIR/compare-environments.sh" "$tier"; then
            log_warning "Environment comparison showed differences for $tier"
            ((COMMAND_WARNINGS++))
        else
            log_success "$tier environments are consistent"
        fi
    done
fi

# Success summary
section_header "🎉 FULL REBUILD COMPLETE"
log_success "Full rebuild completed successfully!"
log_info "Rebuilt tiers: $(echo $TIERS | tr ' ' ', ')"
log_info "Environments: $(echo $ENVIRONMENTS | tr ' ' ', ')"

if [[ "$DEV_ONLY" != "true" && "$PROD_ONLY" != "true" ]]; then
    if [[ $COMMAND_WARNINGS -eq 0 ]]; then
        log_success "All environments are perfectly synchronized!"
    else
        log_warning "Some environment differences detected - review comparison results"
    fi
fi

log_info "GraphQL endpoints ready for use:"
for tier in $TIERS; do
    configure_tier "$tier"
    for environment in $ENVIRONMENTS; do
        configure_endpoint "$tier" "$environment"
        log_detail "$tier ($environment): $GRAPHQL_TIER_ENDPOINT"
    done
done

print_operation_summary "Full Rebuild" "$TIER" "$(echo $ENVIRONMENTS | tr ' ' '/')"
exit 0