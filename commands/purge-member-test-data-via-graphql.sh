#!/bin/bash

# Parse arguments
ENVIRONMENT="${1:-development}"

# Set environment-specific configuration
if [ "$ENVIRONMENT" = "production" ]; then
    GRAPHQL_ENDPOINT="https://member-graphql-api.hasura.app/v1/graphql"
    ADMIN_SECRET="0yyZqc58qfB7t4bJ56LIUBnxsMhvVtENyU9YxiE7cmA0qJLLlIIjm1hcaMGxgbs1"
else
    GRAPHQL_ENDPOINT="http://localhost:8103/v1/graphql"
    ADMIN_SECRET="CCTech2024Member"
fi

echo "🧹 Purging member test data from GraphQL API ($ENVIRONMENT)"
echo "   Endpoint: $GRAPHQL_ENDPOINT"

# Define deletion order for member tables (reverse dependency order)
DELETION_ORDER=(
    # Dependent tables first (child tables with foreign keys)
    "usage_order_items"
    "usage_orders"
    "usage_kitchen_sessions"
    "payments_invoice_line_items"
    "payments_invoices"
    "payments_payments"
    "membership_company_subscriptions"
    "bookings_member_facility_access"
    "bookings_facility_access_log"
    "bookings_booking_requests"
    "integration_signatures"
    "integration_contracts"
    "integration_applications"
    "integration_memberships"
    "integration_membership_specification_items"
    "communications_user_activity_log"
    "profile_user_sessions"
    "profile_user_permissions"
    "member_company_contacts"
    "member_company_documents"
    "member_company_settings"
    
    # Parent tables last (tables with primary keys referenced by others)
    "usage_menu_items"
    "usage_inventory_items"
    "payments_payment_methods"
    "membership_subscription_plans"
    "bookings_operator_facilities"
    "integration_specification_item_billing_rules"
    "integration_membership_specifications"
    "integration_packages"
    "integration_applicant_profiles"
    "member_users"
    "member_companies"
    "member_system_settings"
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
