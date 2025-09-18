#!/bin/bash

# ================================================================================
# Docker Delete Command - Remove GraphQL Container(s) and Volumes
# ================================================================================
# Removes one or more GraphQL containers and their associated volumes
# Usage: ./docker-delete.sh [tier...] (admin, operator, member, or all)
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
Shared GraphQL API - Docker Delete Command

DESCRIPTION:
    Remove GraphQL Docker container(s) and volumes for specified tier(s) using unified docker-compose stack.

USAGE:
    ./docker-delete.sh [tier...] (admin, operator, member, or all)

ARGUMENTS:
    tier              GraphQL tier(s) to delete:
                      - admin: Delete admin GraphQL container and volume
                      - operator: Delete operator GraphQL container and volume
                      - member: Delete member GraphQL container and volume
                      - all: Delete all GraphQL containers and volumes
                      Multiple tiers can be specified

DESCRIPTION:
    This command will:
    • Stop the container(s) if running
    • Remove the container(s)
    • Remove associated Docker volumes
    • Permanently delete all GraphQL metadata

EXAMPLES:
    Delete admin GraphQL container and volume:
    ./docker-delete.sh admin

    Delete multiple containers and volumes:
    ./docker-delete.sh admin operator

    Delete all GraphQL containers and volumes:
    ./docker-delete.sh all

WARNING:
    This operation will permanently delete ALL GraphQL metadata and configuration!
    The containers and volumes cannot be recovered after deletion.

NOTES:
    - Uses unified docker-compose.yml stack
    - Permanently destroys all GraphQL metadata
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
    section_header "Deleting GraphQL Docker Container(s) and Volumes"

    # Check if docker-compose.yml exists
    if [[ ! -f "$PARENT_DIR/docker-compose.yml" ]]; then
        log_error "docker-compose.yml not found in $PARENT_DIR"
        exit 1
    fi

    # Change to parent directory for docker-compose
    cd "$PARENT_DIR"

    local services_to_delete=()
    local volumes_to_delete=()

    # Process tier arguments
    for tier in "${TIERS[@]}"; do
        case "$tier" in
            admin)
                services_to_delete+=("admin-graphql-server")
                volumes_to_delete+=("shared-graphql-api_admin_graphql_metadata")
                ;;
            operator)
                services_to_delete+=("operator-graphql-server")
                volumes_to_delete+=("shared-graphql-api_operator_graphql_metadata")
                ;;
            member)
                services_to_delete+=("member-graphql-server")
                volumes_to_delete+=("shared-graphql-api_member_graphql_metadata")
                ;;
            all)
                services_to_delete=("admin-graphql-server" "operator-graphql-server" "member-graphql-server")
                volumes_to_delete=("shared-graphql-api_admin_graphql_metadata" "shared-graphql-api_operator_graphql_metadata" "shared-graphql-api_member_graphql_metadata")
                break
                ;;
            *)
                log_error "Invalid tier: $tier (must be admin, operator, member, or all)"
                exit 1
                ;;
        esac
    done

    log_warning "About to delete containers and volumes: ${services_to_delete[*]}"
    log_warning "This will permanently delete all GraphQL metadata and configuration!"

    # Stop and remove containers using docker-compose
    log_progress "Stopping and removing containers: ${services_to_delete[*]}"

    if docker-compose rm -s -f -v "${services_to_delete[@]}"; then
        log_success "Successfully removed container(s)"
    else
        log_warning "Some containers may not have existed or failed to remove"
    fi

    # Remove volumes
    log_progress "Removing volumes: ${volumes_to_delete[*]}"

    for volume in "${volumes_to_delete[@]}"; do
        if docker volume ls --format '{{.Name}}' | grep -q "^${volume}$"; then
            if docker volume rm "${volume}"; then
                log_success "Removed volume: ${volume}"
            else
                log_warning "Failed to remove volume: ${volume}"
            fi
        else
            log_info "Volume ${volume} does not exist"
        fi
    done

    # Show remaining containers
    log_progress "Remaining container status:"
    docker-compose ps

    log_success "Delete operation completed"
    print_operation_summary "Docker Delete" "${TIERS[*]}" "development"
}

# Set trap for error handling
trap 'log_error "Script failed on line $LINENO"' ERR

# Run main function
main