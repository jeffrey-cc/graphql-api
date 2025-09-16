#!/bin/bash

# ============================================================================
# SHARED GRAPHQL DROP COMMAND
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Removes GraphQL API metadata and optionally stops services
# Usage: ./drop-graphql.sh <tier> [environment] [-h|--help]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
SHARED GRAPHQL DROP COMMAND
Community Connect Tech - Shared GraphQL API System

DESCRIPTION:
    Removes GraphQL API metadata and optionally stops services for specified tier.
    This command will:
    - Clear all tracked tables and relationships
    - Reset metadata to clean state
    - Stop Docker services (development only)
    - Clean up configurations

USAGE:
    ./drop-graphql.sh <tier> [environment] [options]

ARGUMENTS:
    tier           admin, operator, or member
    environment    production or development (default: development)

OPTIONS:
    -h, --help    Show this help message
    --force       Skip confirmation prompts

EXAMPLES:
    ./drop-graphql.sh admin development     # Clean local admin environment
    ./drop-graphql.sh operator production   # Clear production operator metadata
    ./drop-graphql.sh member development    # Clean local member environment

NOTES:
    - This will remove all GraphQL configurations
    - Database tables remain unchanged
    - Use deploy-graphql.sh to restore
EOF
}

# Check for help flag
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]] || [[ -z "$1" ]]; then
    show_help
    exit 0
fi

# Parse arguments
TIER="$1"
ENVIRONMENT="${2:-development}"
FORCE_FLAG=""

# Check for force flag
for arg in "$@"; do
    if [[ "$arg" == "--force" ]]; then
        FORCE_FLAG="true"
    fi
done

# Validate tier
if [[ "$TIER" != "admin" && "$TIER" != "operator" && "$TIER" != "member" ]]; then
    log_error "Invalid tier: $TIER. Must be admin, operator, or member"
    show_help
    exit 1
fi

# Validate environment
if [[ "$ENVIRONMENT" != "production" && "$ENVIRONMENT" != "development" ]]; then
    log_error "Invalid environment: $ENVIRONMENT. Must be production or development"
    show_help
    exit 1
fi

# Configure tier
configure_tier "$TIER"
if [ $? -ne 0 ]; then
    exit 1
fi

# Start timer
start_timer

# Print header
print_header "SHARED GRAPHQL DROP - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Environment: $ENVIRONMENT"
log_info "Container: $GRAPHQL_TIER_CONTAINER"
echo ""

# Production confirmation
if [ "$ENVIRONMENT" == "production" ] && [ "$FORCE_FLAG" != "true" ]; then
    log_warning "This will clear all GraphQL metadata in PRODUCTION for $TIER!"
    echo -n "Are you sure you want to continue? (yes/no): "
    read -r confirmation
    if [ "$confirmation" != "yes" ]; then
        log_error "Operation cancelled"
        exit 0
    fi
fi

# Load environment configuration
load_environment "$TIER" "$ENVIRONMENT"
if [ $? -ne 0 ]; then
    exit 1
fi

# Function to check if Hasura is running
check_hasura() {
    if curl -s -f -o /dev/null "${GRAPHQL_ENDPOINT}/healthz" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Check if Hasura is accessible
if check_hasura; then
    log_step "Clearing GraphQL metadata..."
    
    # Export clean metadata (minimal configuration)
    CLEAN_METADATA=$(cat << EOF
{
  "version": 3,
  "sources": [
    {
      "name": "${TIER}_database",
      "kind": "postgres",
      "tables": [],
      "configuration": {
        "connection_info": {
          "database_url": {
            "from_env": "HASURA_GRAPHQL_DATABASE_URL"
          },
          "isolation_level": "read-committed",
          "pool_settings": {
            "connection_lifetime": 600,
            "idle_timeout": 180,
            "max_connections": 50,
            "retries": 1
          },
          "use_prepared_statements": true
        }
      }
    }
  ]
}
EOF
)
    
    # Clear metadata via API
    echo "$CLEAN_METADATA" | curl -s -X POST "${GRAPHQL_ENDPOINT}/v1/metadata" \
        -H "Content-Type: application/json" \
        -H "x-hasura-admin-secret: $GRAPHQL_TIER_ADMIN_SECRET" \
        -d @- > /dev/null
    
    if [ $? -eq 0 ]; then
        log_success "GraphQL metadata cleared"
    else
        log_error "Failed to clear metadata"
        ((COMMAND_ERRORS++))
    fi
else
    log_warning "Hasura is not accessible at $GRAPHQL_ENDPOINT"
    if [ "$ENVIRONMENT" == "development" ]; then
        log_info "Proceeding to stop services..."
    fi
fi

# Development-specific cleanup
if [ "$ENVIRONMENT" == "development" ]; then
    echo ""
    log_step "Stopping Docker services..."
    
    # Change to tier repository directory for docker-compose
    cd "$TIER_REPOSITORY_PATH"
    
    # Stop Docker services
    if docker-compose down 2>/dev/null; then
        log_success "Docker services stopped"
    else
        log_warning "Docker services may not be running"
    fi
    
    # Optional: Clean up volumes
    if [ "$FORCE_FLAG" != "true" ]; then
        echo ""
        echo -n "Do you want to remove Docker volumes? (y/n): "
        read -r remove_volumes
        if [[ "$remove_volumes" == "y" ]] || [[ "$remove_volumes" == "Y" ]]; then
            docker-compose down -v 2>/dev/null
            log_success "Docker volumes removed"
        fi
    fi
fi

# Print summary
print_summary

# Final status
echo ""
if [ $COMMAND_ERRORS -eq 0 ]; then
    log_success "$(echo $TIER | tr '[:lower:]' '[:upper:]') GraphQL API cleanup complete!"
    log_info "To redeploy, run: ./deploy-graphql.sh $TIER $ENVIRONMENT"
else
    log_error "Cleanup completed with $COMMAND_ERRORS error(s)"
fi

exit $COMMAND_ERRORS