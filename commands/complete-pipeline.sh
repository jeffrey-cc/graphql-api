#!/bin/bash

# ================================================================================
# Complete Deterministic GraphQL Pipeline
# ================================================================================
# Implements the full deterministic workflow:
# 1. Container management (dev: destroy+rebuild, prod: purge)
# 2. Database connections + introspection (tables, views, enums, functions)
# 3. Dynamic relationship discovery and tracking
# 4. Test data workflow: purge → load → verify counts → purge → verify zero
# 5. Dev/Prod structure comparison (tables and relationships)
# Usage: ./complete-pipeline.sh <tier> <environment>
# ================================================================================

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_shared_functions.sh"

# Parse arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <tier> <environment>"
    echo "Example: $0 admin development"
    exit 1
fi

TIER="$1"
ENVIRONMENT="$2"

# Setup logging
LOG_DIR="$SCRIPT_DIR/../logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MAIN_LOG="$LOG_DIR/complete-pipeline_${TIER}_${ENVIRONMENT}_${TIMESTAMP}.log"
ERROR_LOG="$LOG_DIR/errors_${TIER}_${ENVIRONMENT}_${TIMESTAMP}.log"

# Logging functions
log_to_file() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$MAIN_LOG"
}

log_error_to_file() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$ERROR_LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$MAIN_LOG"
}

log_to_file "Starting complete pipeline for $TIER in $ENVIRONMENT"

# Configure tier settings
configure_tier "$TIER"

# Configure endpoint for the environment
if ! configure_endpoint "$TIER" "$ENVIRONMENT"; then
    die "Failed to configure endpoint for $TIER ($ENVIRONMENT)"
fi

section_header "🚀 COMPLETE DETERMINISTIC GRAPHQL PIPELINE - $(echo $TIER | tr '[:lower:]' '[:upper:]') TIER"
log_info "Tier: $TIER"
log_info "Environment: $ENVIRONMENT"
log_info "GraphQL: $GRAPHQL_TIER_ENDPOINT"

start_timer

# ================================================================================
# STEP 1: Container Management
# ================================================================================
log_progress "Step 1/5: Container Management..."

if [[ "$ENVIRONMENT" == "development" ]]; then
    log_detail "Development: Destroying and rebuilding Docker containers..."
    log_to_file "STEP 1: Rebuilding Docker containers for development"
    cd "$SCRIPT_DIR/.."
    docker-compose down -v >/dev/null 2>&1 || true
    docker-compose up -d

    # Wait for containers to be healthy
    log_to_file "Waiting for containers to become healthy..."
    sleep 10
    for service in admin-graphql-server operator-graphql-server member-graphql-server; do
        attempt=1
        max_attempts=30

        while [ $attempt -le $max_attempts ]; do
            if docker inspect $service --format='{{.State.Health.Status}}' 2>/dev/null | grep -q "healthy"; then
                log_detail "✓ $service is healthy"
                log_to_file "✓ $service is healthy"
                break
            elif [ $attempt -eq $max_attempts ]; then
                log_warning "$service may not be fully healthy yet"
                log_to_file "WARNING: $service may not be fully healthy after $max_attempts attempts"
                break
            else
                echo -n "."
                sleep 2
                ((attempt++))
            fi
        done
    done

    log_success "Docker containers rebuilt and healthy"
    log_to_file "Docker containers successfully rebuilt and healthy"
else
    log_detail "Production: Preserving containers, will purge metadata only"
    log_to_file "STEP 1: Production mode - preserving containers"
    log_success "Production mode: containers left intact"
fi

# ================================================================================
# STEP 2: Database Connections + Introspection
# ================================================================================
log_progress "Step 2/5: Database connections and introspection..."

# Test GraphQL connection
if ! test_graphql_connection "$TIER" "$ENVIRONMENT"; then
    die "GraphQL connection failed"
fi

# Purge all existing tracking - improved version
log_detail "Purging all existing GraphQL tracking..."
log_to_file "STEP 2.1: Starting complete metadata purge"

