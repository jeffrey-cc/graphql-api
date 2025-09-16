#!/bin/bash

# Check status of all GraphQL and database containers
# Usage: ./status-all.sh [format]
#   format: simple, detailed, or json (default: simple)

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source shared functions
source "${SCRIPT_DIR}/_shared_functions.sh"

# Parse arguments
FORMAT="${1:-simple}"

# Validate format
if [[ ! "$FORMAT" =~ ^(simple|detailed|json)$ ]]; then
    echo "${RED}✗${NC} Invalid format: $FORMAT"
    echo "${CYAN}ℹ${NC} Valid formats: simple, detailed, json"
    exit 1
fi

# Colors for output
ERROR="${RED}✗${NC}"
SUCCESS="${GREEN}✓${NC}"
INFO="${CYAN}ℹ${NC}"
PROGRESS="${BLUE}➜${NC}"
WARNING="${YELLOW}⚠${NC}"

# Function to check container status
check_container() {
    local name=$1
    local expected_port=$2
    local type=$3
    
    if [ "$FORMAT" = "json" ]; then
        # JSON output
        local status=$(docker ps --format "{{.Status}}" --filter "name=${name}" 2>/dev/null | head -1)
        local ports=$(docker ps --format "{{.Ports}}" --filter "name=${name}" 2>/dev/null | head -1)
        if [ -n "$status" ]; then
            echo "    {\"name\": \"$name\", \"type\": \"$type\", \"port\": \"$expected_port\", \"status\": \"running\", \"health\": \"$status\", \"ports\": \"$ports\"}"
        else
            echo "    {\"name\": \"$name\", \"type\": \"$type\", \"port\": \"$expected_port\", \"status\": \"stopped\"}"
        fi
    elif [ "$FORMAT" = "detailed" ]; then
        # Detailed output
        local info=$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" --filter "name=${name}" 2>/dev/null | grep -v NAMES | head -1)
        if [ -n "$info" ]; then
            echo "$info"
        else
            printf "%-30s %-30s %s\n" "$name" "Not running" "-"
        fi
    else
        # Simple output
        printf "  %-25s [%s] " "${name}:" "$expected_port"
        if docker ps --format "{{.Names}}" | grep -q "^${name}$"; then
            local health=$(docker ps --format "{{.Status}}" --filter "name=${name}" | head -1)
            if echo "$health" | grep -q "healthy"; then
                echo "✅ Running (healthy)"
            elif echo "$health" | grep -q "unhealthy"; then
                echo "⚠️  Running (unhealthy)"
            else
                echo "🔄 Running (starting...)"
            fi
        else
            echo "❌ Not running"
            ((COMMAND_ERRORS++))
        fi
    fi
}

# Main execution
echo ""
echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${CYAN}📊 SYSTEM STATUS - ALL SERVICES${NC}"
echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${INFO} Format: $FORMAT"
echo "${INFO} Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

if [ "$FORMAT" = "json" ]; then
    echo "{"
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"services\": {"
fi

# Database containers
if [ "$FORMAT" = "json" ]; then
    echo "    \"databases\": ["
elif [ "$FORMAT" = "detailed" ]; then
    echo "DATABASE SERVICES:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-30s %-30s %s\n" "NAME" "STATUS" "PORTS"
    echo "───────────────────────────────────────────────────────────────────────────"
else
    echo "🗄️  DATABASE SERVICES:"
fi

check_container "admin-postgres" "7101" "database"
if [ "$FORMAT" = "json" ]; then echo ","; fi
check_container "operator-postgres" "7102" "database"
if [ "$FORMAT" = "json" ]; then echo ","; fi
check_container "member-postgres" "7103" "database"

if [ "$FORMAT" = "json" ]; then
    echo "    ],"
    echo "    \"graphql\": ["
elif [ "$FORMAT" = "detailed" ]; then
    echo ""
    echo "GRAPHQL SERVICES:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-30s %-30s %s\n" "NAME" "STATUS" "PORTS"
    echo "───────────────────────────────────────────────────────────────────────────"
else
    echo ""
    echo "🚀 GRAPHQL SERVICES:"
fi

# GraphQL containers
check_container "admin-graphql-server" "8101" "graphql"
if [ "$FORMAT" = "json" ]; then echo ","; fi
check_container "operator-graphql-server" "8102" "graphql"
if [ "$FORMAT" = "json" ]; then echo ","; fi
check_container "member-graphql-server" "8103" "graphql"

if [ "$FORMAT" = "json" ]; then
    echo "    ]"
    echo "  },"
    echo "  \"summary\": {"
    echo "    \"total_errors\": $COMMAND_ERRORS,"
    echo "    \"status\": \"$([ $COMMAND_ERRORS -eq 0 ] && echo "healthy" || echo "degraded")\""
    echo "  }"
    echo "}"
else
    echo ""
    echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Show summary
    if [ $COMMAND_ERRORS -eq 0 ]; then
        echo "${SUCCESS} All services running normally!${NC}"
    else
        echo "${WARNING} ${COMMAND_ERRORS} service(s) not running${NC}"
        echo ""
        echo "To start services:"
        echo "  • Databases: cd shared-database-sql && ./commands/docker-start.sh <tier> development"
        echo "  • GraphQL: cd shared-graphql-api && ./commands/docker-start.sh <tier> development"
    fi
fi

# Clean exit
exit $COMMAND_ERRORS