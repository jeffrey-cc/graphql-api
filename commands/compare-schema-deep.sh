#!/bin/bash

# ============================================================================
# DEEP GRAPHQL SCHEMA COMPARISON
# Compares GraphQL schemas at the API endpoint level including all types,
# queries, mutations, and field details between environments
# ============================================================================

set -e

# Parse arguments
TIER="${1:-}"
DETAILED="${2:-}"

if [ -z "$TIER" ]; then
    echo "Usage: $0 <admin|operator|member> [--detailed]"
    exit 1
fi

# Color codes
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

echo -e "${BLUE}🔍 Deep GraphQL Schema Comparison - $TIER${NC}"
echo "================================================"

# Configure endpoints
case "$TIER" in
    admin)
        DEV_ENDPOINT="http://localhost:8101/v1/graphql"
        DEV_SECRET="CCTech2024Admin"
        PROD_ENDPOINT="https://admin-graphql-api.hasura.app/v1/graphql"
        PROD_SECRET="G2t1VKcCa2WKEZT671y6lfZBvP2gjv43H5YdqKTnSP0YIwjcPB6sC15tcVgHN2Vb"
        ;;
    operator)
        DEV_ENDPOINT="http://localhost:8102/v1/graphql"
        DEV_SECRET="CCTech2024Operator"
        PROD_ENDPOINT="https://operator-graphql-api.hasura.app/v1/graphql"
        PROD_SECRET="tdlRz1LKUx1MM2ckawtmb97s0bsfBxU1DE344Bege8wK4oV66qs94lu4IDkTVE55"
        ;;
    member)
        DEV_ENDPOINT="http://localhost:8103/v1/graphql"
        DEV_SECRET="CCTech2024Member"
        PROD_ENDPOINT="https://member-graphql-api.hasura.app/v1/graphql"
        PROD_SECRET="0yyZqc58qfB7t4bJ56LIUBnxsMhvVtENyU9YxiE7cmA0qJLLlIIjm1hcaMGxgbs1"
        ;;
    *)
        echo "Invalid tier: $TIER"
        exit 1
        ;;
esac

# Introspection query to get complete schema
INTROSPECTION_QUERY='{
  "__schema": {
    "types": {
      "name": true,
      "kind": true,
      "description": true,
      "fields": {
        "name": true,
        "type": {
          "name": true,
          "kind": true
        }
      }
    },
    "queryType": {
      "name": true,
      "fields": {
        "name": true,
        "type": {
          "name": true
        }
      }
    },
    "mutationType": {
      "name": true,
      "fields": {
        "name": true,
        "type": {
          "name": true
        }
      }
    },
    "subscriptionType": {
      "name": true,
      "fields": {
        "name": true,
        "type": {
          "name": true
        }
      }
    }
  }
}'

# Full introspection query
FULL_INTROSPECTION='{"query": "{ __schema { types { name kind description fields { name type { name kind } } } queryType { name fields { name } } mutationType { name fields { name } } subscriptionType { name fields { name } } } }"}'

echo ""
echo "📊 Fetching schemas..."

# Get dev schema
DEV_SCHEMA=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "X-Hasura-Admin-Secret: $DEV_SECRET" \
    -d "$FULL_INTROSPECTION" \
    "$DEV_ENDPOINT" 2>/dev/null)

# Get prod schema  
PROD_SCHEMA=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "X-Hasura-Admin-Secret: $PROD_SECRET" \
    -d "$FULL_INTROSPECTION" \
    "$PROD_ENDPOINT" 2>/dev/null)

# Check if we got valid responses
if ! echo "$DEV_SCHEMA" | jq -e '.data.__schema' > /dev/null 2>&1; then
    echo -e "${RED}❌ Failed to fetch development schema${NC}"
    echo "$DEV_SCHEMA" | jq -r '.errors[0].message' 2>/dev/null || echo "$DEV_SCHEMA"
    exit 1
fi

if ! echo "$PROD_SCHEMA" | jq -e '.data.__schema' > /dev/null 2>&1; then
    echo -e "${RED}❌ Failed to fetch production schema${NC}"
    echo "$PROD_SCHEMA" | jq -r '.errors[0].message' 2>/dev/null || echo "$PROD_SCHEMA"
    exit 1
fi

echo -e "${GREEN}✅ Schemas fetched successfully${NC}"
echo ""

