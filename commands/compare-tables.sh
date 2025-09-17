#!/bin/bash

# compare-tables.sh
# Compare tracked tables between development and production for all tiers
# Usage: ./commands/compare-tables.sh [tier|all]

set -euo pipefail

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_shared_functions.sh"

# Parse arguments
TIER="${1:-all}"

# Colors for output
HEADER="${CYAN}${BOLD}"
SUCCESS="${GREEN}"
WARNING="${YELLOW}"
ERROR="${RED}"
RESET="${NC}"

# Function to compare tables for a specific tier
compare_tier_tables() {
    local tier="$1"
    local dev_secret=""
    local prod_secret=""
    local prod_endpoint=""
    
    # Set credentials based on tier
    case "$tier" in
        "admin")
            dev_secret="CCTech2024Admin"
            prod_secret="G2t1VKcCa2WKEZT671y6lfZBvP2gjv43H5YdqKTnSP0YIwjcPB6sC15tcVgHN2Vb"
            prod_endpoint="https://admin-graphql-api.hasura.app"
            ;;
        "operator")
            dev_secret="CCTech2024Operator"
            prod_secret="tdlRz1LKUx1MM2ckawtmb97s0bsfBxU1DE344Bege8wK4oV66qs94lu4IDkTVE55"
            prod_endpoint="https://operator-graphql-api.hasura.app"
            ;;
        "member")
            dev_secret="CCTech2024Member"
            prod_secret="0yyZqc58qfB7t4bJ56LIUBnxsMhvVtENyU9YxiE7cmA0qJLLlIIjm1hcaMGxgbs1"
            prod_endpoint="https://member-graphql-api.hasura.app"
            ;;
        *)
            echo "${ERROR}Unknown tier: $tier${RESET}"
            return 1
            ;;
    esac
    
    # Configure tier for port info
    configure_tier "$tier"
    
    echo ""
    local tier_upper=$(echo "$tier" | tr '[:lower:]' '[:upper:]')
    echo "${HEADER}📊 ${tier_upper} Tier Comparison${RESET}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Get development tables
    echo -n "Fetching development tables... "
    dev_tables=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-Hasura-Admin-Secret: ${dev_secret}" \
        -d '{"query": "{ __schema { queryType { fields { name } } } }"}' \
        "http://localhost:${GRAPHQL_TIER_PORT}/v1/graphql" 2>/dev/null | \
        jq -r '.data.__schema.queryType.fields[].name' 2>/dev/null | \
        grep -v "_by_pk\|_aggregate" | sort) || dev_tables=""
    
    if [ -z "$dev_tables" ]; then
        echo "${ERROR}FAILED${RESET}"
        echo "  ⚠️  Could not connect to development server on port ${GRAPHQL_TIER_PORT}"
        return 1
    fi
    
    dev_count=$(echo "$dev_tables" | wc -l | xargs)
    echo "${SUCCESS}${dev_count} tables${RESET}"
    
    # Get production tables
    echo -n "Fetching production tables... "
    prod_tables=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-Hasura-Admin-Secret: ${prod_secret}" \
        -d '{"query": "{ __schema { queryType { fields { name } } } }"}' \
        "${prod_endpoint}/v1/graphql" 2>/dev/null | \
        jq -r '.data.__schema.queryType.fields[].name' 2>/dev/null | \
        grep -v "_by_pk\|_aggregate" | sort) || prod_tables=""
    
    if [ -z "$prod_tables" ]; then
        echo "${ERROR}FAILED${RESET}"
        echo "  ⚠️  Could not connect to production server"
        return 1
    fi
    
    prod_count=$(echo "$prod_tables" | wc -l | xargs)
    echo "${SUCCESS}${prod_count} tables${RESET}"
    
    # Compare tables
    echo ""
    echo "📈 Summary:"
    echo "  Development: ${BOLD}${dev_count}${RESET} tables"
    echo "  Production:  ${BOLD}${prod_count}${RESET} tables"
    
    # Find differences
    diff_dev=$(comm -23 <(echo "$dev_tables") <(echo "$prod_tables") 2>/dev/null)
    diff_prod=$(comm -13 <(echo "$dev_tables") <(echo "$prod_tables") 2>/dev/null)
    
    if [ -n "$diff_dev" ]; then
        echo ""
        echo "${WARNING}⚠️  Tables only in Development:${RESET}"
        echo "$diff_dev" | sed 's/^/    - /'
    fi
    
    if [ -n "$diff_prod" ]; then
        echo ""
        echo "${WARNING}⚠️  Tables only in Production:${RESET}"
        echo "$diff_prod" | sed 's/^/    - /'
    fi
    
    if [ "$dev_count" -eq "$prod_count" ] && [ -z "$diff_dev" ] && [ -z "$diff_prod" ]; then
        echo ""
        echo "${SUCCESS}✅ Perfect match! Development and Production are in sync.${RESET}"
    elif [ "$dev_count" -eq "$prod_count" ]; then
        echo ""
        echo "${WARNING}⚠️  Table count matches but different tables are tracked.${RESET}"
    else
        echo ""
        echo "${ERROR}❌ Environment mismatch detected.${RESET}"
    fi
}

# Main execution
echo ""
echo "${HEADER}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "${HEADER}🔄 TABLE TRACKING COMPARISON${RESET}"
echo "${HEADER}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "${CYAN}ℹ️  Comparing: Development vs Production${RESET}"

if [ "$TIER" = "all" ]; then
    # Compare all tiers
    for t in admin operator member; do
        compare_tier_tables "$t"
    done
    
    echo ""
    echo "${HEADER}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo "${SUCCESS}✓ Comparison complete for all tiers${RESET}"
else
    # Compare specific tier
    compare_tier_tables "$TIER"
    
    echo ""
    echo "${HEADER}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo "${SUCCESS}✓ Comparison complete for ${TIER} tier${RESET}"
fi

echo ""