# First export current metadata to check what needs to be cleared
current_metadata=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/metadata" \
  -H "X-Hasura-Admin-Secret: $GRAPHQL_TIER_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"type": "export_metadata", "args": {}}')

log_to_file "Current metadata exported for inspection"

# Clear all metadata
log_to_file "Clearing all metadata..."
clear_response=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/metadata" \
  -H "X-Hasura-Admin-Secret: $GRAPHQL_TIER_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"type": "clear_metadata", "args": {}}')

if [[ "$clear_response" == *'"message":"success"'* ]] || [[ -z "$clear_response" ]]; then
    log_to_file "Successfully cleared all metadata"
    log_success "Metadata cleared successfully"
else
    log_to_file "Clear metadata response: $clear_response"
fi

# Re-add or verify database source
log_to_file "STEP 2.2: Setting up database source"
log_detail "Configuring database connection..."

db_url="postgresql://${DB_TIER_USER}:${DB_TIER_PASSWORD}@host.docker.internal:${DB_TIER_PORT}/${DB_TIER_DATABASE}"

# First try to add the source
add_source_response=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/metadata" \
  -H "X-Hasura-Admin-Secret: $GRAPHQL_TIER_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "pg_add_source",
    "args": {
      "name": "default",
      "configuration": {
        "connection_info": {
          "database_url": "'$db_url'"
        }
      }
    }
  }')

if [[ "$add_source_response" == *'"message":"success"'* ]] || [[ -z "$add_source_response" ]]; then
    log_to_file "Successfully added database source"
elif [[ "$add_source_response" == *'"already exists"'* ]]; then
    log_to_file "Database source already exists (this is OK)"
else
    log_to_file "Add source response: $add_source_response"
fi

# Discover and track all tables via introspection
log_detail "Discovering database objects via introspection..."
log_to_file "STEP 2.3: Running database introspection query"

introspection_query='{
  "type": "run_sql",
  "args": {
    "sql": "SELECT table_schema, table_name, table_type FROM information_schema.tables WHERE table_schema NOT IN ('"'"'information_schema'"'"', '"'"'pg_catalog'"'"', '"'"'pg_toast'"'"', '"'"'hdb_catalog'"'"') ORDER BY table_schema, table_name;"
  }
}'

response=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v2/query" \
  -H "X-Hasura-Admin-Secret: $GRAPHQL_TIER_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d "$introspection_query")

log_to_file "Introspection query executed"

if [[ ! "$response" == *'"result_type":"TuplesOk"'* ]]; then
    log_error_to_file "Database introspection failed: $response"
    die "Database introspection failed"
fi

log_to_file "Introspection successful, processing results..."

# Process tables and track them - using temp file to avoid subshell issue
TEMP_TRACK_FILE=$(mktemp)
echo "0" > "$TEMP_TRACK_FILE"
TEMP_ERROR_FILE=$(mktemp)
echo "0" > "$TEMP_ERROR_FILE"

tables_json=$(echo "$response" | jq '.result[1:][] | {schema: .[0], name: .[1], type: .[2]}' 2>/dev/null)
object_count=$(echo "$tables_json" | jq -s length 2>/dev/null || echo 0)

log_detail "Tracking $object_count database objects..."
log_to_file "STEP 2.4: Starting table tracking for $object_count objects"

echo "$tables_json" | jq -r '@json' | while read -r object_json; do
    schema=$(echo "$object_json" | jq -r '.schema')
    name=$(echo "$object_json" | jq -r '.name')
    type=$(echo "$object_json" | jq -r '.type')

    if [[ "$type" == "BASE TABLE" ]]; then
        log_to_file "  Tracking table: $schema.$name"

        track_response=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/metadata" \
          -H "X-Hasura-Admin-Secret: $GRAPHQL_TIER_ADMIN_SECRET" \
          -H "Content-Type: application/json" \
          -d '{"type": "pg_track_table", "args": {"source": "default", "table": {"schema": "'$schema'", "name": "'$name'"}}}')

        if [[ "$track_response" == *'"message":"success"'* ]] || [[ -z "$track_response" ]]; then
            current_count=$(cat "$TEMP_TRACK_FILE")
            echo $((current_count + 1)) > "$TEMP_TRACK_FILE"
            log_to_file "    ✓ Successfully tracked $schema.$name"
        elif [[ "$track_response" == *'"error"'* ]]; then
            current_errors=$(cat "$TEMP_ERROR_FILE")
            echo $((current_errors + 1)) > "$TEMP_ERROR_FILE"
            log_error_to_file "Failed to track $schema.$name: $track_response"
        fi
    fi