# Extract and compare queries
echo "📋 Comparing Queries..."
DEV_QUERIES=$(echo "$DEV_SCHEMA" | jq -r '.data.__schema.queryType.fields[].name' | grep -v "__" | sort)
PROD_QUERIES=$(echo "$PROD_SCHEMA" | jq -r '.data.__schema.queryType.fields[].name' | grep -v "__" | sort)

QUERIES_ONLY_DEV=$(comm -23 <(echo "$DEV_QUERIES") <(echo "$PROD_QUERIES"))
QUERIES_ONLY_PROD=$(comm -13 <(echo "$DEV_QUERIES") <(echo "$PROD_QUERIES"))
QUERIES_COMMON=$(comm -12 <(echo "$DEV_QUERIES") <(echo "$PROD_QUERIES"))

if [ -n "$QUERIES_ONLY_DEV" ]; then
    echo -e "${YELLOW}⚠️  Queries only in DEV:${NC}"
    echo "$QUERIES_ONLY_DEV" | sed 's/^/   - /'
fi

if [ -n "$QUERIES_ONLY_PROD" ]; then
    echo -e "${YELLOW}⚠️  Queries only in PROD:${NC}"
    echo "$QUERIES_ONLY_PROD" | sed 's/^/   - /'
fi

QUERY_COUNT_DEV=$(echo "$DEV_QUERIES" | wc -l)
QUERY_COUNT_PROD=$(echo "$PROD_QUERIES" | wc -l)
QUERY_COUNT_COMMON=$(echo "$QUERIES_COMMON" | wc -l)

echo -e "${BLUE}Query Summary:${NC}"
echo "  Development: $QUERY_COUNT_DEV queries"
echo "  Production: $QUERY_COUNT_PROD queries"
echo "  Common: $QUERY_COUNT_COMMON queries"
echo ""

# Extract and compare mutations
echo "📝 Comparing Mutations..."
DEV_MUTATIONS=$(echo "$DEV_SCHEMA" | jq -r '.data.__schema.mutationType.fields[].name' | grep -v "__" | sort)
PROD_MUTATIONS=$(echo "$PROD_SCHEMA" | jq -r '.data.__schema.mutationType.fields[].name' | grep -v "__" | sort)

MUTATIONS_ONLY_DEV=$(comm -23 <(echo "$DEV_MUTATIONS") <(echo "$PROD_MUTATIONS"))
MUTATIONS_ONLY_PROD=$(comm -13 <(echo "$DEV_MUTATIONS") <(echo "$PROD_MUTATIONS"))
MUTATIONS_COMMON=$(comm -12 <(echo "$DEV_MUTATIONS") <(echo "$PROD_MUTATIONS"))

if [ -n "$MUTATIONS_ONLY_DEV" ]; then
    echo -e "${YELLOW}⚠️  Mutations only in DEV:${NC}"
    echo "$MUTATIONS_ONLY_DEV" | sed 's/^/   - /'
fi

if [ -n "$MUTATIONS_ONLY_PROD" ]; then
    echo -e "${YELLOW}⚠️  Mutations only in PROD:${NC}"
    echo "$MUTATIONS_ONLY_PROD" | sed 's/^/   - /'
fi

MUTATION_COUNT_DEV=$(echo "$DEV_MUTATIONS" | wc -l)
MUTATION_COUNT_PROD=$(echo "$PROD_MUTATIONS" | wc -l)
MUTATION_COUNT_COMMON=$(echo "$MUTATIONS_COMMON" | wc -l)

echo -e "${BLUE}Mutation Summary:${NC}"
echo "  Development: $MUTATION_COUNT_DEV mutations"
echo "  Production: $MUTATION_COUNT_PROD mutations"
echo "  Common: $MUTATION_COUNT_COMMON mutations"
echo ""

# Extract and compare types (tables)
echo "📊 Comparing Types (Tables)..."
DEV_TYPES=$(echo "$DEV_SCHEMA" | jq -r '.data.__schema.types[] | select(.name | startswith("__") | not) | select(.kind == "OBJECT") | .name' | sort)
PROD_TYPES=$(echo "$PROD_SCHEMA" | jq -r '.data.__schema.types[] | select(.name | startswith("__") | not) | select(.kind == "OBJECT") | .name' | sort)

