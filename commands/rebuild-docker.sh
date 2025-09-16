#!/bin/bash

# ============================================================================
# SHARED GRAPHQL DOCKER REBUILD
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Complete Docker container destruction and recreation (30-45 seconds)
# Usage: ./rebuild-docker.sh <tier> <environment> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Docker Rebuild Command

DESCRIPTION:
    Complete container destruction and recreation from scratch (30-45 seconds).
    This is the NUCLEAR OPTION - use ONLY when:
    - GraphQL server won't start properly
    - Metadata is in an inconsistent state
    - Configuration is corrupted
    - Docker containers are in bad state

    This command will:
    - Delete ALL Docker containers and volumes
    - Destroy ALL GraphQL server settings and configuration
    - Recreate everything from ground zero
    - Re-import schema from database and rebuild metadata

USAGE:
    ./rebuild-docker.sh <tier> <environment> [options]

ARGUMENTS:
    tier           One of: admin, operator, member
    environment    Either 'production' or 'development'

OPTIONS:
    -h, --help     Show this help message
    -f, --force    Skip confirmation prompts

EXAMPLES:
    ./rebuild-docker.sh member development    # Rebuild member Docker (with confirmation)
    ./rebuild-docker.sh admin development -f # Force rebuild without confirmation

NOTES:
    - DESTRUCTIVE: Completely destroys existing containers and data
    - Use sparingly - try fast-refresh.sh first
    - Production environments require confirmation
    - Automatically tracks tables and relationships after rebuild
EOF
}

# Parse command line arguments
TIER=""
ENVIRONMENT=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            FORCE=true
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

# Check prerequisites
check_prerequisites

# Discover tier repository
if ! discover_tier_repository "$TIER"; then
    die "Could not find tier repository"
fi

section_header "💥 SHARED GRAPHQL DOCKER REBUILD - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "Repository: $TIER_REPOSITORY_PATH"
log_info "Start Time: $(date '+%Y-%m-%d %H:%M:%S')"

# Production safety confirmation
if [[ "$ENVIRONMENT" == "production" && "$FORCE" != "true" ]]; then
    echo ""
    log_warning "⚠️  PRODUCTION REBUILD REQUESTED ⚠️"
    log_warning "This will completely destroy and recreate the production GraphQL service"
    echo ""
    read -p "Are you sure you want to proceed? (type 'YES' to confirm): " confirm
    
    if [[ "$confirm" != "YES" ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
fi

# Development safety confirmation (unless forced)
if [[ "$ENVIRONMENT" == "development" && "$FORCE" != "true" ]]; then
    echo ""
    log_warning "This will completely destroy and recreate the $TIER GraphQL service"
    log_warning "All container data and metadata will be lost"
    echo ""
    read -p "Continue? (y/N): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
fi

# Start timing
start_timer

# Change to tier repository for docker-compose operations
log_progress "Changing to tier repository: $TIER_REPOSITORY_PATH"
cd "$TIER_REPOSITORY_PATH"

# Stop and remove containers with volumes
log_progress "Stopping and removing containers with volumes..."
if ! docker-compose down -v --remove-orphans; then
    log_warning "Docker compose down failed, attempting manual cleanup"
    
    # Manual cleanup
    docker stop "$GRAPHQL_TIER_CONTAINER" 2>/dev/null || true
    docker rm "$GRAPHQL_TIER_CONTAINER" 2>/dev/null || true
    docker volume rm "$GRAPHQL_TIER_VOLUME" 2>/dev/null || true
fi

# Verify containers are gone
log_progress "Verifying container removal..."
container_status=$(get_container_status "$GRAPHQL_TIER_CONTAINER")
if [[ "$container_status" != "not_exists" ]]; then
    log_warning "Container still exists, forcing removal..."
    docker rm -f "$GRAPHQL_TIER_CONTAINER" 2>/dev/null || true
fi

# Remove any dangling volumes
log_progress "Cleaning up dangling volumes..."
docker volume prune -f >/dev/null 2>&1 || true

# Start fresh containers
log_progress "Starting fresh containers..."
if ! docker-compose up -d; then
    die "Failed to start fresh containers"
fi

# Wait for GraphQL service to be ready
if ! wait_for_graphql_service "$TIER"; then
    die "GraphQL service failed to start after rebuild"
fi

# Return to shared directory
cd "$SCRIPT_DIR/.."

# Test connectivity
log_progress "Testing connectivity..."
if ! test_graphql_connection "$TIER" "$ENVIRONMENT"; then
    die "Failed to connect to rebuilt GraphQL service"
fi

# Reload metadata to pick up database schema
log_progress "Reloading metadata..."
if ! reload_metadata "$TIER" "$ENVIRONMENT"; then
    die "Failed to reload metadata after rebuild"
fi

# Track all tables
log_progress "Tracking database tables..."
if ! track_all_tables "$TIER" "$ENVIRONMENT"; then
    log_warning "Some tables failed to track"
fi

# Track relationships
log_progress "Tracking relationships..."
if ! track_relationships "$TIER" "$ENVIRONMENT"; then
    log_warning "Some relationships failed to track"
fi

# Final validation
log_progress "Validating rebuilt service..."
if ! test_graphql_connection "$TIER" "$ENVIRONMENT"; then
    die "Rebuild validation failed"
fi

# Success summary
print_operation_summary "Docker Rebuild" "$TIER" "$ENVIRONMENT"

echo ""
log_success "Docker rebuild completed successfully!"
log_info "Endpoint: http://localhost:$GRAPHQL_TIER_PORT"
log_info "GraphQL Console: http://localhost:$GRAPHQL_TIER_PORT/console"
log_info "Service is ready for use"
# Return success exit code
exit 0
