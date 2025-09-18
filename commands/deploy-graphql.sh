#!/bin/bash

# ============================================================================
# SHARED GRAPHQL DEPLOYMENT
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Deploys GraphQL service with introspection and relationship tracking
# Usage: ./deploy-graphql.sh <tier> <environment> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Deploy Command

DESCRIPTION:
    Deploys the Hasura GraphQL API with automatic database introspection.
    This command will:
    - Configure tier-specific settings (admin/operator/member)
    - Start Docker services (development only)
    - Apply metadata configuration
    - Reload metadata to introspect database tables
    - Track all tables and relationships
    - Validate the deployment

USAGE:
    ./deploy-graphql.sh <tier> <environment> [options]

ARGUMENTS:
    tier           One of: admin, operator, member
    environment    Either 'production' or 'development' (default: development)

OPTIONS:
    -h, --help     Show this help message
    -q, --quiet    Suppress verbose output
    --no-track     Skip automatic table and relationship tracking

EXAMPLES:
    ./deploy-graphql.sh member development     # Deploy member API to local Docker
    ./deploy-graphql.sh admin production       # Deploy admin API to Hasura Cloud
    ./deploy-graphql.sh operator development --no-track  # Deploy without tracking

NOTES:
    - Development deployment uses Docker Compose
    - Production deployment requires Hasura Cloud credentials
    - All database tables are automatically discovered via introspection
    - Relationships are automatically tracked from foreign keys
EOF
}

# Parse command line arguments
TIER=""
ENVIRONMENT="development"
QUIET=false
NO_TRACK=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        --no-track)
            NO_TRACK=true
            shift
            ;;
        *)
            if [[ -z "$TIER" ]]; then
                TIER="$1"
            elif [[ -z "$ENVIRONMENT" || "$ENVIRONMENT" == "development" ]]; then
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
if [[ -z "$TIER" ]]; then
    log_error "Tier argument is required"
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

# Configure endpoint based on environment
if ! configure_endpoint "$TIER" "$ENVIRONMENT"; then
    die "Failed to configure endpoint for $TIER $ENVIRONMENT"
fi

section_header "🚀 SHARED GRAPHQL DEPLOYMENT - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "GraphQL Port: $GRAPHQL_TIER_PORT"
log_info "GraphQL Endpoint: $GRAPHQL_TIER_ENDPOINT"
log_info "Database: $DB_TIER_DATABASE at localhost:$DB_TIER_PORT"
log_info "Start Time: $(date '+%Y-%m-%d %H:%M:%S')"

# Start timing
start_timer

# Development-specific Docker management
if [[ "$ENVIRONMENT" == "development" ]]; then
    log_progress "Starting Docker services for $TIER..."
    
    # Change to tier repository for docker-compose
    # Change to shared GraphQL API directory for unified docker-compose
    cd "$SCRIPT_DIR/.."
    
    # Determine service name based on tier
    case "$TIER" in
        admin)
            SERVICE_NAME="admin-graphql-server"
            ;;
        operator)
            SERVICE_NAME="operator-graphql-server"
            ;;
        member)
            SERVICE_NAME="member-graphql-server"
            ;;
        *)
            die "Invalid tier: $TIER"
            ;;
    esac
    
    # Start services using unified docker-compose
    if ! docker-compose up -d "$SERVICE_NAME"; then
        die "Failed to start Docker service: $SERVICE_NAME"
    fi
    
    # Wait for GraphQL service
    if ! wait_for_graphql_service "$TIER"; then
        die "GraphQL service failed to start"
    fi
    
    # Return to shared directory
    cd "$SCRIPT_DIR/.."
fi

# Test connectivity
log_progress "Testing connectivity..."
if ! test_graphql_connection "$TIER" "$ENVIRONMENT"; then
    die "Failed to connect to GraphQL service"
fi

# Reload metadata to pick up database changes
log_progress "Reloading metadata..."
if ! reload_metadata "$TIER" "$ENVIRONMENT"; then
    die "Failed to reload metadata"
fi

# Track tables and relationships (unless disabled)
if [[ "$NO_TRACK" != "true" ]]; then
    log_progress "Tracking database tables..."
    if ! track_all_tables "$TIER" "$ENVIRONMENT"; then
        log_warning "Some tables failed to track"
    fi
    
    log_progress "Tracking relationships..."
    if ! track_relationships "$TIER" "$ENVIRONMENT"; then
        log_warning "Some relationships failed to track"
    fi
fi

# Final validation
log_progress "Validating deployment..."
if ! test_graphql_connection "$TIER" "$ENVIRONMENT"; then
    die "Deployment validation failed"
fi

# Success summary
print_operation_summary "GraphQL Deployment" "$TIER" "$ENVIRONMENT"

if [[ "$QUIET" != "true" ]]; then
    echo ""
    log_success "GraphQL API deployed successfully!"
    log_info "Endpoint: http://localhost:$GRAPHQL_TIER_PORT"
    log_info "GraphQL Console: http://localhost:$GRAPHQL_TIER_PORT/console"
    log_info "Admin Secret: $GRAPHQL_TIER_ADMIN_SECRET"
fi
# Return success exit code
exit 0
