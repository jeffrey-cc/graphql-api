#!/bin/bash

# ============================================================================
# SHARED GRAPHQL REBUILD ALL TIERS
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Complete rebuild for all tiers (admin, operator, member)
# Development: Docker rebuild + relationship tracking
# Production: Fast refresh + relationship tracking (no Docker)
# Usage: ./rebuild-all.sh <environment> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Rebuild All Tiers Command

DESCRIPTION:
    Complete rebuild for all three tiers (admin, operator, member).
    
    DEVELOPMENT MODE:
    - Destroys and recreates ALL Docker containers and volumes
    - Rebuilds GraphQL servers from scratch
    - Tracks all database tables, views, enums, and functions
    - Tracks ALL foreign key relationships automatically
    - Verifies relationships are working
    
    PRODUCTION MODE:
    - Performs fast refresh (cannot rebuild Docker in production)
    - Reloads metadata and tracks relationships
    - Much faster since no Docker containers are involved

USAGE:
    ./rebuild-all.sh <environment> [options]

ARGUMENTS:
    environment    Either 'production' or 'development'

OPTIONS:
    -h, --help     Show this help message
    -f, --force    Skip confirmation prompts
    --sequential   Run tiers sequentially instead of parallel

EXAMPLES:
    ./rebuild-all.sh development          # Rebuild all dev Docker containers
    ./rebuild-all.sh production --force   # Force refresh all production
    ./rebuild-all.sh development --sequential  # Rebuild sequentially

NOTES:
    - Development: DESTRUCTIVE - destroys all containers and volumes
    - Production: Safe refresh operation (no Docker destruction)
    - All operations include complete relationship tracking
    - Parallel execution by default for speed
    - Total time: ~2-3 minutes for development, ~30 seconds for production
EOF
}

# Parse command line arguments
ENVIRONMENT=""
FORCE_FLAG=""
SEQUENTIAL_FLAG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            FORCE_FLAG="--force"
            shift
            ;;
        --sequential)
            SEQUENTIAL_FLAG="true"
            shift
            ;;
        *)
            if [[ -z "$ENVIRONMENT" ]]; then
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
if [[ -z "$ENVIRONMENT" ]]; then
    log_error "Environment argument is required"
    show_help
    exit 1
fi

validate_environment "$ENVIRONMENT"

# Show appropriate warnings
if [[ "$ENVIRONMENT" == "development" && -z "$FORCE_FLAG" ]]; then
    echo -e "${RED}⚠️  DESTRUCTIVE OPERATION WARNING${NC}"
    echo -e "${YELLOW}You are about to DESTROY and REBUILD ALL development Docker containers:${NC}"
    echo -e "${YELLOW}  - Admin GraphQL Docker container (admin-graphql-server)${NC}"
    echo -e "${YELLOW}  - Operator GraphQL Docker container (operator-graphql-server)${NC}"
    echo -e "${YELLOW}  - Member GraphQL Docker container (member-graphql-server)${NC}"
    echo ""
    echo -e "${YELLOW}This will:${NC}"
    echo -e "${YELLOW}  - Delete ALL containers and volumes${NC}"
    echo -e "${YELLOW}  - Destroy ALL GraphQL metadata and settings${NC}"
    echo -e "${YELLOW}  - Recreate everything from scratch${NC}"
    echo -e "${YELLOW}  - Take approximately 2-3 minutes${NC}"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi
elif [[ "$ENVIRONMENT" == "production" && -z "$FORCE_FLAG" ]]; then
    echo -e "${YELLOW}⚠️  PRODUCTION REFRESH WARNING${NC}"
    echo -e "${YELLOW}You are about to refresh ALL production GraphQL APIs:${NC}"
    echo -e "${YELLOW}  - Admin GraphQL API (franchisor operations)${NC}"
    echo -e "${YELLOW}  - Operator GraphQL API (facility management)${NC}"
    echo -e "${YELLOW}  - Member GraphQL API (member operations)${NC}"
    echo ""
    echo -e "${YELLOW}Note: Production rebuild = refresh (no Docker destruction)${NC}"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi
fi

# Determine operation type
if [[ "$ENVIRONMENT" == "development" ]]; then
    OPERATION="Docker Rebuild"
    OPERATION_SCRIPT="rebuild-docker.sh"
else
    OPERATION="Fast Refresh"
    OPERATION_SCRIPT="fast-refresh.sh"
    log_info "Production rebuild = fast refresh (no Docker containers)"
fi

# Header
section_header "🔨 SHARED GRAPHQL REBUILD ALL TIERS - $(echo $ENVIRONMENT | tr '[:lower:]' '[:upper:]')"
log_info "Environment: $ENVIRONMENT"
log_info "Operation: $OPERATION"
log_info "Mode: $([ "$SEQUENTIAL_FLAG" == "true" ] && echo "Sequential" || echo "Parallel")"
log_info "Start Time: $(date '+%Y-%m-%d %H:%M:%S')"

# Start timing
start_timer

# Define tiers
TIERS=("admin" "operator" "member")

# Function to rebuild a single tier
rebuild_tier() {
    local tier="$1"
    local logfile="/tmp/rebuild_${tier}_$$.log"
    
    echo -e "${CYAN}🔨 Starting $OPERATION for $tier tier...${NC}"
    
    if "$SCRIPT_DIR/$OPERATION_SCRIPT" "$tier" "$ENVIRONMENT" $FORCE_FLAG 2>&1 | tee "$logfile"; then
        echo -e "${GREEN}✅ $tier tier $OPERATION completed successfully${NC}"
        rm -f "$logfile"
        return 0
    else
        echo -e "${RED}❌ $tier tier $OPERATION failed - check logs${NC}"
        echo "Log file saved at: $logfile"
        return 1
    fi
}

