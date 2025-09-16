#!/bin/bash

# ============================================================================
# SHARED GRAPHQL DOCKER START
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Start Docker container for any GraphQL tier
# Usage: ./docker-start.sh <tier> <environment> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Docker Start Command

DESCRIPTION:
    Start the Docker container for the specified GraphQL tier.
    This command will:
    - Configure tier-specific Docker settings
    - Check Docker daemon status
    - Start the GraphQL container if not running
    - Validate container health

USAGE:
    ./docker-start.sh <tier> <environment> [options]

ARGUMENTS:
    tier           One of: admin, operator, member
    environment    Either 'production' or 'development'

OPTIONS:
    -h, --help     Show this help message
    --logs         Show container logs after start

EXAMPLES:
    ./docker-start.sh member development     # Start member container
    ./docker-start.sh admin development --logs  # Start admin with logs

NOTES:
    - Only applies to development environment (uses Docker)
    - Production uses Hasura Cloud (no local containers)
    - Will skip if container is already running
EOF
}

# Parse command line arguments
TIER=""
ENVIRONMENT=""
SHOW_LOGS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --logs)
            SHOW_LOGS=true
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

section_header "🐳 SHARED GRAPHQL DOCKER START - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "Container: $GRAPHQL_TIER_CONTAINER"
log_info "Repository: $TIER_REPOSITORY_PATH"

# Production check - no Docker containers in production
if [[ "$ENVIRONMENT" == "production" ]]; then
    log_warning "Production environment uses Hasura Cloud, not Docker containers"
    log_info "Skipping Docker start for production"
    exit 0
fi

# Start timing
start_timer

# Check if Docker is running
if ! check_docker_running; then
    die "Docker is not running. Please start Docker Desktop."
fi

# Check current container status
container_status=$(get_container_status "$GRAPHQL_TIER_CONTAINER")
log_detail "Current container status: $container_status"

case "$container_status" in
    "running")
        log_warning "Container '$GRAPHQL_TIER_CONTAINER' is already running"
        
        # Get container details
        if command -v docker >/dev/null 2>&1; then
            local container_port=$(docker port "$GRAPHQL_TIER_CONTAINER" 8080 2>/dev/null | cut -d: -f2)
            if [[ -n "$container_port" ]]; then
                log_info "Container port mapping: localhost:$container_port"
            fi
        fi
        
        log_success "Container is healthy and accessible"
        ;;
        
    "stopped")
        log_progress "Starting stopped container..."
        
        # Change to tier repository for docker-compose
        cd "$TIER_REPOSITORY_PATH"
        
        if docker start "$GRAPHQL_TIER_CONTAINER"; then
            log_success "Container started successfully"
        else
            log_warning "Failed to start existing container, trying docker-compose up..."
            if docker-compose up -d; then
                log_success "Container started via docker-compose"
            else
                die "Failed to start container"
            fi
        fi
        ;;
        
    "not_exists")
        log_progress "Creating and starting new container..."
        
        # Change to tier repository for docker-compose
        cd "$TIER_REPOSITORY_PATH"
        
        if docker-compose up -d; then
            log_success "Container created and started successfully"
        else
            die "Failed to create and start container"
        fi
        ;;
        
    *)
        log_warning "Unknown container status: $container_status"
        log_progress "Attempting to start container anyway..."
        
        cd "$TIER_REPOSITORY_PATH"
        
        if docker-compose up -d; then
            log_success "Container started successfully"
        else
            die "Failed to start container"
        fi
        ;;
esac

# Return to shared directory
cd "$SCRIPT_DIR/.."

# Wait for service to be ready
if ! wait_for_graphql_service "$TIER"; then
    log_warning "GraphQL service may not be fully ready yet"
else
    log_success "GraphQL service is ready and accessible"
fi

# Show logs if requested
if [[ "$SHOW_LOGS" == "true" ]]; then
    log_progress "Showing container logs..."
    cd "$TIER_REPOSITORY_PATH"
    docker-compose logs --tail=20 "$GRAPHQL_TIER_CONTAINER" || docker logs --tail=20 "$GRAPHQL_TIER_CONTAINER" 2>/dev/null || log_warning "Could not retrieve logs"
    cd "$SCRIPT_DIR/.."
fi

# Success summary
print_operation_summary "Docker Start" "$TIER" "$ENVIRONMENT"

log_success "Container started successfully!"
log_info "GraphQL Endpoint: http://localhost:$GRAPHQL_TIER_PORT"
log_info "GraphQL Console: http://localhost:$GRAPHQL_TIER_PORT/console"
log_info "Container: $GRAPHQL_TIER_CONTAINER"
# Return success exit code
exit 0
