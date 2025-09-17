#!/bin/bash

# Parse arguments
ENVIRONMENT="${1:-development}"

# Set environment-specific configuration
if [ "$ENVIRONMENT" = "production" ]; then
    GRAPHQL_ENDPOINT="https://operator-graphql-api.hasura.app/v1/graphql"
    ADMIN_SECRET="tdlRz1LKUx1MM2ckawtmb97s0bsfBxU1DE344Bege8wK4oV66qs94lu4IDkTVE55"
else
    GRAPHQL_ENDPOINT="http://localhost:8102/v1/graphql"
    ADMIN_SECRET="CCTech2024Operator"
fi

echo "🧹 Purging operator test data from GraphQL API ($ENVIRONMENT)"
echo "   Endpoint: $GRAPHQL_ENDPOINT"

# Define deletion order for operator tables (reverse dependency order)
DELETION_ORDER=(
    # Dependent tables first - Child tables
    "third_party_mappings_member_access_pins"
    "third_party_mappings_member_facilities"
    "third_party_mappings_member_monnit_sensors"
    "deferred_tasks"
    "memberships_specification_item_billing_rules"
    "memberships_membership_specification_items"
    "memberships_memberships"
    "memberships_applications"
    "support_tickets"
    "sales_lead_activities"
    "sales_leads"
    "financial_invoices"
    "documents_documents"
    "communications_communications"
    "integration_monnit_sensors"
    "integration_monnit_gateways"
    "assets_bookings"
    "assets_booking_serieses"
    "assets_assets"
    "access_pin_space"
    "access_pins"
    "access_door_events"
    "access_access_grants"
    "access_doors"
    "access_locks"
    "operations_facilities"
    
    # Parent tables last - Independent tables
    "memberships_membership_specifications"
    "support_ticket_kinds"
    "sales_stages"
    "financial_account_codes"
    "documents_document_kinds"
    "communications_communication_kinds"
    "integration_sensor_kinds"
    "assets_asset_classes"
    "access_lock_models"
    "operations_facility_kinds"
    "identity_principals"
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
