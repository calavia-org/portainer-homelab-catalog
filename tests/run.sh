#!/usr/bin/env bash
# Unified test runner for Portainer stack smoke tests.
# Usage:
#   bash tests/run.sh                    # Run all tests
#   bash tests/run.sh network/unifi-controller  # Run single stack test
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"

# ANSI colour codes for pretty output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Colour

run_single() {
    local stack_path="$1"
    local test_script="$TESTS_DIR/test-$(basename "$stack_path").sh"

    if [ ! -f "$test_script" ]; then
        echo -e "${RED}SKIP${NC}: No test found for ${stack_path} (expected ${test_script})"
        return 0
    fi

    echo ""
    echo "========================================"
    echo "Testing: ${stack_path}"
    echo "Script: ${test_script}"
    echo "========================================"

    if bash "$test_script"; then
        echo -e "${GREEN}✓ PASS${NC}: ${stack_path}"
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: ${stack_path}"
        return 1
    fi
}

# Collect all stacks that have a docker-compose.yml
find_stacks() {
    find "$REPO_DIR" -name 'docker-compose.yml' -not -path '*/.omo/*' | \
        sed "s|${REPO_DIR}/||" | \
        sed 's|/docker-compose.yml||' | \
        sort
}

main() {
    local target="${1:-}"
    local failed=0

    if [ -n "$target" ]; then
        # Single stack mode
        run_single "$target" || failed=1
    else
        # All stacks mode
        echo "Discovering stacks with docker-compose.yml..."
        local stacks
        stacks=$(find_stacks)

        if [ -z "$stacks" ]; then
            echo "No stacks found."
            exit 0
        fi

        echo "Found $(echo "$stacks" | wc -l | tr -d ' ') stack(s):"
        echo "$stacks" | sed 's/^/  - /'
        echo ""

        while IFS= read -r stack; do
            run_single "$stack" || failed=1
        done <<< "$stacks"
    fi

    echo ""
    echo "========================================"
    if [ "$failed" -eq 0 ]; then
        echo -e "${GREEN}All tests passed.${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        exit 1
    fi
}

main "$@"
