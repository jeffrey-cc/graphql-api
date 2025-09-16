#!/bin/bash

# Exhaustive test of all commands in shared-graphql-api
set -e

cd /Users/cc/Desktop/v3/shared-graphql-api

echo "====================================="
echo "EXHAUSTIVE COMMAND TESTING"
echo "Testing all commands across all tiers and environments"
echo "====================================="
echo ""

# Define tiers and environments
TIERS="admin operator member"
ENVIRONMENTS="development production"

# Test results tracking
PASSED=0
FAILED=0
ERRORS=""

# Function to test a command
test_command() {
    local cmd=$1
    local tier=$2
    local env=$3
    local desc="$cmd $tier $env"
    
    echo -n "Testing $desc... "
    if timeout 30 ./commands/$cmd $tier $env > /tmp/test-output.log 2>&1; then
        echo "✅ PASSED"
        ((PASSED++))
        return 0
    else
        local exit_code=$?
        echo "❌ FAILED (exit: $exit_code)"
        ((FAILED++))
        ERRORS="$ERRORS\n  - $desc (exit: $exit_code)"
        tail -5 /tmp/test-output.log | sed 's/^/    /'
        return 1
    fi
}

# Function to test command that takes only tier
test_tier_only_command() {
    local cmd=$1
    local tier=$2
    local desc="$cmd $tier"
    
    echo -n "Testing $desc... "
    if timeout 30 ./commands/$cmd $tier > /tmp/test-output.log 2>&1; then
        echo "✅ PASSED"
        ((PASSED++))
        return 0
    else
        local exit_code=$?
        echo "❌ FAILED (exit: $exit_code)"
        ((FAILED++))
        ERRORS="$ERRORS\n  - $desc (exit: $exit_code)"
        tail -5 /tmp/test-output.log | sed 's/^/    /'
        return 1
    fi
}

# Function to test command with no parameters
test_no_params_command() {
    local cmd=$1
    local desc="$cmd"
    
    echo -n "Testing $desc... "
    if timeout 30 ./commands/$cmd > /tmp/test-output.log 2>&1; then
        echo "✅ PASSED"
        ((PASSED++))
        return 0
    else
        local exit_code=$?
        echo "❌ FAILED (exit: $exit_code)"
        ((FAILED++))
        ERRORS="$ERRORS\n  - $desc (exit: $exit_code)"
        tail -5 /tmp/test-output.log | sed 's/^/    /'
        return 1
    fi
}

echo "========================================="
echo "1. TESTING compare-environments.sh"
echo "========================================="
for tier in $TIERS; do
    test_tier_only_command "compare-environments.sh" "$tier" || true
done
echo ""

echo "========================================="
echo "2. TESTING status-all.sh"
echo "========================================="
test_no_params_command "status-all.sh" || true
echo ""

echo "========================================="
echo "3. TESTING docker-status.sh"
echo "========================================="
for tier in $TIERS; do
    for env in $ENVIRONMENTS; do
        test_command "docker-status.sh" "$tier" "$env" || true
    done
done
echo ""

echo "========================================="
echo "4. TESTING test-health.sh"
echo "========================================="
for tier in $TIERS; do
    for env in $ENVIRONMENTS; do
        test_command "test-health.sh" "$tier" "$env" || true
    done
done
echo ""

echo "========================================="
echo "5. TESTING fast-refresh.sh"
echo "========================================="
for tier in $TIERS; do
    for env in $ENVIRONMENTS; do
        test_command "fast-refresh.sh" "$tier" "$env" || true
    done
done
echo ""

echo "========================================="
echo "6. TESTING verify-tables-tracked.sh"
echo "========================================="
for tier in $TIERS; do
    for env in $ENVIRONMENTS; do
        test_command "verify-tables-tracked.sh" "$tier" "$env" || true
    done
done
echo ""

echo "========================================="
echo "7. TESTING verify-complete-setup.sh"
echo "========================================="
for tier in $TIERS; do
    for env in $ENVIRONMENTS; do
        test_command "verify-complete-setup.sh" "$tier" "$env" || true
    done
done
echo ""

echo "========================================="
echo "8. TESTING track-all-tables.sh"
echo "========================================="
for tier in $TIERS; do
    test_command "track-all-tables.sh" "$tier" "development" || true
done
echo ""

echo "========================================="
echo "9. TESTING track-relationships.sh"
echo "========================================="
for tier in $TIERS; do
    test_command "track-relationships.sh" "$tier" "development" || true
done
echo ""

echo "========================================="
echo "10. TESTING restart-graphql.sh"
echo "========================================="
for tier in $TIERS; do
    test_command "restart-graphql.sh" "$tier" "development" || true
done
echo ""

echo "========================================="
echo "11. TESTING docker-start.sh"
echo "========================================="
for tier in $TIERS; do
    test_command "docker-start.sh" "$tier" "development" || true
done
echo ""

echo "========================================="
echo "12. TESTING docker-stop.sh"
echo "========================================="
for tier in $TIERS; do
    test_command "docker-stop.sh" "$tier" "development" || true
done
echo ""

echo "========================================="
echo "13. TESTING docker-start.sh (restart after stop)"
echo "========================================="
for tier in $TIERS; do
    test_command "docker-start.sh" "$tier" "development" || true
done
echo ""

echo "========================================="
echo "14. TESTING rebuild-docker.sh"
echo "========================================="
for tier in $TIERS; do
    test_command "rebuild-docker.sh" "$tier" "development" || true
done
echo ""

echo "========================================="
echo "15. TESTING deploy-graphql.sh"
echo "========================================="
for tier in $TIERS; do
    test_command "deploy-graphql.sh" "$tier" "development" || true
done
echo ""

echo ""
echo "====================================="
echo "TEST SUMMARY"
echo "====================================="
echo "✅ PASSED: $PASSED"
echo "❌ FAILED: $FAILED"
echo "Total: $((PASSED + FAILED))"
echo ""
if [ $FAILED -gt 0 ]; then
    echo "Failed commands:"
    echo -e "$ERRORS"
    echo ""
fi
echo "Success rate: $(( PASSED * 100 / (PASSED + FAILED) ))%"
echo "====================================="