#!/bin/bash
# Smoke test script for deployed application
# Usage: ENDPOINT="https://your-app.example.com" ./smoke-test.sh

set -euo pipefail

ENDPOINT="${ENDPOINT:-http://localhost:5000}"
MAX_RETRIES=5
RETRY_DELAY=10

echo "Running smoke tests against: ${ENDPOINT}"
echo "-------------------------------------------"

check_endpoint() {
    local path="$1"
    local expected_code="$2"
    local description="$3"

    echo -n "Testing ${description}... "

    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" "${ENDPOINT}${path}" --max-time 10 2>/dev/null || echo "000")

    if [ "$response_code" == "$expected_code" ]; then
        echo "PASS (HTTP ${response_code})"
        return 0
    else
        echo "FAIL (expected ${expected_code}, got ${response_code})"
        return 1
    fi
}

# Wait for app to be ready
echo "Waiting for application to be ready..."
for i in $(seq 1 $MAX_RETRIES); do
    if curl -sf "${ENDPOINT}/health" --max-time 5 > /dev/null 2>&1; then
        echo "Application is ready."
        break
    fi
    if [ "$i" -eq "$MAX_RETRIES" ]; then
        echo "FAIL: Application did not become ready after ${MAX_RETRIES} retries"
        exit 1
    fi
    echo "  Retry ${i}/${MAX_RETRIES} in ${RETRY_DELAY}s..."
    sleep "$RETRY_DELAY"
done

echo ""
FAILURES=0

# Health check
check_endpoint "/health" "200" "Health endpoint" || FAILURES=$((FAILURES + 1))

# Health check returns valid JSON
echo -n "Testing health response JSON... "
HEALTH_RESPONSE=$(curl -sf "${ENDPOINT}/health" --max-time 10 2>/dev/null)
if echo "$HEALTH_RESPONSE" | python3 -m json.tool > /dev/null 2>&1; then
    echo "PASS (valid JSON)"
else
    echo "FAIL (invalid JSON)"
    FAILURES=$((FAILURES + 1))
fi

# API items endpoint
check_endpoint "/api/items" "200" "Items list endpoint" || FAILURES=$((FAILURES + 1))

# Stats endpoint
check_endpoint "/api/stats" "200" "Stats endpoint" || FAILURES=$((FAILURES + 1))

# 404 for unknown routes
check_endpoint "/nonexistent" "404" "404 for unknown routes" || FAILURES=$((FAILURES + 1))

echo ""
echo "-------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: ${FAILURES} test(s) failed"
    exit 1
else
    echo "ALL TESTS PASSED"
    exit 0
fi