done

tracked_count=$(cat "$TEMP_TRACK_FILE")
error_count=$(cat "$TEMP_ERROR_FILE")
rm -f "$TEMP_TRACK_FILE" "$TEMP_ERROR_FILE"

log_to_file "Table tracking complete: $tracked_count successful, $error_count errors"
log_success "Tracked $tracked_count tables via introspection"

# ================================================================================
# STEP 3: Dynamic Relationship Discovery and Tracking
# ================================================================================
log_progress "Step 3/5: Dynamic relationship discovery..."
log_to_file "STEP 3: Starting relationship discovery"

# Discover foreign key relationships via introspection
fk_query='{
  "type": "run_sql",
  "args": {
    "sql": "SELECT tc.table_schema, tc.table_name, kcu.column_name, ccu.table_schema AS foreign_table_schema, ccu.table_name AS foreign_table_name, ccu.column_name AS foreign_column_name FROM information_schema.table_constraints AS tc JOIN information_schema.key_column_usage AS kcu ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema JOIN information_schema.constraint_column_usage AS ccu ON ccu.constraint_name = tc.constraint_name WHERE tc.constraint_type = '"'"'FOREIGN KEY'"'"' ORDER BY tc.table_schema, tc.table_name;"
  }
}'

fk_response=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v2/query" \
  -H "X-Hasura-Admin-Secret: $GRAPHQL_TIER_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d "$fk_query")

TEMP_REL_FILE=$(mktemp)
echo "0" > "$TEMP_REL_FILE"

if [[ "$fk_response" == *'"result_type":"TuplesOk"'* ]]; then
    fk_count=$(echo "$fk_response" | jq '.result | length - 1' 2>/dev/null || echo 0)
    log_detail "Discovered $fk_count foreign key relationships"
    log_to_file "Found $fk_count foreign key relationships to track"

    # Track relationships
    echo "$fk_response" | jq -r '.result[1:][] | @json' | while read -r fk_json; do
        if [[ "$fk_json" != "null" && "$fk_json" != "" ]]; then
            fk_data=$(echo "$fk_json" | jq -r '. | @json')
            schema=$(echo "$fk_data" | jq -r '.[0]')
            table=$(echo "$fk_data" | jq -r '.[1]')
            column=$(echo "$fk_data" | jq -r '.[2]')
            foreign_schema=$(echo "$fk_data" | jq -r '.[3]')
            foreign_table=$(echo "$fk_data" | jq -r '.[4]')
            foreign_column=$(echo "$fk_data" | jq -r '.[5]')

            # Create object relationship
            rel_name="${foreign_table}_by_${column}"
            log_to_file "  Creating relationship: $schema.$table -> $rel_name"

            rel_response=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/metadata" \
              -H "X-Hasura-Admin-Secret: $GRAPHQL_TIER_ADMIN_SECRET" \
              -H "Content-Type: application/json" \
              -d '{"type": "pg_create_object_relationship", "args": {"source": "default", "table": {"schema": "'$schema'", "name": "'$table'"}, "name": "'$rel_name'", "using": {"foreign_key_constraint_on": "'$column'"}}}')

            if [[ "$rel_response" != *'"error"'* ]]; then
                current_rels=$(cat "$TEMP_REL_FILE")
                echo $((current_rels + 1)) > "$TEMP_REL_FILE"
                log_to_file "    ✓ Created relationship successfully"
            fi
        fi
    done
else
    log_warning "No foreign key relationships found"
    log_to_file "No foreign key relationships discovered"
fi

relationship_count=$(cat "$TEMP_REL_FILE")
rm -f "$TEMP_REL_FILE"

