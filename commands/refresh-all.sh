#!/bin/bash

# ============================================================================
# SHARED GRAPHQL REFRESH ALL TIERS
# Community Connect Tech - Shared GraphQL API System
# ============================================================================
# Fast refresh for all tiers (admin, operator, member) in parallel
# Usage: ./refresh-all.sh <environment> [options]
# ============================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Show help information
show_help() {
    cat << EOF
Shared GraphQL API - Refresh All Tiers Command

DESCRIPTION:
    Fast refresh for all three tiers (admin, operator, member) in parallel.
    This command:
    - Refreshes metadata for all GraphQL APIs
    - Tracks all database tables, views, enums, and functions
    - Tracks ALL foreign key relationships automatically
    - Verifies relationships are working
    - Runs all operations in parallel for maximum speed

USAGE:
    ./refresh-all.sh <environment> [options]

ARGUMENTS:
    environment    Either 'production' or 'development'

OPTIONS:
    -h, --help     Show this help message
    -f, --force    Skip confirmation prompts for production
    --sequential   Run tiers sequentially instead of parallel

EXAMPLES:
    ./refresh-all.sh development          # Refresh all dev environments in parallel
    ./refresh-all.sh production --force   # Force refresh all production (use carefully!)
    ./refresh-all.sh development --sequential  # Refresh sequentially for debugging

NOTES:
    - All tiers run in parallel by default for speed
    - Each tier refresh includes complete relationship tracking
    - If any tier fails, the command will report errors but continue with others
    - Total execution time is typically the slowest individual tier (not cumulative)
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

# Production confirmation
if [[ "$ENVIRONMENT" == "production" && -z "$FORCE_FLAG" ]]; then
    echo -e "${YELLOW}⚠️  WARNING: You are about to refresh ALL production GraphQL APIs${NC}"
    echo -e "${YELLOW}This will reload metadata and track relationships for:${NC}"
    echo -e "${YELLOW}  - Admin GraphQL API (franchisor operations)${NC}"
    echo -e "${YELLOW}  - Operator GraphQL API (facility management)${NC}"
    echo -e "${YELLOW}  - Member GraphQL API (member operations)${NC}"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi
fi

# Header
section_header "🔄 SHARED GRAPHQL REFRESH ALL TIERS - $(echo $ENVIRONMENT | tr '[:lower:]' '[:upper:]')"
log_info "Environment: $ENVIRONMENT"
log_info "Mode: $([ "$SEQUENTIAL_FLAG" == "true" ] && echo "Sequential" || echo "Parallel")"
log_info "Start Time: $(date '+%Y-%m-%d %H:%M:%S')"

# Start timing
start_timer

# Define tiers
TIERS=("admin" "operator" "member")

# Function to refresh a single tier
refresh_tier() {
    local tier="$1"
    local logfile="/tmp/refresh_${tier}_$$.log"
    
    echo -e "${CYAN}🔄 Starting refresh for $tier tier...${NC}"
    
    if "$SCRIPT_DIR/fast-refresh.sh" "$tier" "$ENVIRONMENT" 2>&1 | tee "$logfile"; then
        echo -e "${GREEN}✅ $tier tier refresh completed successfully${NC}"
        rm -f "$logfile"
        return 0
    else
        echo -e "${RED}❌ $tier tier refresh failed - check logs${NC}"
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
    # Sequential execution
    echo -e "${INFO}Running tiers sequentially for debugging...${NC}"
    
    for tier in "${TIERS[@]}"; do
        if refresh_tier "$tier"; then
            tier_results["$tier"]="SUCCESS"
            ((success_count++))
        else
            tier_results["$tier"]="FAILED"
            ((failure_count++))
        fi
    done
else
    # Parallel execution
    echo -e "${INFO}Running all tiers in parallel for maximum speed...${NC}"
    
    # Start all refresh processes in background
    declare -A tier_pids
    
    for tier in "${TIERS[@]}"; do
        refresh_tier "$tier" &
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
echo -e "${PROGRESS}Verifying all GraphQL APIs...${NC}"

verification_success=0
for tier in "${TIERS[@]}"; do
    configure_tier "$tier"
    configure_endpoint "$tier" "$ENVIRONMENT"
    
    if test_graphql_connection "$tier" "$ENVIRONMENT" 2>/dev/null; then
        echo -e "${SUCCESS}✅ $tier GraphQL API responding${NC}"
        ((verification_success++))
    else
        echo -e "${ERROR}❌ $tier GraphQL API not responding${NC}"
        tier_results["$tier"]="FAILED"
    fi
done

# Final summary
echo ""
section_header "🎯 REFRESH ALL TIERS SUMMARY"
log_info "Environment: $ENVIRONMENT"
log_info "Total Tiers: $total_tiers"
log_info "Successful: $success_count"
log_info "Failed: $failure_count"
log_info "APIs Responding: $verification_success"

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

# Overall result
echo ""
if [[ $failure_count -eq 0 && $verification_success -eq $total_tiers ]]; then
    log_success "🎉 ALL TIERS REFRESHED SUCCESSFULLY!"
    log_info "All GraphQL APIs are ready with relationships tracked"
    exit_code=0
else
    log_error "⚠️  SOME TIERS FAILED OR ARE NOT RESPONDING"
    log_info "Check individual tier logs for details"
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