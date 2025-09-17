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

echo "📦 Loading admin test data via GraphQL API ($ENVIRONMENT)"
echo "   Endpoint: $GRAPHQL_ENDPOINT"

# Base directory for test data
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DATA_DIR="${SCRIPT_DIR}/../test-data"

# Define loading order for admin schemas
LOADING_ORDER=(
    "01_admin"
    "02_system"
    "03_operators"
    "04_financial"
    "05_sales"
    "06_support"
    "07_compliance"
    "08_integration"
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
        
        # Map CSV filename to GraphQL table name based on directory
        case "$dir" in
            01_admin)
                table_name="admin_${table_base}"
                ;;
            02_system)
                table_name="system_${table_base}"
                ;;
            03_operators)
                table_name="operators_${table_base}"
                ;;
            04_financial)
                table_name="financial_${table_base}"
                ;;
            05_sales)
                table_name="sales_${table_base}"
                ;;
            06_support)
                table_name="support_${table_base}"
                ;;
            07_compliance)
                table_name="compliance_${table_base}"
                ;;
            08_integration)
                table_name="integration_${table_base}"
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
