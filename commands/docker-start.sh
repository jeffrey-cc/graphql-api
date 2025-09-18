#!/bin/bash

# ================================================================================
# Docker Start Command - Start GraphQL Container for Specified Tier
# ================================================================================
# Starts the Docker GraphQL container for development environment using unified stack
# Usage: ./docker-start.sh <tier>
# ================================================================================

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Source shared functions
source "$SCRIPT_DIR/_shared_functions.sh"

# ================================================================================
# Help Documentation
# ================================================================================

show_help() {
    cat << EOF
Shared GraphQL API - Docker Start Command

DESCRIPTION:
    Start GraphQL Docker container for specified tier using unified docker-compose stack.
    
USAGE:
    ./docker-start.sh <tier>

ARGUMENTS:
    tier              GraphQL tier (admin, operator, member, or all)

EXAMPLES:
    Start admin GraphQL container:
    ./docker-start.sh admin

    Start operator GraphQL container:
    ./docker-start.sh operator
    
    Start all GraphQL containers:
    ./docker-start.sh all

CONTAINER CONFIGURATION:
    admin:    Port 8101, Container: admin-graphql-server
    operator: Port 8102, Container: operator-graphql-server  
    member:   Port 8103, Container: member-graphql-server

NOTES:
    - Uses unified docker-compose.yml stack
    - Automatically waits for database connectivity
    - Includes health checks for all services
    - Part of shared GraphQL API management system
EOF
}

# ================================================================================
# Parse Arguments
# ================================================================================

TIER="${1:-}"

if [[ "$TIER" == "-h" ]] || [[ "$TIER" == "--help" ]]; then
    show_help
    exit 0
fi

if [[ -z "$TIER" ]]; then
    log_error "Tier argument is required"
    show_help
    exit 1
fi

# ================================================================================
# Main Logic
# ================================================================================

main() {
    section_header "Starting GraphQL Docker Container - $TIER Tier"
    
    # Check if docker-compose.yml exists
    if [[ ! -f "$PARENT_DIR/docker-compose.yml" ]]; then
        log_error "docker-compose.yml not found in $PARENT_DIR"
        exit 1
    fi

    # Change to parent directory for docker-compose
    cd "$PARENT_DIR"

    local services_to_start=()

    # Process tier argument
    case "$TIER" in
        admin)
            services_to_start=("admin-graphql-server")
            ;;
        operator)
            services_to_start=("operator-graphql-server")
            ;;
        member)
            services_to_start=("member-graphql-server")
            ;;
        all)
            services_to_start=("admin-graphql-server" "operator-graphql-server" "member-graphql-server")
            ;;
        *)
            log_error "Invalid tier: $TIER (must be admin, operator, member, or all)"
            exit 1
            ;;
    esac

    # Start the containers
    log_progress "Starting GraphQL containers: ${services_to_start[*]}"
    
    if docker-compose up -d "${services_to_start[@]}"; then
        log_success "GraphQL containers started successfully"
    else
        log_error "Failed to start GraphQL containers"
        exit 1
    fi

    # Wait for containers to be healthy
    log_progress "Waiting for containers to be healthy..."
    
    for service in "${services_to_start[@]}"; do
        local max_attempts=30
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            if docker-compose ps "$service" | grep -q "healthy\|Up"; then
                log_success "$service is healthy"
                break
            elif [ $attempt -eq $max_attempts ]; then
                log_warning "$service may not be fully healthy yet"
                break
            else
                echo -n "."
                sleep 2
                ((attempt++))
            fi
        done
    done

    # Show connection information
    echo ""
    log_info "GraphQL API Endpoints:"
    
    for service in "${services_to_start[@]}"; do
        case "$service" in
            admin-graphql-server)
                log_detail "Admin GraphQL: http://localhost:8101/v1/graphql"
                log_detail "Admin Console: http://localhost:8101/console"
                ;;
            operator-graphql-server)
                log_detail "Operator GraphQL: http://localhost:8102/v1/graphql"
                log_detail "Operator Console: http://localhost:8102/console"
                ;;
            member-graphql-server)
                log_detail "Member GraphQL: http://localhost:8103/v1/graphql"
                log_detail "Member Console: http://localhost:8103/console"
                ;;
        esac
    done

    # Show status
    echo ""
    log_progress "Current container status:"
    docker-compose ps

    # Performance summary
    print_operation_summary "Docker Start" "$TIER" "development"
}

# Set trap for error handling
trap 'log_error "Script failed on line $LINENO"' ERR

# Run main function
main