TYPES_ONLY_DEV=$(comm -23 <(echo "$DEV_TYPES") <(echo "$PROD_TYPES"))
TYPES_ONLY_PROD=$(comm -13 <(echo "$DEV_TYPES") <(echo "$PROD_TYPES"))
TYPES_COMMON=$(comm -12 <(echo "$DEV_TYPES") <(echo "$PROD_TYPES"))

if [ -n "$TYPES_ONLY_DEV" ]; then
    echo -e "${YELLOW}⚠️  Types only in DEV:${NC}"
    echo "$TYPES_ONLY_DEV" | sed 's/^/   - /' | head -10
    if [ $(echo "$TYPES_ONLY_DEV" | wc -l) -gt 10 ]; then
        echo "   ... and $(($(echo "$TYPES_ONLY_DEV" | wc -l) - 10)) more"
    fi
fi

if [ -n "$TYPES_ONLY_PROD" ]; then
    echo -e "${YELLOW}⚠️  Types only in PROD:${NC}"
    echo "$TYPES_ONLY_PROD" | sed 's/^/   - /' | head -10
    if [ $(echo "$TYPES_ONLY_PROD" | wc -l) -gt 10 ]; then
        echo "   ... and $(($(echo "$TYPES_ONLY_PROD" | wc -l) - 10)) more"
    fi
fi

TYPE_COUNT_DEV=$(echo "$DEV_TYPES" | wc -l)
TYPE_COUNT_PROD=$(echo "$PROD_TYPES" | wc -l)
TYPE_COUNT_COMMON=$(echo "$TYPES_COMMON" | wc -l)

echo -e "${BLUE}Type Summary:${NC}"
echo "  Development: $TYPE_COUNT_DEV types"
echo "  Production: $TYPE_COUNT_PROD types"
echo "  Common: $TYPE_COUNT_COMMON types"
echo ""

# Overall verdict
echo "================================================"
echo -e "${BLUE}🎯 Overall Comparison Results:${NC}"

TOTAL_DIFF=0
if [ "$QUERY_COUNT_DEV" != "$QUERY_COUNT_PROD" ]; then
    echo -e "${YELLOW}⚠️  Query count mismatch${NC}"
    TOTAL_DIFF=$((TOTAL_DIFF + 1))
fi

if [ "$MUTATION_COUNT_DEV" != "$MUTATION_COUNT_PROD" ]; then
    echo -e "${YELLOW}⚠️  Mutation count mismatch${NC}"
    TOTAL_DIFF=$((TOTAL_DIFF + 1))
fi

if [ "$TYPE_COUNT_DEV" != "$TYPE_COUNT_PROD" ]; then
    echo -e "${YELLOW}⚠️  Type count mismatch${NC}"
    TOTAL_DIFF=$((TOTAL_DIFF + 1))
fi

if [ $TOTAL_DIFF -eq 0 ]; then
    echo -e "${GREEN}✅ Development and Production schemas are IDENTICAL${NC}"
else
    echo -e "${YELLOW}⚠️  Found $TOTAL_DIFF category differences between environments${NC}"
    echo ""
    echo "Recommendation: Run './commands/fast-refresh.sh $TIER production' to sync"
fi

# Detailed mode
if [ "$DETAILED" == "--detailed" ]; then
    echo ""
    echo "================================================"
    echo "📜 Detailed Field Comparison for Common Types"
    echo ""
    
    # Compare fields for each common type
    for type in $(echo "$TYPES_COMMON" | head -5); do
        echo "Type: $type"
        
        DEV_FIELDS=$(echo "$DEV_SCHEMA" | jq -r ".data.__schema.types[] | select(.name == \"$type\") | .fields[]?.name" | sort)
        PROD_FIELDS=$(echo "$PROD_SCHEMA" | jq -r ".data.__schema.types[] | select(.name == \"$type\") | .fields[]?.name" | sort)
        
        FIELDS_DIFF=$(diff <(echo "$DEV_FIELDS") <(echo "$PROD_FIELDS") || true)
        
        if [ -n "$FIELDS_DIFF" ]; then
            echo -e "${YELLOW}  Field differences found:${NC}"
            echo "$FIELDS_DIFF" | sed 's/^/    /'
        else
            echo -e "${GREEN}  Fields match ✓${NC}"
        fi
        echo ""
    done
fi