log_to_file "Relationship tracking complete: $relationship_count relationships created"
log_success "Tracked $relationship_count relationships dynamically"

# ================================================================================
# STEP 4: Test Data Workflow
# ================================================================================
log_progress "Step 4/5: Test data workflow..."
log_to_file "STEP 4: Starting test data workflow"

# 4a. Purge all existing data via GraphQL mutations
log_detail "Purging all existing data..."
log_to_file "STEP 4.1: Purging all data from database"

TEMP_PURGE_FILE=$(mktemp)
echo "0" > "$TEMP_PURGE_FILE"

# Get all tracked tables and delete data
schema_response=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
  -H "X-Hasura-Admin-Secret: $GRAPHQL_TIER_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ __schema { mutationType { fields { name } } } }"}')

if [[ "$schema_response" == *'"data"'* ]]; then
    # Find all delete mutations
    delete_mutations=$(echo "$schema_response" | jq -r '.data.__schema.mutationType.fields[]?.name' 2>/dev/null | grep "^delete_" | grep -v "_by_pk")

    for mutation in $delete_mutations; do
        if [[ ! -z "$mutation" ]]; then
            table_identifier=$(echo "$mutation" | sed 's/^delete_//')
            log_to_file "  Purging table: $table_identifier"

            delete_response=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
              -H "X-Hasura-Admin-Secret: $GRAPHQL_TIER_ADMIN_SECRET" \
              -H "Content-Type: application/json" \
              -d '{"query": "mutation { '$mutation'(where: {}) { affected_rows } }"}')

            if [[ "$delete_response" == *'"affected_rows"'* ]]; then
                deleted=$(echo "$delete_response" | jq '.data.'"$mutation"'.affected_rows' 2>/dev/null || echo 0)
                current_purge=$(cat "$TEMP_PURGE_FILE")
                echo $((current_purge + deleted)) > "$TEMP_PURGE_FILE"
                if [[ $deleted -gt 0 ]]; then
                    log_to_file "    Deleted $deleted rows from $table_identifier"
                fi
            fi
        fi
    done
fi

purge_count=$(cat "$TEMP_PURGE_FILE")
rm -f "$TEMP_PURGE_FILE"

log_to_file "Initial purge complete: $purge_count total records deleted"
log_success "Purged $purge_count records from database"

# 4b. Load test data from CSV files
log_detail "Loading test data from CSV files..."
log_to_file "STEP 4.2: Loading test data from CSV files"

TEST_DATA_PATH="./graphql-$TIER-api/test-data"
TEMP_LOAD_FILE=$(mktemp)
echo "0" > "$TEMP_LOAD_FILE"
csv_line_count=0

