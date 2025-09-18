#!/bin/bash

# ================================================================================
# Docker Stop Command - Stop GraphQL Container(s) Using Docker Compose
# ================================================================================
# Stops one or more GraphQL containers managed by docker-compose
# Usage: ./docker-stop.sh [tier...] (admin, operator, member, or all)
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
Shared GraphQL API - Docker Stop Command

DESCRIPTION:
    Stop GraphQL Docker container(s) for specified tier(s) using unified docker-compose stack.

USAGE:
    ./docker-stop.sh [tier...] (admin, operator, member, or all)

ARGUMENTS:
    tier              GraphQL tier(s) to stop:
                      - admin: Stop admin GraphQL container
                      - operator: Stop operator GraphQL container
                      - member: Stop member GraphQL container
                      - all: Stop all GraphQL containers
                      Multiple tiers can be specified

EXAMPLES:
    Stop admin GraphQL container:
    ./docker-stop.sh admin

    Stop multiple containers:
    ./docker-stop.sh admin operator

    Stop all GraphQL containers:
    ./docker-stop.sh all

NOTES:
    - Uses unified docker-compose.yml stack
    - Gracefully stops containers without removing them
    - Part of shared GraphQL API management system
EOF
}

# ================================================================================
# Parse Arguments
# ================================================================================

if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    if [[ $# -eq 0 ]]; then
        log_error "At least one tier argument is required"
    fi
    show_help
    exit 0
fi

# Collect all tier arguments
TIERS=("$@")

# ================================================================================
# Main Logic
# ================================================================================

main() {
    section_header "Stopping GraphQL Docker Container(s)"

    # Check if docker-compose.yml exists
    if [[ ! -f "$PARENT_DIR/docker-compose.yml" ]]; then
        log_error "docker-compose.yml not found in $PARENT_DIR"
        exit 1
    fi

    # Change to parent directory for docker-compose
    cd "$PARENT_DIR"

    local services_to_stop=()

    # Process tier arguments
    for tier in "${TIERS[@]}"; do
        case "$tier" in
            admin)
                services_to_stop+=("admin-graphql-server")
                ;;
            operator)
                services_to_stop+=("operator-graphql-server")
                ;;
            member)
                services_to_stop+=("member-graphql-server")
                ;;
            all)
                services_to_stop=("admin-graphql-server" "operator-graphql-server" "member-graphql-server")
                break
                ;;
            *)
                log_error "Invalid tier: $tier (must be admin, operator, member, or all)"
                exit 1
                ;;
        esac
    done

    # Stop the containers
    log_progress "Stopping containers: ${services_to_stop[*]}"

    if docker-compose stop "${services_to_stop[@]}"; then
        log_success "Successfully stopped container(s)"
    else
        log_error "Failed to stop container(s)"
        exit 1
    fi

    # Show status
    log_progress "Current container status:"
    docker-compose ps

    print_operation_summary "Docker Stop" "${TIERS[*]}" "development"
}

# Set trap for error handling
trap 'log_error "Script failed on line $LINENO"' ERR

# Run main function
main
