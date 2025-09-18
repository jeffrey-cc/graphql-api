#!/bin/bash

# ============================================================================
# SHARED GRAPHQL FAST REFRESH
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Fast metadata refresh for routine updates (1-3 seconds)
# Usage: ./fast-refresh.sh <tier> <environment> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Fast Refresh Command

DESCRIPTION:
    Lightning-fast metadata refresh for routine updates (1-3 seconds).
    Use when database structure hasn't changed but you need to:
    - Pick up database schema changes
    - Reload metadata without downtime
    - Regular maintenance and updates

USAGE:
    ./fast-refresh.sh <tier> <environment> [options]

ARGUMENTS:
    tier           One of: admin, operator, member
    environment    Either 'production' or 'development'

OPTIONS:
    -h, --help     Show this help message

EXAMPLES:
    ./fast-refresh.sh member development      # Refresh member API metadata
    ./fast-refresh.sh admin production        # Refresh admin API in production

NOTES:
    - Does NOT delete or recreate Docker containers
    - Does NOT restart GraphQL service
    - Only reloads metadata and schema cache
    - Fallback to rebuild-docker.sh if metadata is corrupted
EOF
}

# Parse command line arguments
TIER=""
ENVIRONMENT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
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

# Check prerequisites
check_prerequisites

# Configure endpoint for the environment
if ! configure_endpoint "$TIER" "$ENVIRONMENT"; then
    die "Failed to configure endpoint for $TIER ($ENVIRONMENT)"
fi

section_header "🔄 SHARED GRAPHQL FAST REFRESH - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "Start Time: $(date '+%Y-%m-%d %H:%M:%S')"
log_info "Endpoint: $GRAPHQL_TIER_ENDPOINT"

# Start timing
start_timer

# Test connectivity
if ! test_graphql_connection "$TIER" "$ENVIRONMENT"; then
    die "Cannot connect to GraphQL service. Is it running?"
fi

# Reload metadata (picks up all database changes)
log_progress "Reloading metadata..."
if ! reload_metadata "$TIER" "$ENVIRONMENT"; then
    log_warning "Metadata reload failed. May indicate corruption. Falling back to Docker rebuild..."
    
    # Call Docker rebuild script from shared system
    exec "$SCRIPT_DIR/rebuild-docker.sh" "$TIER" "$ENVIRONMENT"
fi

# Track all tables
log_progress "Tracking database tables..."
if ! track_all_tables "$TIER" "$ENVIRONMENT"; then
    log_warning "Some tables failed to track"
fi

# Track relationships (CRITICAL for GraphQL nested queries)
log_progress "Tracking foreign key relationships..."
if ! track_relationships "$TIER" "$ENVIRONMENT"; then
    log_warning "Some relationships failed to track - GraphQL nested queries may not work!"
fi

# Verify GraphQL schema is working
log_progress "Verifying GraphQL schema..."
if ! test_graphql_connection "$TIER" "$ENVIRONMENT"; then
    die "GraphQL schema verification failed"
fi

# Success summary
print_operation_summary "Fast Refresh" "$TIER" "$ENVIRONMENT"

log_success "Fast refresh completed successfully!"
log_info "Endpoint: http://localhost:$GRAPHQL_TIER_PORT"
# Return success exit code
exit 0