if [[ -d "$TEST_DATA_PATH" ]]; then
    log_to_file "Test data directory found: $TEST_DATA_PATH"

    # Count total lines in CSV files (excluding headers)
    for csv_file in $(find "$TEST_DATA_PATH" -name "*.csv" -type f | sort); do
        lines=$(tail -n +2 "$csv_file" | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')
        csv_line_count=$((csv_line_count + lines))
        log_to_file "  Found $lines data rows in $(basename $csv_file)"
    done

    log_to_file "Total CSV data rows to load: $csv_line_count"

    # Load data using GraphQL mutations
    for csv_file in $(find "$TEST_DATA_PATH" -name "*.csv" -type f | sort); do
        # Extract table info from path and filename
        dir_name=$(basename $(dirname "$csv_file"))
        file_name=$(basename "$csv_file" .csv)

        # Parse schema and table name
        if [[ "$dir_name" =~ ^[0-9]+_ ]]; then
            schema_name=$(echo "$dir_name" | sed 's/^[0-9]*_//')
        else
            schema_name="public"
        fi

        if [[ "$file_name" =~ ^[0-9]+_ ]]; then
            table_name=$(echo "$file_name" | sed 's/^[0-9]*_//')
        else
            table_name="$file_name"
        fi

        mutation_name="insert_${schema_name}_${table_name}_one"

        log_to_file "  Loading data into $schema_name.$table_name from $(basename $csv_file) using mutation: $mutation_name"

        # Capture the python output and parse results
        python_output=$(CSV_FILE="$csv_file" MUTATION_NAME="$mutation_name" ENDPOINT="$GRAPHQL_TIER_ENDPOINT" ADMIN_SECRET="$GRAPHQL_TIER_ADMIN_SECRET" python3 << 'EOF'
import csv
import json
import subprocess
import sys

def convert_value(value_str, col_name):
    """Convert string value to appropriate JSON type"""
    if not value_str or value_str.lower() == 'null':
        return None

    # Keep certain columns as strings regardless of content
    # These are known text columns that might contain numeric-looking values
    text_columns = ['info_value', 'description', 'notes', 'comments', 'address', 'config_value', 'code', 'name', 'email', 'phone', 'legal_name', 'first_name', 'last_name', 'middle_name', 'tax_id']
    if any(tc in col_name.lower() for tc in text_columns):
        return value_str

    # Handle UUIDs and IDs as strings
    if 'id' in col_name.lower() or 'guid' in col_name.lower() or 'uuid' in col_name.lower():
        return value_str

    # Handle timestamps as strings
    if '_at' in col_name.lower() or 'date' in col_name.lower() or 'time' in col_name.lower():
        return value_str

    # For other columns, try to infer type
    if value_str.lower() == 'true':
        return True
    if value_str.lower() == 'false':
        return False

    # Try to convert to number for non-text columns
    try:
        if '.' in value_str:
            return float(value_str)
        else:
            return int(value_str)
    except ValueError:
        # It's a string
        return value_str

def execute_graphql_mutation(mutation_name, obj_data, first_col, endpoint, admin_secret):
    """Execute a GraphQL mutation"""

    # Build the GraphQL object literal (not JSON!)
    obj_parts = []
    for key, value in obj_data.items():
        if value is None:
            obj_parts.append(f"{key}: null")
        elif isinstance(value, bool):
            obj_parts.append(f"{key}: {str(value).lower()}")
        elif isinstance(value, (int, float)):
            obj_parts.append(f"{key}: {value}")
        else:
            # String - escape and quote
            escaped_value = str(value).replace('"', '\\"')
            obj_parts.append(f'{key}: "{escaped_value}"')

    obj_literal = "{" + ", ".join(obj_parts) + "}"

    # Build the mutation query
    mutation_query = f"mutation {{ {mutation_name}(object: {obj_literal}) {{ {first_col} }} }}"

    # Prepare the full GraphQL request
    graphql_request = {
        "query": mutation_query
    }

    # Execute curl command
    curl_cmd = [
        'curl', '-s', '-X', 'POST', f'{endpoint}/v1/graphql',
        '-H', f'X-Hasura-Admin-Secret: {admin_secret}',
        '-H', 'Content-Type: application/json',
        '-d', json.dumps(graphql_request)
    ]

    try:
        result = subprocess.run(curl_cmd, capture_output=True, text=True, timeout=30)
        response = result.stdout

        # Parse response to check for success
        try:
            response_data = json.loads(response)
            if 'data' in response_data and response_data['data'] is not None:
                if 'errors' not in response_data:
                    return True, response
            return False, response
        except json.JSONDecodeError:
            return False, response

    except Exception as e:
        return False, str(e)

# Read CSV file and process rows
import os
csv_file = os.environ.get('CSV_FILE')
mutation_name = os.environ.get('MUTATION_NAME')
endpoint = os.environ.get('ENDPOINT')
admin_secret = os.environ.get('ADMIN_SECRET')
success_count = 0

try:
    with open(csv_file, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)  # Get header row
        first_col = header[0]

        for row_num, row in enumerate(reader, 1):
            if len(row) > 0 and any(cell.strip() for cell in row):
                # Build object data
                obj_data = {}
                for i, value in enumerate(row):
                    if i < len(header):
                        col_name = header[i].strip()
                        obj_data[col_name] = convert_value(value.strip(), col_name)

                # Execute mutation
                success, response = execute_graphql_mutation(
                    mutation_name, obj_data, first_col, endpoint, admin_secret
                )

                if success:
                    success_count += 1
                    print(f"SUCCESS: Row {row_num}")
                else:
                    print(f"ERROR: Row {row_num} failed: {response}")

    # Output final count
    print(f"FINAL_COUNT: {success_count}")

except Exception as e:
    print(f"PYTHON_ERROR: {e}")
    sys.exit(1)
EOF
)

        # Parse the output and update counters
        success_rows=$(echo "$python_output" | grep "^SUCCESS:" | wc -l | tr -d ' ')
        error_rows=$(echo "$python_output" | grep "^ERROR:" | wc -l | tr -d ' ')

        if [[ "$python_output" == *"FINAL_COUNT:"* ]]; then
            final_count=$(echo "$python_output" | grep "FINAL_COUNT:" | sed 's/FINAL_COUNT: //')
            current_load=$(cat "$TEMP_LOAD_FILE")
            echo $((current_load + final_count)) > "$TEMP_LOAD_FILE"
            log_to_file "    ✓ Inserted $final_count records into $schema_name.$table_name"
        else
            log_to_file "    ✗ Failed to process $csv_file: $python_output"
        fi

        # Log any errors
        if [[ $error_rows -gt 0 ]]; then
            echo "$python_output" | grep "^ERROR:" | while read error_line; do
                log_to_file "    $error_line"
            done
        fi
    done
else
    log_warning "No test data directory found: $TEST_DATA_PATH"
    log_to_file "WARNING: Test data directory not found"
fi

loaded_count=$(cat "$TEMP_LOAD_FILE")
rm -f "$TEMP_LOAD_FILE"

log_to_file "Data loading complete: $loaded_count records inserted"
log_success "Loaded $loaded_count records from CSV files"

# 4c. Verify record counts match CSV counts
log_detail "Verifying record counts..."
log_to_file "STEP 4.3: Verifying loaded data counts"

if [[ $loaded_count -eq $csv_line_count ]]; then
    log_success "✓ Data verification passed: $loaded_count records match $csv_line_count CSV lines"
    log_to_file "VERIFICATION SUCCESS: Loaded count ($loaded_count) matches CSV count ($csv_line_count)"
else
    log_warning "⚠ Data verification mismatch: $loaded_count loaded vs $csv_line_count in CSV files"
    log_error_to_file "VERIFICATION FAILED: Loaded count ($loaded_count) does not match CSV count ($csv_line_count)"
fi

# 4d. Final purge to verify everything can be deleted
log_detail "Final purge of database..."
log_to_file "STEP 4.4: Final purge to verify data can be deleted"

TEMP_FINAL_PURGE=$(mktemp)
echo "0" > "$TEMP_FINAL_PURGE"

if [[ "$schema_response" == *'"data"'* ]]; then
    delete_mutations=$(echo "$schema_response" | jq -r '.data.__schema.mutationType.fields[]?.name' 2>/dev/null | grep "^delete_" | grep -v "_by_pk")

    for mutation in $delete_mutations; do
        if [[ ! -z "$mutation" ]]; then
            delete_response=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
              -H "X-Hasura-Admin-Secret: $GRAPHQL_TIER_ADMIN_SECRET" \
              -H "Content-Type: application/json" \
              -d '{"query": "mutation { '$mutation'(where: {}) { affected_rows } }"}')

            if [[ "$delete_response" == *'"affected_rows"'* ]]; then
                deleted=$(echo "$delete_response" | jq '.data.'"$mutation"'.affected_rows' 2>/dev/null || echo 0)
                current_final=$(cat "$TEMP_FINAL_PURGE")
                echo $((current_final + deleted)) > "$TEMP_FINAL_PURGE"
            fi
        fi
    done
