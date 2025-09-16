#!/bin/bash

# Restart GraphQL service using docker-compose
# Usage: ./restart-graphql.sh <tier> [environment]
#   tier: admin, operator, or member (required)
#   environment: development or production (default: development)

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source shared functions
source "${SCRIPT_DIR}/_shared_functions.sh"

# Check arguments
if [ $# -lt 1 ]; then
    echo "${RED}✗${NC} Usage: $0 <tier> [environment]"
    echo "  tier: admin, operator, or member"
    echo "  environment: development or production (default: development)"
    exit 1
fi

# Parse arguments
TIER="${1}"
ENVIRONMENT="${2:-development}"

# Validate tier
if [[ ! "$TIER" =~ ^(admin|operator|member)$ ]]; then
    echo "${RED}✗${NC} Invalid tier: $TIER"
    echo "${CYAN}ℹ${NC} Valid tiers: admin, operator, member"
    exit 1
fi

# Configure tier
configure_tier "$TIER"

# Colors for output
ERROR="${RED}✗${NC}"
SUCCESS="${GREEN}✓${NC}"
INFO="${CYAN}ℹ${NC}"
PROGRESS="${BLUE}➜${NC}"
WARNING="${YELLOW}⚠${NC}"

# Main execution
echo ""
echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
TIER_UPPER=$(echo "$TIER" | tr '[:lower:]' '[:upper:]')
echo "${CYAN}🔄 RESTART GRAPHQL SERVICE - ${TIER_UPPER} TIER${NC}"
echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${INFO} Tier: $TIER"
echo "${INFO} Environment: $ENVIRONMENT"
echo "${INFO} Container: ${GRAPHQL_TIER_CONTAINER}"

# Production check
if [ "$ENVIRONMENT" = "production" ]; then
    echo ""
    echo "${YELLOW}⚠️  WARNING${NC}: Production restart not implemented"
    echo "${INFO} Please use Hasura Cloud console for production operations"
    exit 1
fi

# Get repository path
REPO_PATH="$(dirname "$SCRIPT_DIR")/${TIER}-graqhql-api"

# Check if repository exists
if [ ! -d "$REPO_PATH" ]; then
    echo "${ERROR} Repository not found: $REPO_PATH"
    exit 1
fi

# Check for docker-compose.yml
if [ ! -f "$REPO_PATH/docker-compose.yml" ]; then
    echo "${ERROR} docker-compose.yml not found in $REPO_PATH"
    exit 1
fi

# Navigate to repository
cd "$REPO_PATH"

# Stop the service
echo ""
echo "${PROGRESS} Stopping ${TIER} GraphQL service..."
if docker-compose down 2>&1; then
    echo "${SUCCESS} Service stopped successfully"
else
    echo "${WARNING} Service may not have been running"
fi

# Wait a moment
sleep 2

# Start the service
echo ""
echo "${PROGRESS} Starting ${TIER} GraphQL service..."
if docker-compose up -d 2>&1; then
    echo "${SUCCESS} Service started successfully"
else
    echo "${ERROR} Failed to start service"
    exit 1
fi

# Wait for health check
echo ""
echo "${PROGRESS} Waiting for service to be healthy..."
sleep 5

# Map tier to port
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

# Test health
echo "${PROGRESS} Testing health endpoint..."
if curl -sf "http://localhost:${PORT}/healthz" > /dev/null 2>&1; then
    echo "${SUCCESS} Service is healthy!"
else
    echo "${WARNING} Service may still be starting up..."
    echo "${INFO} You can check status with: ./docker-status.sh $TIER $ENVIRONMENT"
fi

echo ""
echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Show summary
if [ $COMMAND_ERRORS -eq 0 ]; then
    TIER_CAP="${TIER_UPPER:0:1}${TIER:1}"
    echo "${SUCCESS} ${TIER_CAP} GraphQL service restarted successfully!${NC}"
    echo ""
    echo "Access points:"
    echo "  • GraphQL API: http://localhost:${PORT}/v1/graphql"
    echo "  • Console: http://localhost:${PORT}/console"
    exit 0
else
    echo "${ERROR} Restart completed with errors${NC}"
    exit 1
fi