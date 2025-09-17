#!/bin/bash

echo "🔍 COMPREHENSIVE GRAPHQL DATA TEST REPORT"
echo "=========================================="
echo ""

test_tier() {
    local tier=$1
    local env=$2
    local purge_cmd=$3
    local load_cmd=$4
    
    echo "Testing $tier in $env..."
    
    # Purge
    $purge_cmd $env > /tmp/${tier}_${env}_purge.log 2>&1
    local purge_total=$(grep "Total rows deleted:" /tmp/${tier}_${env}_purge.log | awk '{print $NF}')
    local purge_errors=$(grep "❌" /tmp/${tier}_${env}_purge.log | wc -l)
    
    # Load
    $load_cmd $env > /tmp/${tier}_${env}_load.log 2>&1
    local load_total=$(grep "Total rows loaded:" /tmp/${tier}_${env}_load.log | awk '{print $NF}')
    local load_errors=$(grep "❌" /tmp/${tier}_${env}_load.log | wc -l)
    local load_success=$(grep "✅" /tmp/${tier}_${env}_load.log | wc -l)
    
    echo "  Purge: Deleted $purge_total rows (${purge_errors} errors)"
    echo "  Load:  Loaded $load_total rows (${load_success} success, ${load_errors} errors)"
    
    if [ "$load_errors" -gt 0 ]; then
        echo "  Failed tables:"
        grep "❌" /tmp/${tier}_${env}_load.log | head -3 | sed 's/^/    /'
    fi
}

echo "📊 DEVELOPMENT ENVIRONMENT"
echo "--------------------------"
test_tier "Admin" "development" "./commands/purge-admin-test-data-via-graphql.sh" "./commands/load-admin-test-data-via-graphql.sh"
test_tier "Operator" "development" "./commands/purge-operator-test-data-via-graphql.sh" "./commands/load-operator-test-data-via-graphql.sh"
test_tier "Member" "development" "./commands/purge-member-test-data-via-graphql.sh" "./commands/load-member-test-data-via-graphql.sh"

echo ""
echo "📊 PRODUCTION ENVIRONMENT"
echo "-------------------------"
test_tier "Admin" "production" "./commands/purge-admin-test-data-via-graphql.sh" "./commands/load-admin-test-data-via-graphql.sh"
test_tier "Operator" "production" "./commands/purge-operator-test-data-via-graphql.sh" "./commands/load-operator-test-data-via-graphql.sh"
test_tier "Member" "production" "./commands/purge-member-test-data-via-graphql.sh" "./commands/load-member-test-data-via-graphql.sh"

echo ""
echo "✅ SUMMARY"
echo "----------"
echo "Development:"
echo "  Admin:    $(grep "Total rows loaded:" /tmp/Admin_development_load.log | awk '{print $NF}') rows loaded"
echo "  Operator: $(grep "Total rows loaded:" /tmp/Operator_development_load.log | awk '{print $NF}') rows loaded"
echo "  Member:   $(grep "Total rows loaded:" /tmp/Member_development_load.log | awk '{print $NF}') rows loaded"
echo ""
echo "Production:"
echo "  Admin:    $(grep "Total rows loaded:" /tmp/Admin_production_load.log | awk '{print $NF}') rows loaded"
echo "  Operator: $(grep "Total rows loaded:" /tmp/Operator_production_load.log | awk '{print $NF}') rows loaded"
echo "  Member:   $(grep "Total rows loaded:" /tmp/Member_production_load.log | awk '{print $NF}') rows loaded"
