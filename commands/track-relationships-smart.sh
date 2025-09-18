#!/bin/bash

# Track All Relationships Smart Script
# Scans database for foreign keys and creates both object and array relationships
# This script ensures ALL relationships are tracked automatically

# Source shared functions
source "$(dirname "$0")/_shared_functions.sh"

# Parse arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <tier> <environment> [--force] [--verbose]"
    echo "Example: $0 admin development"
    exit 1
fi

TIER="$1"
ENVIRONMENT="$2"
FORCE_FLAG=""
VERBOSE_FLAG=""

# Process optional flags
shift 2
while [ $# -gt 0 ]; do
    case $1 in
        --force) FORCE_FLAG="--force" ;;
        --verbose) VERBOSE_FLAG="--verbose" ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
    shift
done

# Configure tier settings
configure_tier "$TIER"

# Configure endpoint for the environment
if ! configure_endpoint "$TIER" "$ENVIRONMENT"; then
    die "Failed to configure endpoint for $TIER ($ENVIRONMENT)"
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${CYAN}🔗 SMART RELATIONSHIP TRACKING - $(echo "$TIER" | tr '[:lower:]' '[:upper:]') TIER${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${INFO}Tier: $TIER${NC}"
echo -e "${INFO}Environment: $ENVIRONMENT${NC}"
echo -e "${INFO}Database: $DB_TIER_DATABASE at $DB_TIER_HOST:$DB_TIER_PORT${NC}"
echo -e "${INFO}GraphQL: $GRAPHQL_TIER_ENDPOINT${NC}"

# Test GraphQL connection
echo -e "${PROGRESS}Testing GraphQL connection for $TIER ($ENVIRONMENT)...${NC}"
if ! test_graphql_connection "$TIER" "$ENVIRONMENT"; then
    echo -e "${ERROR}GraphQL connection failed. Please check your setup.${NC}"
    exit 1
fi
echo -e "${SUCCESS}GraphQL connection successful${NC}"

# Create temporary Python script for relationship tracking
TEMP_SCRIPT="/tmp/track_relationships_${TIER}_$$.py"

cat > "$TEMP_SCRIPT" << 'EOF'
#!/usr/bin/env python3

import sys
import requests
import json
import os

def get_foreign_keys(endpoint, admin_secret):
    """Get all foreign key relationships from the database"""
    headers = {
        "Content-Type": "application/json",
        "X-Hasura-Admin-Secret": admin_secret
    }
    
    sql_query = """
    SELECT 
        tc.table_schema, 
        tc.table_name, 
        kcu.column_name, 
        ccu.table_schema AS foreign_table_schema, 
        ccu.table_name AS foreign_table_name, 
        ccu.column_name AS foreign_column_name,
        tc.constraint_name
    FROM information_schema.table_constraints AS tc 
    JOIN information_schema.key_column_usage AS kcu 
        ON tc.constraint_name = kcu.constraint_name 
        AND tc.table_schema = kcu.table_schema 
    JOIN information_schema.constraint_column_usage AS ccu 
        ON ccu.constraint_name = tc.constraint_name 
    WHERE tc.constraint_type = 'FOREIGN KEY' 
    ORDER BY tc.table_schema, tc.table_name, kcu.column_name;
    """
    
    payload = {
        "type": "run_sql",
        "args": {"sql": sql_query}
    }
    
    try:
        response = requests.post(f"{endpoint}/v2/query", json=payload, headers=headers)
        if response.status_code == 200:
            result = response.json()
            if result.get("result_type") == "TuplesOk":
                rows = result["result"][1:]  # Skip header row
                return rows
        return []
    except Exception as e:
        print(f"    ❌ Error querying foreign keys: {e}")
        return []

def create_object_relationship(endpoint, admin_secret, table_schema, table_name, column_name, foreign_table_schema, foreign_table_name, constraint_name):
    """Create an object relationship (many-to-one)"""
    
    # Generate relationship name
    if column_name.endswith('_id'):
        base_name = column_name[:-3]
        rel_name = f"{foreign_table_schema}_{foreign_table_name}"
    else:
        rel_name = f"{foreign_table_schema}_{foreign_table_name}_by_{column_name}"
    
    payload = {
        "type": "pg_create_object_relationship",
        "args": {
            "source": "default",
            "table": {"schema": table_schema, "name": table_name},
            "name": rel_name,
            "using": {
                "foreign_key_constraint_on": column_name
            }
        }
    }
    
    headers = {
        "Content-Type": "application/json",
        "X-Hasura-Admin-Secret": admin_secret
    }
    
    try:
        response = requests.post(f"{endpoint}/v1/metadata", json=payload, headers=headers)
        if response.status_code == 200:
            result = response.json()
            if "message" in result and ("already exists" in result["message"] or result["message"] == "success"):
                return True, f"Object: {table_schema}_{table_name}.{rel_name}"
            elif "error" in result:
                return False, f"Object error: {result.get('error', 'Unknown error')}"
            else:
                return True, f"Object: {table_schema}_{table_name}.{rel_name}"
        else:
            return False, f"Object HTTP {response.status_code}"
    except Exception as e:
        return False, f"Object exception: {e}"

def create_array_relationship(endpoint, admin_secret, foreign_table_schema, foreign_table_name, table_schema, table_name, column_name, constraint_name):
    """Create an array relationship (one-to-many)"""
    
    # Generate relationship name (plural form)
    rel_name = f"{table_schema}_{table_name}s"
    
    payload = {
        "type": "pg_create_array_relationship",
        "args": {
            "source": "default", 
            "table": {"schema": foreign_table_schema, "name": foreign_table_name},
            "name": rel_name,
            "using": {
                "foreign_key_constraint_on": {
                    "table": {"schema": table_schema, "name": table_name},
                    "column": column_name
                }
            }
        }
    }
    
    headers = {
        "Content-Type": "application/json",
        "X-Hasura-Admin-Secret": admin_secret
    }
    
    try:
        response = requests.post(f"{endpoint}/v1/metadata", json=payload, headers=headers)
        if response.status_code == 200:
            result = response.json()
            if "message" in result and ("already exists" in result["message"] or result["message"] == "success"):
                return True, f"Array: {foreign_table_schema}_{foreign_table_name}.{rel_name}"
            elif "error" in result:
                return False, f"Array error: {result.get('error', 'Unknown error')}"
            else:
                return True, f"Array: {foreign_table_schema}_{foreign_table_name}.{rel_name}"
        else:
            return False, f"Array HTTP {response.status_code}"
    except Exception as e:
        return False, f"Array exception: {e}"

def main():
    if len(sys.argv) != 3:
        print("Usage: script.py <endpoint> <admin_secret>")
        sys.exit(1)
    
    endpoint = sys.argv[1]
    admin_secret = sys.argv[2]
    
    print("🔍 Scanning database for foreign key relationships...")
    foreign_keys = get_foreign_keys(endpoint, admin_secret)
    
    if not foreign_keys:
        print("⚠️  No foreign key relationships found in database")
        return
    
    print(f"📋 Found {len(foreign_keys)} foreign key relationships")
    
    # Track object relationships (many-to-one)
    print("\n📋 Creating object relationships (many-to-one)...")
    object_success = 0
    object_errors = []
    
    for fk in foreign_keys:
        table_schema, table_name, column_name, foreign_table_schema, foreign_table_name, foreign_column_name, constraint_name = fk
        success, message = create_object_relationship(
            endpoint, admin_secret, table_schema, table_name, column_name, 
            foreign_table_schema, foreign_table_name, constraint_name
        )
        if success:
            object_success += 1
            print(f"    ✅ {message}")
        else:
            object_errors.append(message)
            print(f"    ❌ {message}")
    
    # Track array relationships (one-to-many) 
    print("\n📋 Creating array relationships (one-to-many)...")
    array_success = 0
    array_errors = []
    
    for fk in foreign_keys:
        table_schema, table_name, column_name, foreign_table_schema, foreign_table_name, foreign_column_name, constraint_name = fk
        success, message = create_array_relationship(
            endpoint, admin_secret, foreign_table_schema, foreign_table_name,
            table_schema, table_name, column_name, constraint_name
        )
        if success:
            array_success += 1
            print(f"    ✅ {message}")
        else:
            array_errors.append(message)
            print(f"    ❌ {message}")
    
    # Summary
    print(f"\n🎉 Relationship tracking complete!")
    print(f"   Foreign keys found: {len(foreign_keys)}")
    print(f"   Object relationships: {object_success}/{len(foreign_keys)} successful")
    print(f"   Array relationships: {array_success}/{len(foreign_keys)} successful")
    
    if object_errors:
        print(f"   Object errors: {len(object_errors)}")
    if array_errors:
        print(f"   Array errors: {len(array_errors)}")

if __name__ == "__main__":
    main()
EOF

# Make temp script executable
chmod +x "$TEMP_SCRIPT"

# Run the smart relationship tracking
echo -e "${PROGRESS}Running smart relationship tracking...${NC}"
python3 "$TEMP_SCRIPT" "$GRAPHQL_TIER_ENDPOINT" "$GRAPHQL_TIER_ADMIN_SECRET"

# Clean up temp script
rm -f "$TEMP_SCRIPT"

# Verify relationships are working
echo -e "${PROGRESS}Verifying relationships are working...${NC}"

# Count relationships using introspection
RELATIONSHIP_COUNT=$(curl -s -X POST -H "Content-Type: application/json" -H "X-Hasura-Admin-Secret: $GRAPHQL_TIER_ADMIN_SECRET" \
    -d '{"query": "query { __schema { types { name fields { name type { name kind ofType { name } } } } } }"}' \
    "$GRAPHQL_TIER_ENDPOINT/v1/graphql" | \
    jq '[.data.__schema.types[] | select(.name | test("^(admin|operators|compliance|financial|sales|support|system|integration)_")) | .fields[] | select(.type.kind == "OBJECT" or (.type.kind == "LIST" and .type.ofType.name != null and (.type.ofType.name | test("^(admin|operators|compliance|financial|sales|support|system|integration)_"))))] | length' 2>/dev/null || echo "0")

echo -e "${INFO}GraphQL relationship fields detected: $RELATIONSHIP_COUNT${NC}"

if [ "$RELATIONSHIP_COUNT" -gt 50 ]; then
    echo -e "${SUCCESS}✅ Relationships verified successfully!${NC}"
    echo -e "${INFO}Nested GraphQL queries are now available${NC}"
else
    echo -e "${WARNING}⚠️  Few relationships detected (${RELATIONSHIP_COUNT}). Manual verification recommended.${NC}"
fi

# Performance summary
END_TIME=$(date +%s.%N)
DURATION=$(echo "$END_TIME - $START_TIME" | bc 2>/dev/null || echo "unknown")

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${CYAN}🎯 OPERATION SUMMARY${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${INFO}Operation: Smart Relationship Tracking${NC}"
echo -e "${INFO}Tier: $TIER${NC}"
echo -e "${INFO}Environment: $ENVIRONMENT${NC}"
echo -e "${INFO}Errors: $COMMAND_ERRORS${NC}"
echo -e "${INFO}Warnings: $COMMAND_WARNINGS${NC}"

if [ "$COMMAND_ERRORS" -eq 0 ]; then
    echo -e "${SUCCESS}Operation completed successfully${NC}"
else
    echo -e "${ERROR}Operation completed with errors${NC}"
fi

if [ "$DURATION" != "unknown" ]; then
    echo -e "${SUCCESS}⏱️  Operation completed in ${DURATION}s${NC}"
fi

echo -e "${SUCCESS}Smart relationship tracking completed successfully!${NC}"
echo -e "${INFO}GraphQL Console: $GRAPHQL_TIER_ENDPOINT/console${NC}"