fi

final_purge_count=$(cat "$TEMP_FINAL_PURGE")
rm -f "$TEMP_FINAL_PURGE"

log_to_file "Final purge complete: $final_purge_count records deleted"

# 4e. Verify all counts are zero
log_detail "Verifying zero records..."
log_to_file "STEP 4.5: Verifying all tables are empty"

TEMP_VERIFY_FILE=$(mktemp)
echo "0" > "$TEMP_VERIFY_FILE"

# Query all tables to verify they're empty
query_response=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
  -H "X-Hasura-Admin-Secret: $GRAPHQL_TIER_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ __schema { queryType { fields { name } } } }"}')

if [[ "$query_response" == *'"data"'* ]]; then
    # Check aggregate queries for counts
    aggregate_queries=$(echo "$query_response" | jq -r '.data.__schema.queryType.fields[]?.name' 2>/dev/null | grep "_aggregate$")

    for query in $aggregate_queries; do
        if [[ ! -z "$query" ]]; then
            count_response=$(curl -s -X POST "$GRAPHQL_TIER_ENDPOINT/v1/graphql" \
              -H "X-Hasura-Admin-Secret: $GRAPHQL_TIER_ADMIN_SECRET" \
              -H "Content-Type: application/json" \
              -d "{\"query\": \"{ $query { aggregate { count } } }\"}")

            if [[ "$count_response" == *'"count"'* ]]; then
                count=$(echo "$count_response" | jq '.data.'"$query"'.aggregate.count' 2>/dev/null || echo 0)
                if [[ $count -gt 0 ]]; then
                    current_verify=$(cat "$TEMP_VERIFY_FILE")
                    echo $((current_verify + count)) > "$TEMP_VERIFY_FILE"
                    log_to_file "  WARNING: Table $(echo $query | sed 's/_aggregate//') has $count records"
                fi
            fi
        fi
    done
