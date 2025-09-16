#!/bin/bash

# ============================================================================
# SHARED GRAPHQL DOCKER STOP
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Stop Docker container for any GraphQL tier
# Usage: ./docker-stop.sh <tier> <environment> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Docker Stop Command

DESCRIPTION:
    Stop the Docker container for the specified GraphQL tier.
    This command will:
    - Configure tier-specific Docker settings
    - Stop the running GraphQL container
    - Optionally remove volumes and clean up

USAGE:
    ./docker-stop.sh <tier> <environment> [options]

ARGUMENTS:
    tier           One of: admin, operator, member
    environment    Either 'production' or 'development'

OPTIONS:
    -h, --help     Show this help message
    --remove-volumes   Remove Docker volumes (destructive)
    --force        Force stop without confirmation

EXAMPLES:
    ./docker-stop.sh member development        # Stop member container
    ./docker-stop.sh admin development --remove-volumes  # Stop and remove volumes

NOTES:
    - Only applies to development environment (uses Docker)
    - Production uses Hasura Cloud (no local containers)
    - --remove-volumes will delete all container data
EOF
}

# Parse command line arguments
TIER=""
ENVIRONMENT=""
REMOVE_VOLUMES=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --remove-volumes)
            REMOVE_VOLUMES=true
            shift
            ;;
        --force)
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

section_header "🛑 SHARED GRAPHQL DOCKER STOP - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "Container: $GRAPHQL_TIER_CONTAINER"
log_info "Repository: $TIER_REPOSITORY_PATH"

# Production check - no Docker containers in production
if [[ "$ENVIRONMENT" == "production" ]]; then
    log_warning "Production environment uses Hasura Cloud, not Docker containers"
    log_info "Skipping Docker stop for production"
    exit 0
fi

# Volume removal confirmation
if [[ "$REMOVE_VOLUMES" == "true" && "$FORCE" != "true" ]]; then
    echo ""
    log_warning "⚠️  VOLUME REMOVAL REQUESTED ⚠️"
    log_warning "This will permanently delete all GraphQL metadata and configuration"
    echo ""
    read -p "Are you sure you want to remove volumes? (y/N): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
fi

# Start timing
start_timer

# Check if Docker is running
if ! check_docker_running; then
    log_warning "Docker is not running - containers may already be stopped"
fi

# Check current container status
container_status=$(get_container_status "$GRAPHQL_TIER_CONTAINER")
log_detail "Current container status: $container_status"

case "$container_status" in
    "running")
        log_progress "Stopping running container..."
        
        # Change to tier repository for docker-compose
        cd "$TIER_REPOSITORY_PATH"
        
        if [[ "$REMOVE_VOLUMES" == "true" ]]; then
            log_warning "Stopping container and removing volumes..."
            if docker-compose down -v; then
                log_success "Container stopped and volumes removed"
            else
                log_warning "docker-compose failed, trying manual stop..."
                docker stop "$GRAPHQL_TIER_CONTAINER" 2>/dev/null || true
                docker rm "$GRAPHQL_TIER_CONTAINER" 2>/dev/null || true
                docker volume rm "$GRAPHQL_TIER_VOLUME" 2>/dev/null || true
                log_success "Container stopped manually"
            fi
        else
            if docker-compose stop; then
                log_success "Container stopped successfully"
            else
                log_warning "docker-compose failed, trying manual stop..."
                if docker stop "$GRAPHQL_TIER_CONTAINER"; then
                    log_success "Container stopped manually"
                else
                    log_error "Failed to stop container"
                fi
            fi
        fi
        ;;
        
    "stopped")
        log_info "Container '$GRAPHQL_TIER_CONTAINER' is already stopped"
        
        if [[ "$REMOVE_VOLUMES" == "true" ]]; then
            log_progress "Removing volumes for stopped container..."
            cd "$TIER_REPOSITORY_PATH"
            
            docker-compose down -v 2>/dev/null || true
            docker rm "$GRAPHQL_TIER_CONTAINER" 2>/dev/null || true
            docker volume rm "$GRAPHQL_TIER_VOLUME" 2>/dev/null || true
            
            log_success "Volumes removed"
        fi
        ;;
        
    "not_exists")
        log_info "Container '$GRAPHQL_TIER_CONTAINER' does not exist"
        
        if [[ "$REMOVE_VOLUMES" == "true" ]]; then
            log_progress "Cleaning up any orphaned volumes..."
            docker volume rm "$GRAPHQL_TIER_VOLUME" 2>/dev/null || true
            log_info "Cleanup completed"
        fi
        ;;
        
    *)
        log_warning "Unknown container status: $container_status"
        log_progress "Attempting to stop anyway..."
        
        cd "$TIER_REPOSITORY_PATH"
        
        if [[ "$REMOVE_VOLUMES" == "true" ]]; then
            docker-compose down -v 2>/dev/null || true
        else
            docker-compose stop 2>/dev/null || true
        fi
        
        log_info "Stop attempt completed"
        ;;
esac

# Return to shared directory
cd "$SCRIPT_DIR/.."

# Verify container is stopped
final_status=$(get_container_status "$GRAPHQL_TIER_CONTAINER")
case "$final_status" in
    "not_exists"|"stopped")
        log_success "Container is properly stopped"
        ;;
    "running")
        log_warning "Container may still be running"
        ;;
    *)
        log_detail "Final container status: $final_status"
        ;;
esac

# Success summary
print_operation_summary "Docker Stop" "$TIER" "$ENVIRONMENT"

log_success "Docker stop operation completed!"
if [[ "$REMOVE_VOLUMES" == "true" ]]; then
    log_info "All volumes and data have been removed"
else
    log_info "Container data preserved (use --remove-volumes to clean up)"
fi
# Return success exit code
exit 0
