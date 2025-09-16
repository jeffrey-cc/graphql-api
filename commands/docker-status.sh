#!/bin/bash

# ============================================================================
# SHARED GRAPHQL DOCKER STATUS
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Check Docker container status for any GraphQL tier
# Usage: ./docker-status.sh <tier> <environment> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Docker Status Command

DESCRIPTION:
    Check the Docker container status for the specified GraphQL tier.
    This command will:
    - Configure tier-specific Docker settings
    - Check container running status
    - Display port mappings and health info
    - Test GraphQL service connectivity

USAGE:
    ./docker-status.sh <tier> <environment> [options]

ARGUMENTS:
    tier           One of: admin, operator, member
    environment    Either 'production' or 'development'

OPTIONS:
    -h, --help     Show this help message
    --detailed     Show detailed container information
    --logs         Show recent container logs

EXAMPLES:
    ./docker-status.sh member development     # Check member container status
    ./docker-status.sh admin development --detailed  # Detailed admin status

NOTES:
    - Only applies to development environment (uses Docker)
    - Production uses Hasura Cloud (no local containers)
    - Tests both container and GraphQL service health
EOF
}

# Parse command line arguments
TIER=""
ENVIRONMENT=""
DETAILED=false
SHOW_LOGS=false

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

section_header "📊 SHARED GRAPHQL DOCKER STATUS - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "Container: $GRAPHQL_TIER_CONTAINER"
log_info "Expected Port: $GRAPHQL_TIER_PORT"

# Production check - no Docker containers in production
if [[ "$ENVIRONMENT" == "production" ]]; then
    log_info "Production environment uses Hasura Cloud, not Docker containers"
    log_info "Use compare-environments.sh to check production status"
    exit 0
fi

# Start timing
start_timer

# Check if Docker is running
if ! check_docker_running; then
    log_error "Docker is not running"
    log_info "Please start Docker Desktop to check container status"
    exit 1
fi

# Get container status
container_status=$(get_container_status "$GRAPHQL_TIER_CONTAINER")
log_progress "Checking container status..."

case "$container_status" in
    "running")
        log_success "Container '$GRAPHQL_TIER_CONTAINER' is running"
        
        # Get detailed container information
        if command -v docker >/dev/null 2>&1; then
            # Get port mappings
            local port_mapping=$(docker port "$GRAPHQL_TIER_CONTAINER" 8080 2>/dev/null)
            if [[ -n "$port_mapping" ]]; then
                log_detail "Port mapping: 8080 → $port_mapping"
            else
                log_warning "No port mapping found for port 8080"
            fi
            
            # Get container uptime
            local created=$(docker inspect "$GRAPHQL_TIER_CONTAINER" --format='{{.Created}}' 2>/dev/null)
            if [[ -n "$created" ]]; then
                log_detail "Container created: $created"
            fi
            
            # Get container image
            local image=$(docker inspect "$GRAPHQL_TIER_CONTAINER" --format='{{.Config.Image}}' 2>/dev/null)
            if [[ -n "$image" ]]; then
                log_detail "Container image: $image"
            fi
        fi
        
        # Test GraphQL service connectivity
        log_progress "Testing GraphQL service connectivity..."
        if test_graphql_connection "$TIER" "$ENVIRONMENT"; then
            log_success "GraphQL service is accessible and healthy"
        else
            log_warning "Container is running but GraphQL service is not responsive"
            log_detail "Service may still be starting up"
        fi
        ;;
        
    "stopped")
        log_warning "Container '$GRAPHQL_TIER_CONTAINER' exists but is stopped"
        log_info "Use docker-start.sh to start the container"
        ;;
        
    "not_exists")
        log_error "Container '$GRAPHQL_TIER_CONTAINER' does not exist"
        log_info "Use docker-start.sh to create and start the container"
        ;;
        
    *)
        log_warning "Unknown container status: $container_status"
        ;;
esac

# Detailed information if requested
if [[ "$DETAILED" == "true" && "$container_status" == "running" ]]; then
    log_progress "Gathering detailed container information..."
    
    cd "$TIER_REPOSITORY_PATH"
    
    # docker-compose status
    log_detail "Docker Compose Status:"
    if docker-compose ps 2>/dev/null; then
        echo ""
    else
        log_warning "Could not get docker-compose status"
    fi
    
    # Container stats
    if command -v docker >/dev/null 2>&1; then
        log_detail "Container Resource Usage:"
        docker stats "$GRAPHQL_TIER_CONTAINER" --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null || log_warning "Could not get container stats"
    fi
    
    cd "$SCRIPT_DIR/.."
fi

# Show logs if requested
if [[ "$SHOW_LOGS" == "true" && "$container_status" == "running" ]]; then
    log_progress "Showing recent container logs..."
    
    cd "$TIER_REPOSITORY_PATH"
    
    if docker-compose logs --tail=20 "$GRAPHQL_TIER_CONTAINER" 2>/dev/null; then
        echo ""
    elif docker logs --tail=20 "$GRAPHQL_TIER_CONTAINER" 2>/dev/null; then
        echo ""
    else
        log_warning "Could not retrieve container logs"
    fi
    
    cd "$SCRIPT_DIR/.."
fi

# Summary based on status
case "$container_status" in
    "running")
        if test_graphql_connection "$TIER" "$ENVIRONMENT" >/dev/null 2>&1; then
            log_success "✅ Service Status: HEALTHY"
            log_info "GraphQL Endpoint: http://localhost:$GRAPHQL_TIER_PORT"
            log_info "GraphQL Console: http://localhost:$GRAPHQL_TIER_PORT/console"
        else
            log_warning "⚠️  Service Status: CONTAINER RUNNING, SERVICE NOT READY"
            log_info "Container may still be initializing"
        fi
        ;;
    "stopped")
        log_warning "🛑 Service Status: STOPPED"
        log_info "Run: ./docker-start.sh $TIER $ENVIRONMENT"
        ;;
    "not_exists")
        log_error "❌ Service Status: NOT CREATED"
        log_info "Run: ./docker-start.sh $TIER $ENVIRONMENT"
        ;;
    *)
        log_warning "❓ Service Status: UNKNOWN"
        ;;
esac

# Success summary
print_operation_summary "Docker Status Check" "$TIER" "$ENVIRONMENT"
# Return success exit code
exit 0
