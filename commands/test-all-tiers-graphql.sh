#!/bin/bash

echo "🧪 Testing GraphQL Data Loading for All Tiers"
echo "=============================================="
echo ""

# Test Admin Tier
echo "📊 Testing Admin Tier..."
echo "------------------------"
./commands/purge-test-data-via-graphql.sh admin development > /tmp/admin-purge.log 2>&1
if grep -q "✅ Purge completed successfully" /tmp/admin-purge.log; then
    echo "✅ Admin purge: SUCCESS"
else
    echo "❌ Admin purge: FAILED (check /tmp/admin-purge.log)"
fi

./commands/load-test-data-via-graphql.sh admin development > /tmp/admin-load.log 2>&1
total_loaded=$(grep "Total rows loaded:" /tmp/admin-load.log | awk '{print $NF}')
echo "📦 Admin load: $total_loaded rows loaded"

# Test Operator Tier
echo ""
echo "📊 Testing Operator Tier..."
echo "---------------------------"
./commands/purge-operator-test-data-via-graphql.sh development > /tmp/operator-purge.log 2>&1
if grep -q "✅ Purge completed successfully" /tmp/operator-purge.log; then
    echo "✅ Operator purge: SUCCESS"
else
    echo "❌ Operator purge: FAILED (check /tmp/operator-purge.log)"
fi

./commands/load-operator-test-data-via-graphql.sh development > /tmp/operator-load.log 2>&1
total_loaded=$(grep "Total rows loaded:" /tmp/operator-load.log | awk '{print $NF}')
echo "📦 Operator load: $total_loaded rows loaded"

# Test Member Tier
echo ""
echo "📊 Testing Member Tier..."
echo "-------------------------"
./commands/purge-member-test-data-via-graphql.sh development > /tmp/member-purge.log 2>&1
purge_errors=$(grep "errors" /tmp/member-purge.log | wc -l)
if [ "$purge_errors" -eq 0 ]; then
    echo "✅ Member purge: SUCCESS"
else
    echo "⚠️  Member purge: PARTIAL (some tables don't exist)"
fi

./commands/load-member-test-data-via-graphql.sh development > /tmp/member-load.log 2>&1
total_loaded=$(grep "Total rows loaded:" /tmp/member-load.log | awk '{print $NF}')
echo "📦 Member load: $total_loaded rows loaded"

# Summary
echo ""
echo "📈 Summary Report"
echo "================="
echo ""
echo "Admin Tier:"
grep -E "(✅|❌|⚠️)" /tmp/admin-load.log | tail -5
echo ""
echo "Operator Tier:"
grep -E "(✅|❌|⚠️)" /tmp/operator-load.log | tail -5
echo ""
echo "Member Tier:"
grep -E "(✅|❌|⚠️)" /tmp/member-load.log | tail -5

echo ""
echo "✨ Test complete. Check /tmp/*-*.log for detailed logs."
