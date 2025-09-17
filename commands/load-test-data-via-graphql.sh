#!/bin/bash

# load-test-data-via-graphql.sh
# Load test data from CSV files into the database via GraphQL mutations
# Usage: ./commands/load-test-data-via-graphql.sh <tier> <environment>

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

echo "📊 Loading test data into ${TIER} GraphQL API (${ENVIRONMENT})"
echo "   Endpoint: ${GRAPHQL_ENDPOINT}"

# Validate GraphQL endpoint is accessible
if ! curl -sf "${GRAPHQL_ENDPOINT}/healthz" > /dev/null 2>&1; then
    echo "❌ GraphQL endpoint not accessible: ${GRAPHQL_ENDPOINT}"
    echo "   Run: ./commands/deploy-graphql.sh ${TIER} ${ENVIRONMENT}"
    exit 1
fi

# Define test data directory
TEST_DATA_DIR="${SCRIPT_DIR}/../test-data"

if [[ ! -d "$TEST_DATA_DIR" ]]; then
    echo "❌ Test data directory not found: $TEST_DATA_DIR"
    exit 1
fi

# CSV to GraphQL field mapping function
csv_to_graphql_object() {
    local csv_file="$1"
    local table_name="$2"
    
    # Use a simpler approach with python for proper CSV parsing
    python3 << EOF
import csv
import json
import sys

try:
    with open('${csv_file}', 'r') as f:
        reader = csv.DictReader(f)
        objects = []
        
        for row in reader:
            # Clean up the row data
            clean_row = {}
            for key, value in row.items():
                # Handle empty values
                if value == '' or value is None:
                    clean_row[key] = None
                # Handle boolean values
                elif value.lower() in ['true', 'false']:
                    clean_row[key] = value.lower() == 'true'
                # Handle numeric values
                elif value.isdigit():
                    clean_row[key] = int(value)
                # Handle float values
                elif '.' in value and value.replace('.', '').replace('-', '').isdigit():
                    clean_row[key] = float(value)
                # Everything else is a string
                else:
                    clean_row[key] = value
            
            objects.append(clean_row)
        
        print(json.dumps(objects))
        
except Exception as e:
    print(f'{{"error": "{str(e)}"}}')
    sys.exit(1)
EOF
}

# Load data in correct order (respecting foreign keys)
# Note: Table names are prefixed with schema name in GraphQL
LOAD_ORDER=(
    "01_admin/01_admin_users.csv:admin_admin_users"
    "01_admin/02_admin_permissions.csv:admin_admin_permissions"
    "02_system/01_admin_system_info.csv:system_admin_system_info"
    "02_system/02_file_storage.csv:system_file_storage"
    "03_operators/01_operator_companies.csv:operators_operator_companies"
    "03_operators/02_operator_contacts.csv:operators_operator_contacts"
    "04_financial/01_commission_structures.csv:financial_commission_structures"
    "04_financial/07_billing_invoices.csv:financial_billing_invoices"
    "05_sales/01_sales_leads.csv:sales_sales_leads"
    "06_support/01_support_categories.csv:support_support_categories"
    "07_compliance/01_compliance_alerts.csv:compliance_compliance_alerts"
    "08_integration/01_operator_facility_mappings.csv:integration_operator_facility_mappings"
)

TOTAL_INSERTED=0
ERRORS=0

echo "📥 Loading data in dependency order..."

for item in "${LOAD_ORDER[@]}"; do
    IFS=':' read -r csv_path table_name <<< "$item"
    csv_file="${TEST_DATA_DIR}/${csv_path}"
    
    if [[ ! -f "$csv_file" ]]; then
        echo "   ⚠️  Skipping ${table_name}: CSV file not found (${csv_file})"
        continue
    fi
    
    echo -n "   Loading ${table_name}... "
    
    # Count expected rows
    expected_rows=$(($(wc -l < "$csv_file") - 1))  # Subtract header
    
    if [[ $expected_rows -le 0 ]]; then
        echo "⚠️  No data rows found"
        continue
    fi
    
    # Convert CSV to GraphQL objects
    objects_json=$(csv_to_graphql_object "$csv_file" "$table_name")
    
    # Create GraphQL mutation payload
    payload=$(jq -n \
        --arg query "mutation insert_data(\$objects: [${table_name}_insert_input!]!) { insert_${table_name}(objects: \$objects) { affected_rows } }" \
        --argjson objects "${objects_json}" \
        '{query: $query, variables: {objects: $objects}}')
    
    # Execute insertion
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-Hasura-Admin-Secret: ${HASURA_ADMIN_SECRET}" \
        -d "${payload}" \
        "${GRAPHQL_ENDPOINT}/v1/graphql" 2>/dev/null || echo '{"errors":[{"message":"Request failed"}]}')
    
    # Check for errors
    if echo "$response" | jq -e '.errors' > /dev/null 2>&1; then
        error_msg=$(echo "$response" | jq -r '.errors[0].message' 2>/dev/null || echo "Unknown error")
        echo "❌ FAILED: $error_msg"
        ((ERRORS++))
    else
        affected_rows=$(echo "$response" | jq -r '.data.insert_'${table_name}'.affected_rows' 2>/dev/null || echo "0")
        echo "✅ Inserted ${affected_rows}/${expected_rows} rows"
        ((TOTAL_INSERTED += affected_rows))
        
        if [[ $affected_rows -ne $expected_rows ]]; then
            echo "     ⚠️  Row count mismatch: expected ${expected_rows}, got ${affected_rows}"
        fi
    fi
done

echo ""
if [[ $ERRORS -eq 0 ]]; then
    echo "✅ Data loading completed successfully"
    echo "   Total rows inserted: ${TOTAL_INSERTED}"
    echo "   Database is ready for testing"
else
    echo "⚠️  Data loading completed with ${ERRORS} errors"
    echo "   Total rows inserted: ${TOTAL_INSERTED}"
    echo "   Some data may be missing"
    exit 1
fi