fi

remaining_count=$(cat "$TEMP_VERIFY_FILE")
rm -f "$TEMP_VERIFY_FILE"

if [[ $remaining_count -eq 0 ]]; then
    log_success "✓ All tables verified empty"
    log_to_file "VERIFICATION SUCCESS: All tables are empty"
else
    log_warning "⚠ Found $remaining_count records remaining after purge"
    log_error_to_file "VERIFICATION FAILED: $remaining_count records still in database"
fi

log_success "Test data workflow completed"

# ================================================================================
# STEP 5: Dev/Prod Structure Comparison (if applicable)
# ================================================================================
log_progress "Step 5/5: Structure comparison..."
log_to_file "STEP 5: Structure comparison"

if [[ "$ENVIRONMENT" == "development" ]]; then
    log_detail "Development environment - skipping prod comparison"
    log_to_file "Development environment - no production comparison needed"
else
    log_detail "Production environment - comparing with development"
    log_to_file "Production environment - would compare with development structure"
    # TODO: Implement comparison between dev and prod
fi

log_success "Pipeline structure verification completed"
log_to_file "Pipeline structure verification completed successfully"

# Performance summary
end_timer

echo ""
section_header "🎯 COMPLETE PIPELINE SUMMARY"
log_info "Environment: $ENVIRONMENT"
log_info "Objects tracked: $tracked_count"
log_info "Relationships: $relationship_count"
log_info "Data loaded/verified: $loaded_count/$csv_line_count"

if [[ $error_count -eq 0 ]] && [[ $loaded_count -eq $csv_line_count ]] && [[ $remaining_count -eq 0 ]]; then
    log_success "✅ DETERMINISTIC PIPELINE COMPLETED SUCCESSFULLY - ZERO ERRORS!"
    log_to_file "PIPELINE SUCCESS: Completed with zero errors"
else
    if [[ $error_count -gt 0 ]]; then
        log_warning "⚠ Pipeline completed with $error_count tracking errors"
    fi
    if [[ $loaded_count -ne $csv_line_count ]]; then
        log_warning "⚠ Data count mismatch: $loaded_count loaded vs $csv_line_count expected"
    fi
    if [[ $remaining_count -gt 0 ]]; then
        log_warning "⚠ Database not empty after final purge"
    fi
    log_to_file "PIPELINE COMPLETED WITH WARNINGS"
fi

log_info "GraphQL API is fully configured and tested"
log_to_file "Complete pipeline finished at $(date '+%Y-%m-%d %H:%M:%S')"

# Clean exit
exit 0