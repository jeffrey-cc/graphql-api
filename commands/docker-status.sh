#!/bin/bash

# ================================================================================
# Docker Status Command - Show GraphQL Container Status Using Docker Compose
# ================================================================================
# Shows status of GraphQL containers managed by docker-compose
# Usage: ./docker-status.sh [tier...] (admin, operator, member, or all)
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
Shared GraphQL API - Docker Status Command

DESCRIPTION:
    Show status of GraphQL Docker container(s) for specified tier(s) using unified docker-compose stack.

USAGE:
    ./docker-status.sh [tier...] (admin, operator, member, or all)

ARGUMENTS:
    tier              GraphQL tier(s) to check (optional):
                      - admin: Show admin GraphQL container status
                      - operator: Show operator GraphQL container status
                      - member: Show member GraphQL container status
                      - all: Show all GraphQL container status
                      - (no args): Show all containers status

EXAMPLES:
    Show admin GraphQL container status:
    ./docker-status.sh admin

    Show multiple container status:
    ./docker-status.sh admin operator

    Show all GraphQL container status:
    ./docker-status.sh all
    ./docker-status.sh

NOTES:
    - Uses unified docker-compose.yml stack
    - Shows detailed container information including health status
    - Part of shared GraphQL API management system
EOF
}

# ================================================================================
# Parse Arguments
# ================================================================================

if [[ "$#" -gt 0 ]] && ([[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]); then
    show_help
    exit 0
fi

# If no arguments provided, default to "all"
if [[ $# -eq 0 ]]; then
    TIERS=("all")
else
    TIERS=("$@")
fi

# ================================================================================
# Main Logic
# ================================================================================

main() {
    section_header "GraphQL Docker Container Status"

    # Check if docker-compose.yml exists
    if [[ ! -f "$PARENT_DIR/docker-compose.yml" ]]; then
        log_error "docker-compose.yml not found in $PARENT_DIR"
        exit 1
    fi

    # Change to parent directory for docker-compose
    cd "$PARENT_DIR"

    local services_to_check=()

    # Process tier arguments
    for tier in "${TIERS[@]}"; do
        case "$tier" in
            admin)
                services_to_check+=(admin-graphql-server)
                ;;
            operator)
                services_to_check+=(operator-graphql-server)
                ;;
            member)
                services_to_check+=(member-graphql-server)
                ;;
            all)
                services_to_check=(admin-graphql-server operator-graphql-server member-graphql-server)
                break
                ;;
            *)
                log_error "Invalid tier: $tier (must be admin, operator, member, or all)"
                exit 1
                ;;
        esac
    done

    # Show general docker-compose status
    log_progress "Docker Compose Stack Status:"
    if docker-compose ps; then
        echo ""
    else
        log_warning "Failed to get docker-compose status"
    fi

    # Show detailed status for specific services
    if [[ ${#services_to_check[@]} -gt 0 ]]; then
        log_progress "Detailed Service Status:"
        
        for service in "${services_to_check[@]}"; do
            echo ""
            log_info "=== $service ==="
            
            # Check if container exists
            if docker-compose ps -q "$service" >/dev/null 2>&1; then
                # Get container status
                local status=$(docker-compose ps "$service" 2>/dev/null | tail -n +3 | awk '{print $4}' || echo "unknown")
                local container_id=$(docker-compose ps -q "$service" 2>/dev/null || echo "")
                
                if [[ -n "$container_id" ]]; then
                    # Service is defined and may be running
                    if docker inspect "$container_id" >/dev/null 2>&1; then
                        local running=$(docker inspect -f '{{.State.Running}}' "$container_id" 2>/dev/null || echo "false")
                        local health=$(docker inspect -f '{{.State.Health.Status}}' "$container_id" 2>/dev/null || echo "no_health_check")
                        local created=$(docker inspect -f '{{.Created}}' "$container_id" 2>/dev/null || echo "unknown")
                        local image=$(docker inspect -f '{{.Config.Image}}' "$container_id" 2>/dev/null || echo "unknown")
                        
                        if [[ "$running" == "true" ]]; then
                            log_success "Status: Running"
                        else
                            log_warning "Status: Stopped"
                        fi
                        
                        case "$health" in
                            healthy)
                                log_success "Health: Healthy"
                                ;;
                            unhealthy)
                                log_error "Health: Unhealthy"
                                ;;
                            starting)
                                log_warning "Health: Starting"
                                ;;
                            no_health_check)
                                log_info "Health: No health check configured"
                                ;;
                            *)
                                log_info "Health: $health"
                                ;;
                        esac
                        
                        log_detail "Image: $image"
                        log_detail "Created: $created"
                        
                        # Show port mappings
                        local ports=$(docker port "$container_id" 2>/dev/null || echo "")
                        if [[ -n "$ports" ]]; then
                            log_detail "Ports: $ports"
                        fi
                        
                        # Show recent logs (last 5 lines)
                        log_info "Recent logs:"
                        docker logs --tail 5 "$container_id" 2>/dev/null | sed 's/^/    /' || log_warning "Could not retrieve logs"
                        
                    else
                        log_error "Container exists in compose but not in Docker"
                    fi
                else
                    log_warning "$service: Not running"
                fi
            else
                log_error "$service: Service not found in docker-compose"
            fi
        done
    fi

    # Show resource usage
    echo ""
    log_progress "Resource Usage:"
    if command -v docker >/dev/null 2>&1; then
        if docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null | grep -E "(admin-graphql|operator-graphql|member-graphql)" || true; then
            echo ""
        else
            log_info "No GraphQL containers currently consuming resources"
        fi
    else
        log_warning "Docker command not available for resource monitoring"
    fi

    # Show network information
    echo ""
    log_progress "Network Information:"
    if docker network ls | grep -q "shared_graphql_network"; then
        log_success "shared_graphql_network: Available"
        
        # Show connected containers
        local connected=$(docker network inspect shared_graphql_network --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || echo "")
        if [[ -n "$connected" ]]; then
            log_detail "Connected containers: $connected"
        fi
    else
        log_warning "shared_graphql_network: Not found"
    fi

    # Summary
    echo ""
    print_operation_summary "Docker Status" "${TIERS[*]}" "development"
}

# Set trap for error handling
trap 'log_error "Script failed on line $LINENO"' ERR

# Run main function
main
