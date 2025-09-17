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

echo "📦 Loading operator test data via GraphQL API ($ENVIRONMENT)"
echo "   Endpoint: $GRAPHQL_ENDPOINT"

# Base directory for test data
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DATA_DIR="${SCRIPT_DIR}/../test-data"

# Define loading order for operator schemas
LOADING_ORDER=(
    "09_operator_identity"
    "10_operator_operations"
    "11_operator_access"
    "12_operator_assets"
    "13_operator_financial"
    "14_operator_sales"
    "15_operator_communications"
    "16_operator_documents"
    "17_operator_integration"
    "18_operator_support"
    "19_operator_memberships"
)

TOTAL_LOADED=0
ERROR_COUNT=0

for dir in "${LOADING_ORDER[@]}"; do
    if [ ! -d "$TEST_DATA_DIR/$dir" ]; then
        continue
    fi
    
    echo ""
    echo "📂 Loading data from $dir..."
    
    for csv_file in "$TEST_DATA_DIR/$dir"/*.csv; do
        if [ ! -f "$csv_file" ]; then
            continue
        fi
        
        filename=$(basename "$csv_file")
        # Extract table name from filename (remove number prefix and .csv)
        table_base=$(echo "$filename" | sed 's/^[0-9]*_//' | sed 's/\.csv$//')
        
        # Map CSV filename to GraphQL table name
        case "$dir" in
            09_operator_identity)
                table_name="identity_$table_base"
                ;;
            10_operator_operations)
                table_name="operations_$table_base"
                ;;
            11_operator_access)
                table_name="access_$table_base"
                ;;
            12_operator_assets)
                table_name="assets_$table_base"
                ;;
            13_operator_financial)
                table_name="financial_$table_base"
                ;;
            14_operator_sales)
                table_name="sales_$table_base"
                ;;
            15_operator_communications)
                table_name="communications_$table_base"
                ;;
            16_operator_documents)
                table_name="documents_$table_base"
                ;;
            17_operator_integration)
                table_name="integration_$table_base"
                ;;
            18_operator_support)
                table_name="support_$table_base"
                ;;
            19_operator_memberships)
                table_name="memberships_$table_base"
                ;;
            *)
                table_name="$table_base"
                ;;
        esac
        
        echo -n "   Loading $table_name from $filename... "
        
        # Use Python to parse CSV and convert to JSON
        json_data=$(python3 -c "
import csv
import json
import sys

def convert_value(value):
    if value == '' or value is None:
        return None
    # Check for boolean
    if value.lower() in ['true', 'false']:
        return value.lower() == 'true'
    # Try integer
    try:
        return int(value)
    except ValueError:
        pass
    # Try float
    try:
        return float(value)
    except ValueError:
        pass
    # Return as string
    return value

with open('${csv_file}', 'r') as f:
    reader = csv.DictReader(f)
    rows = []
    for row in reader:
        converted_row = {}
        for key, value in row.items():
            converted_row[key] = convert_value(value)
        rows.append(converted_row)
    print(json.dumps(rows))
" 2>/dev/null)
        
        if [ -z "$json_data" ] || [ "$json_data" = "[]" ]; then
            echo "⚠️  No data to load"
            continue
        fi
        
        # Count rows
        row_count=$(echo "$json_data" | jq '. | length')
        
        # Build the insert mutation with variables
        mutation="mutation InsertData(\$objects: [${table_name}_insert_input!]!) { insert_${table_name}(objects: \$objects) { affected_rows } }"
        
        # Execute the insertion
        response=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -H "X-Hasura-Admin-Secret: $ADMIN_SECRET" \
            -d "{\"query\": \"$mutation\", \"variables\": {\"objects\": $json_data}}" \
            "$GRAPHQL_ENDPOINT")
        
        # Check for errors
        if echo "$response" | grep -q '"errors"'; then
            error=$(echo "$response" | jq -r '.errors[0].message' 2>/dev/null || echo "Unknown error")
            echo "❌ FAILED: $error"
            ((ERROR_COUNT++))
        else
            rows_loaded=$(echo "$response" | jq -r '.data.insert_'$table_name'.affected_rows' 2>/dev/null || echo "0")
            if [ "$rows_loaded" = "null" ]; then
                rows_loaded=0
            fi
            TOTAL_LOADED=$((TOTAL_LOADED + rows_loaded))
            if [ "$rows_loaded" = "$row_count" ]; then
                echo "✅ Loaded $rows_loaded rows"
            else
                echo "⚠️  Loaded $rows_loaded of $row_count rows"
            fi
        fi
    done
done

echo ""
if [ $ERROR_COUNT -eq 0 ]; then
    echo "✅ Data loading completed successfully"
    echo "   Total rows loaded: $TOTAL_LOADED"
else
    echo "⚠️  Data loading completed with $ERROR_COUNT errors"
    echo "   Total rows loaded: $TOTAL_LOADED"
fi
