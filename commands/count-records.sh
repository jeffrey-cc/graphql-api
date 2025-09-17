#!/bin/bash

# count-records.sh
# Count records in all tables for a specific tier and environment
# Usage: ./commands/count-records.sh <tier> <environment> [--compare]

set -euo pipefail

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_shared_functions.sh"

# Parse arguments
if [[ $# -lt 2 ]]; then
    echo "❌ Usage: $0 <tier> <environment> [--compare]"
    echo "   tier: admin, operator, or member"
    echo "   environment: development or production"
    echo "   --compare: Optional flag to compare dev vs prod"
    exit 1
fi

TIER="$1"
ENVIRONMENT="$2"
COMPARE_MODE="${3:-}"

# Colors for output
HEADER="${CYAN}${BOLD}"
SUCCESS="${GREEN}"
WARNING="${YELLOW}"
INFO="${BLUE}"
RESET="${NC}"

# Function to get credentials and endpoint
get_credentials() {
    local tier="$1"
    local env="$2"
    
    if [ "$env" = "development" ]; then
        case "$tier" in
            "admin")
                echo "CCTech2024Admin|http://localhost:8101"
                ;;
            "operator")
                echo "CCTech2024Operator|http://localhost:8102"
                ;;
            "member")
                echo "CCTech2024Member|http://localhost:8103"
                ;;
        esac
    else
        case "$tier" in
            "admin")
                echo "G2t1VKcCa2WKEZT671y6lfZBvP2gjv43H5YdqKTnSP0YIwjcPB6sC15tcVgHN2Vb|https://admin-graphql-api.hasura.app"
                ;;
            "operator")
                echo "tdlRz1LKUx1MM2ckawtmb97s0bsfBxU1DE344Bege8wK4oV66qs94lu4IDkTVE55|https://operator-graphql-api.hasura.app"
                ;;
            "member")
                echo "0yyZqc58qfB7t4bJ56LIUBnxsMhvVtENyU9YxiE7cmA0qJLLlIIjm1hcaMGxgbs1|https://member-graphql-api.hasura.app"
                ;;
        esac
    fi
}

# Function to count records for a specific environment
count_records() {
    local tier="$1"
    local env="$2"
    
    # Get credentials
    IFS='|' read -r admin_secret endpoint <<< "$(get_credentials "$tier" "$env")"
    
    echo ""
    local tier_upper=$(echo "$tier" | tr '[:lower:]' '[:upper:]')
    local env_upper=$(echo "$env" | tr '[:lower:]' '[:upper:]')
    echo "${HEADER}📊 Counting Records: ${tier_upper} - ${env_upper}${RESET}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Get all table names (excluding aggregates and by_pk)
    tables=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-Hasura-Admin-Secret: ${admin_secret}" \
        -d '{"query": "{ __schema { queryType { fields { name } } } }"}' \
        "${endpoint}/v1/graphql" 2>/dev/null | \
        jq -r '.data.__schema.queryType.fields[].name' 2>/dev/null | \
        grep -v "_aggregate\|_by_pk" | sort) || tables=""
    
    if [ -z "$tables" ]; then
        echo "${ERROR}❌ Could not connect to ${env} server${RESET}"
        return 1
    fi
    
    local total_records=0
    local table_count=0
    local non_empty_tables=0
    
    # Build a single GraphQL query to get all counts at once
    echo "Fetching record counts..."
    
    # Create the aggregates query
    query="query RecordCounts {"
    for table in $tables; do
        # Clean table name for alias (replace invalid characters)
        alias=$(echo "$table" | tr '-' '_' | tr '.' '_')
        query+=" ${alias}_count: ${table}_aggregate { aggregate { count } }"
    done
    query+=" }"
    
    # Execute the query
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-Hasura-Admin-Secret: ${admin_secret}" \
        -d "{\"query\": \"${query}\"}" \
        "${endpoint}/v1/graphql" 2>/dev/null)
    
    # Check for errors
    if echo "$response" | jq -e '.errors' > /dev/null 2>&1; then
        echo "${ERROR}❌ Error querying tables${RESET}"
        echo "$response" | jq '.errors[0].message' 2>/dev/null
        return 1
    fi
    
    # Parse results and display
    echo ""
    echo "${INFO}Tables with data:${RESET}"
    echo ""
    
    # Process each table count
    for table in $tables; do
        alias=$(echo "$table" | tr '-' '_' | tr '.' '_')
        count=$(echo "$response" | jq -r ".data.${alias}_count.aggregate.count" 2>/dev/null || echo "0")
        
        if [ "$count" != "null" ] && [ "$count" != "0" ]; then
            printf "  %-50s %10s records\n" "$table" "$count"
            total_records=$((total_records + count))
            ((non_empty_tables++))
        fi
        ((table_count++))
    done
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "${SUCCESS}📈 Summary:${RESET}"
    echo "  Total tables:      ${BOLD}${table_count}${RESET}"
    echo "  Non-empty tables:  ${BOLD}${non_empty_tables}${RESET}"
    echo "  Total records:     ${BOLD}${total_records}${RESET}"
    
    # Return total for comparison mode
    echo "$total_records"
}

# Function to compare dev vs prod
compare_environments() {
    local tier="$1"
    
    echo ""
    local tier_upper=$(echo "$tier" | tr '[:lower:]' '[:upper:]')
    echo "${HEADER}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo "${HEADER}🔄 RECORD COUNT COMPARISON - ${tier_upper}${RESET}"
    echo "${HEADER}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    
    # Count development records
    dev_count=$(count_records "$tier" "development" | tail -1)
    
    # Count production records  
    prod_count=$(count_records "$tier" "production" | tail -1)
    
    echo ""
    echo "${HEADER}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo "${HEADER}📊 COMPARISON RESULTS${RESET}"
    echo "${HEADER}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    echo "  Development total: ${BOLD}${dev_count}${RESET} records"
    echo "  Production total:  ${BOLD}${prod_count}${RESET} records"
    
    if [ "$dev_count" -gt "$prod_count" ]; then
        diff=$((dev_count - prod_count))
        echo ""
        echo "  ${WARNING}⚠️  Development has ${diff} more records${RESET}"
    elif [ "$prod_count" -gt "$dev_count" ]; then
        diff=$((prod_count - dev_count))
        echo ""
        echo "  ${WARNING}⚠️  Production has ${diff} more records${RESET}"
    else
        echo ""
        echo "  ${SUCCESS}✅ Record counts match!${RESET}"
    fi
}

# Main execution
if [ "$COMPARE_MODE" = "--compare" ]; then
    compare_environments "$TIER"
else
    count_records "$TIER" "$ENVIRONMENT"
fi

echo ""