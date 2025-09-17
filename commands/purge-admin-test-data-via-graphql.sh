#!/bin/bash

# Parse arguments
ENVIRONMENT="${1:-development}"

# Set environment-specific configuration
if [ "$ENVIRONMENT" = "production" ]; then
    GRAPHQL_ENDPOINT="https://admin-graphql-api.hasura.app/v1/graphql"
    ADMIN_SECRET="G2t1VKcCa2WKEZT671y6lfZBvP2gjv43H5YdqKTnSP0YIwjcPB6sC15tcVgHN2Vb"
else
    GRAPHQL_ENDPOINT="http://localhost:8101/v1/graphql"
    ADMIN_SECRET="CCTech2024Admin"
fi

echo "🧹 Purging admin test data from GraphQL API ($ENVIRONMENT)"
echo "   Endpoint: $GRAPHQL_ENDPOINT"

# Define deletion order for admin tables (reverse dependency order)
DELETION_ORDER=(
    # Dependent tables first
    "financial_billing_invoices"
    "operators_operator_contacts"
    "admin_admin_permissions"
    "admin_admin_user_roles"
    "system_file_storage"
    "compliance_compliance_alerts"
    "integration_operator_facility_mappings"
    "sales_sales_leads"
    "support_support_categories"
    "financial_commission_structures"
    "operators_operator_companies"
    "admin_admin_users"
    "system_admin_system_info"
)

echo "🗑️  Deleting data in dependency order..."

TOTAL_DELETED=0
ERROR_COUNT=0

for table in "${DELETION_ORDER[@]}"; do
    echo -n "   Deleting $table... "
    
    # Build the delete mutation
    mutation="mutation { delete_${table}(where: {}) { affected_rows } }"
    
    # Execute the deletion
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-Hasura-Admin-Secret: $ADMIN_SECRET" \
        -d "{\"query\": \"$mutation\"}" \
        "$GRAPHQL_ENDPOINT")
    
    # Check for errors
    if echo "$response" | grep -q '"errors"'; then
        error=$(echo "$response" | jq -r '.errors[0].message' 2>/dev/null || echo "Unknown error")
        echo "❌ FAILED: $error"
        ((ERROR_COUNT++))
    else
        rows_deleted=$(echo "$response" | jq -r '.data.delete_'$table'.affected_rows' 2>/dev/null || echo "0")
        if [ "$rows_deleted" = "null" ]; then
            rows_deleted=0
        fi
        TOTAL_DELETED=$((TOTAL_DELETED + rows_deleted))
        if [ "$rows_deleted" -gt 0 ]; then
            echo "✅ Deleted $rows_deleted rows"
        else
            echo "✅ No rows to delete"
        fi
    fi
done

echo ""
if [ $ERROR_COUNT -eq 0 ]; then
    echo "✅ Purge completed successfully"
    echo "   Total rows deleted: $TOTAL_DELETED"
else
    echo "⚠️  Purge completed with $ERROR_COUNT errors"
    echo "   Total rows deleted: $TOTAL_DELETED"
    echo "   Some tables may still contain data"
fi