# Track success/failure counts
declare -A tier_results
total_tiers=${#TIERS[@]}
success_count=0
failure_count=0

if [[ "$SEQUENTIAL_FLAG" == "true" ]]; then
    # Sequential execution (useful for debugging)
    echo -e "${INFO}Running tiers sequentially for debugging...${NC}"
    
    for tier in "${TIERS[@]}"; do
        if rebuild_tier "$tier"; then
            tier_results["$tier"]="SUCCESS"
            ((success_count++))
        else
            tier_results["$tier"]="FAILED"
            ((failure_count++))
        fi
    done
else
    # Parallel execution (default for speed)
    echo -e "${INFO}Running all tiers in parallel for maximum speed...${NC}"
    
    # Start all rebuild processes in background
    declare -A tier_pids
    
    for tier in "${TIERS[@]}"; do
        rebuild_tier "$tier" &
        tier_pids["$tier"]=$!
    done
    
    # Wait for all processes and collect results
    for tier in "${TIERS[@]}"; do
        if wait "${tier_pids[$tier]}"; then
            tier_results["$tier"]="SUCCESS"
            ((success_count++))
        else
            tier_results["$tier"]="FAILED"
            ((failure_count++))
        fi
    done
fi

# Verify all GraphQL APIs are responding
echo -e "${PROGRESS}Verifying all GraphQL APIs are responding...${NC}"

verification_success=0
relationship_count_total=0

for tier in "${TIERS[@]}"; do
    configure_tier "$tier"
    configure_endpoint "$tier" "$ENVIRONMENT"
    
    if test_graphql_connection "$tier" "$ENVIRONMENT" 2>/dev/null; then
        echo -e "${SUCCESS}✅ $tier GraphQL API responding${NC}"
        ((verification_success++))
        
        # Check relationship count
        local rel_count=$(curl -s -X POST -H "Content-Type: application/json" -H "X-Hasura-Admin-Secret: $GRAPHQL_TIER_ADMIN_SECRET" \
            -d '{"query": "query { __schema { types { name fields { name type { name kind ofType { name } } } } } }"}' \
            "$GRAPHQL_TIER_ENDPOINT/v1/graphql" | \
            jq '[.data.__schema.types[] | select(.name | test("^(admin|operators|compliance|financial|sales|support|system|integration)_")) | .fields[] | select(.type.kind == "OBJECT" or (.type.kind == "LIST" and .type.ofType.name != null and (.type.ofType.name | test("^(admin|operators|compliance|financial|sales|support|system|integration)_"))))] | length' 2>/dev/null || echo "0")
        
        echo -e "${INFO}  $tier relationships: $rel_count${NC}"
        relationship_count_total=$((relationship_count_total + rel_count))
    else
        echo -e "${ERROR}❌ $tier GraphQL API not responding${NC}"
        tier_results["$tier"]="FAILED"
    fi
done

# Final summary
echo ""
section_header "🎯 REBUILD ALL TIERS SUMMARY"
log_info "Environment: $ENVIRONMENT"
log_info "Operation: $OPERATION"
log_info "Total Tiers: $total_tiers"
log_info "Successful: $success_count"
log_info "Failed: $failure_count"
log_info "APIs Responding: $verification_success"
log_info "Total Relationships: $relationship_count_total"

echo ""
echo -e "${BOLD}Individual Tier Results:${NC}"
for tier in "${TIERS[@]}"; do
    result="${tier_results[$tier]}"
    if [[ "$result" == "SUCCESS" ]]; then
        echo -e "  ${GREEN}✅ $tier: $result${NC}"
    else
        echo -e "  ${RED}❌ $tier: $result${NC}"
    fi
done

# Relationship verification
echo ""
if [[ $relationship_count_total -gt 100 ]]; then
    echo -e "${GREEN}🔗 RELATIONSHIPS VERIFIED: $relationship_count_total total relationship fields${NC}"
    echo -e "${GREEN}   GraphQL nested queries are ready across all tiers!${NC}"
elif [[ $relationship_count_total -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  PARTIAL RELATIONSHIPS: $relationship_count_total relationship fields${NC}"
    echo -e "${YELLOW}   Some relationships may be missing. Manual verification recommended.${NC}"
else
    echo -e "${RED}❌ NO RELATIONSHIPS DETECTED${NC}"
    echo -e "${RED}   GraphQL nested queries will not work. Manual relationship tracking needed.${NC}"
fi

# Overall result
echo ""
if [[ $failure_count -eq 0 && $verification_success -eq $total_tiers && $relationship_count_total -gt 50 ]]; then
    log_success "🎉 ALL TIERS REBUILT SUCCESSFULLY WITH RELATIONSHIPS!"
    log_info "All GraphQL APIs are ready for nested queries"
    exit_code=0
else
    log_error "⚠️  REBUILD COMPLETED WITH ISSUES"
    log_info "Check individual tier logs and relationship counts"
    exit_code=1
fi

# Performance summary
end_timer
echo ""
log_info "GraphQL Consoles:"
log_info "  Admin: http://localhost:8101/console"
log_info "  Operator: http://localhost:8102/console"
log_info "  Member: http://localhost:8103/console"

exit $exit_code