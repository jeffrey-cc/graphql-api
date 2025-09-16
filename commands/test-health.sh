#!/bin/bash

# Test health of GraphQL services
# Usage: ./test-health.sh [tier] [environment]
#   tier: admin, operator, member, or all (default: all)
#   environment: development or production (default: development)

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source shared functions
source "${SCRIPT_DIR}/_shared_functions.sh"

# Parse arguments
TIER="${1:-all}"
ENVIRONMENT="${2:-development}"

# Colors for output
ERROR="${RED}✗${NC}"
SUCCESS="${GREEN}✓${NC}"
INFO="${CYAN}ℹ${NC}"
PROGRESS="${BLUE}➜${NC}"
WARNING="${YELLOW}⚠${NC}"

# Function to test a single GraphQL endpoint
test_graphql_health() {
    local tier=$1
    local port=$2
    local container=$3
    
    printf "%-20s" "  $tier:"
    
    if [ "$ENVIRONMENT" = "production" ]; then
        # For production, we'd need to use the production URLs
        echo " ⏭️  Skipped (production health checks use different endpoints)"
        return 0
    fi
    
    # Check if container is running first
    if ! docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        echo " ❌ Container not running"
        ((COMMAND_ERRORS++))
        return 1
    fi
    
    # Test health endpoint
    if curl -sf "http://localhost:${port}/healthz" > /dev/null 2>&1; then
        echo " ✅ Healthy (port $port)"
        return 0
    else
        echo " ❌ Not responding (port $port)"
        ((COMMAND_ERRORS++))
        return 1
    fi
}

# Main execution
echo ""
echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${CYAN}🏥 GRAPHQL HEALTH CHECK${NC}"
echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${INFO} Environment: $ENVIRONMENT"
echo "${INFO} Checking: ${TIER}"
echo ""

if [ "$TIER" = "all" ]; then
    echo "Testing all GraphQL services:"
    test_graphql_health "Admin" "8101" "admin-graphql-server"
    test_graphql_health "Operator" "8102" "operator-graphql-server"
    test_graphql_health "Member" "8103" "member-graphql-server"
else
    # Configure for specific tier
    configure_tier "$TIER"
    
    # Map tier to port (use updated ports)
    case "$TIER" in
        admin)
            PORT=8101
            ;;
        operator)
            PORT=8102
            ;;
        member)
            PORT=8103
            ;;
    esac
    
    echo "Testing $TIER GraphQL service:"
    TIER_CAP=$(echo "$TIER" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
    test_graphql_health "${TIER_CAP}" "$PORT" "${TIER}-graphql-server"
fi

echo ""
echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Show summary
if [ $COMMAND_ERRORS -eq 0 ]; then
    echo "${SUCCESS} All health checks passed!${NC}"
    exit 0
else
    echo "${ERROR} ${COMMAND_ERRORS} health check(s) failed${NC}"
    exit 1
fi