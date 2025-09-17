#!/bin/bash

# test-graphql-data-workflow.sh
# Complete test workflow: purge → load → verify → report
# Usage: ./commands/test-graphql-data-workflow.sh <tier> <environment>

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

echo "🧪 GraphQL Data Workflow Test for ${TIER} (${ENVIRONMENT})"
echo "   Endpoint: ${GRAPHQL_ENDPOINT}"
echo "   This will: purge → load → verify → report"
echo ""

# Step 1: Purge existing data
echo "🧹 Step 1: Purging existing test data..."
if "${SCRIPT_DIR}/purge-test-data-via-graphql.sh" "$TIER" "$ENVIRONMENT"; then
    echo "✅ Purge completed successfully"
else
    echo "❌ Purge failed"
    exit 1
fi
echo ""

# Step 2: Load test data
echo "📊 Step 2: Loading test data from CSV files..."
if "${SCRIPT_DIR}/load-test-data-via-graphql.sh" "$TIER" "$ENVIRONMENT"; then
    echo "✅ Data loading completed successfully"
else
    echo "❌ Data loading failed"
    exit 1
fi
echo ""

# Step 3: Verify data counts
echo "🔍 Step 3: Verifying data counts..."

# Count CSV rows vs database rows
TEST_DATA_DIR="${SCRIPT_DIR}/../test-data"
VERIFICATION_ERRORS=0

# Tables to verify (with schema prefixes)
TABLES=(
    "admin_admin_users"
    "admin_admin_permissions"
    "system_admin_system_info"
    "system_file_storage"
    "operators_operator_companies"
    "operators_operator_contacts"
    "financial_commission_structures"
    "financial_billing_invoices"
    "sales_sales_leads"
    "support_support_categories"
    "compliance_compliance_alerts"
    "integration_operator_facility_mappings"
)

for table in "${TABLES[@]}"; do
    echo -n "   Checking ${table}... "
    
    # Find corresponding CSV file
    CSV_FILE=$(find "$TEST_DATA_DIR" -name "*${table}.csv" | head -n 1)
    
    if [[ ! -f "$CSV_FILE" ]]; then
        echo "⚠️  CSV file not found"
        continue
    fi
    
    # Count CSV rows (exclude header)
    CSV_ROWS=$(($(wc -l < "$CSV_FILE") - 1))
    
    # Count database rows via GraphQL
    QUERY="{
        \"query\": \"query { ${table}_aggregate { aggregate { count } } }\"
    }"
    
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-Hasura-Admin-Secret: ${HASURA_ADMIN_SECRET}" \
        -d "${QUERY}" \
        "${GRAPHQL_ENDPOINT}/v1/graphql" 2>/dev/null || echo '{"errors":[{"message":"Request failed"}]}')
    
    if echo "$RESPONSE" | jq -e '.errors' > /dev/null 2>&1; then
        echo "❌ Query failed"
        ((VERIFICATION_ERRORS++))
    else
        DB_ROWS=$(echo "$RESPONSE" | jq -r '.data.'${table}'_aggregate.aggregate.count' 2>/dev/null || echo "0")
        
        if [[ "$CSV_ROWS" -eq "$DB_ROWS" ]]; then
            echo "✅ ${DB_ROWS} rows (matches CSV)"
        else
            echo "❌ ${DB_ROWS} rows (expected ${CSV_ROWS})"
            ((VERIFICATION_ERRORS++))
        fi
    fi
done

echo ""

# Step 4: Generate summary report
echo "📋 Step 4: Test Summary Report"
echo "============================================"

if [[ $VERIFICATION_ERRORS -eq 0 ]]; then
    echo "✅ ALL TESTS PASSED"
    echo "   - Data purged successfully"
    echo "   - Test data loaded successfully"
    echo "   - All row counts match CSV files"
    echo "   - GraphQL API is ready for testing"
else
    echo "❌ TESTS FAILED"
    echo "   - ${VERIFICATION_ERRORS} verification errors found"
    echo "   - Some data may be missing or corrupted"
    echo "   - Check GraphQL schema and table tracking"
    exit 1
fi

echo ""
echo "🎉 GraphQL data workflow test completed successfully!"