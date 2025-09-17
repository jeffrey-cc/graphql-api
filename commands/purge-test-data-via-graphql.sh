#!/bin/bash

# purge-test-data-via-graphql.sh
# Purge all test data from the database via GraphQL mutations
# Usage: ./commands/purge-test-data-via-graphql.sh <tier> <environment>

set -euo pipefail

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_shared_functions.sh"

# Parse arguments
if [[ $# -lt 2 ]]; then
    echo "❌ Usage: $0 <tier> <environment>"
    echo "   tier: admin, operator, or member"
    echo "   environment: development or production"
    exit 1
fi

TIER="$1"
ENVIRONMENT="$2"

# Configure tier and validate
if ! configure_tier "$TIER"; then
    echo "❌ Failed to configure tier: $TIER"
    exit 1
fi

validate_environment "$ENVIRONMENT"

# Load tier-specific configuration
if ! load_tier_config "$TIER" "$ENVIRONMENT"; then
    echo "⚠️  Could not load tier configuration, using defaults"
fi

# Set GraphQL endpoint based on tier
GRAPHQL_ENDPOINT="http://localhost:${GRAPHQL_TIER_PORT}"
HASURA_ADMIN_SECRET="${GRAPHQL_TIER_ADMIN_SECRET}"

echo "🧹 Purging test data from ${TIER} GraphQL API (${ENVIRONMENT})"
echo "   Endpoint: ${GRAPHQL_ENDPOINT}"

# Validate GraphQL endpoint is accessible
if ! curl -sf "${GRAPHQL_ENDPOINT}/healthz" > /dev/null 2>&1; then
    echo "❌ GraphQL endpoint not accessible: ${GRAPHQL_ENDPOINT}"
    echo "   Run: ./commands/deploy-graphql.sh ${TIER} ${ENVIRONMENT}"
    exit 1
fi

# Define deletion order (reverse of foreign key dependencies)
# Note: Table names are prefixed with schema name in GraphQL
DELETION_ORDER=(
    # Child tables first (tables with foreign keys)
    "financial_billing_invoices"
    "operators_operator_contacts" 
    "admin_admin_permissions"
    "admin_admin_user_roles"
    "system_file_storage"
    "compliance_compliance_alerts"
    "integration_operator_facility_mappings"
    "sales_sales_leads"
    "support_support_categories"
    
    # Parent tables last (tables referenced by foreign keys)
    "financial_commission_structures"
    "operators_operator_companies"
    "admin_admin_users"
    "system_admin_system_info"
)

TOTAL_DELETED=0
ERRORS=0

echo "🗑️  Deleting data in dependency order..."

for table in "${DELETION_ORDER[@]}"; do
    echo -n "   Deleting ${table}... "
    
    # Create GraphQL mutation
    MUTATION="{
        \"query\": \"mutation { delete_${table}(where: {}) { affected_rows } }\"
    }"
    
    # Execute deletion
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-Hasura-Admin-Secret: ${HASURA_ADMIN_SECRET}" \
        -d "${MUTATION}" \
        "${GRAPHQL_ENDPOINT}/v1/graphql" 2>/dev/null || echo '{"errors":[{"message":"Request failed"}]}')
    
    # Check for errors
    if echo "$RESPONSE" | jq -e '.errors' > /dev/null 2>&1; then
        ERROR_MSG=$(echo "$RESPONSE" | jq -r '.errors[0].message' 2>/dev/null || echo "Unknown error")
        echo "❌ FAILED: $ERROR_MSG"
        ((ERRORS++))
    else
        AFFECTED_ROWS=$(echo "$RESPONSE" | jq -r '.data.delete_'${table}'.affected_rows' 2>/dev/null || echo "0")
        echo "✅ Deleted ${AFFECTED_ROWS} rows"
        ((TOTAL_DELETED += AFFECTED_ROWS))
    fi
done

echo ""
if [[ $ERRORS -eq 0 ]]; then
    echo "✅ Purge completed successfully"
    echo "   Total rows deleted: ${TOTAL_DELETED}"
    echo "   Database is clean and ready for fresh test data"
else
    echo "⚠️  Purge completed with ${ERRORS} errors"
    echo "   Total rows deleted: ${TOTAL_DELETED}"
    echo "   Some tables may still contain data"
    exit 1
fi