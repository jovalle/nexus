#!/bin/bash
#
# Nexus Setup Verification Script
# Tests that all setup components are working correctly
#
# Usage: ./scripts/verify-setup.sh

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Nexus Setup Verification"
echo "========================"
echo ""

# Test 1: Check if setup script exists and is executable
print_test "Checking setup script..."
if [ -x "$SCRIPT_DIR/setup.sh" ]; then
    print_pass "setup.sh exists and is executable"
else
    print_fail "setup.sh not found or not executable"
    exit 1
fi

# Test 2: Check if update-readme script exists and is executable
print_test "Checking update-readme script..."
if [ -x "$SCRIPT_DIR/update-readme.py" ]; then
    print_pass "update-readme.py exists and is executable"
else
    print_fail "update-readme.py not found or not executable"
    exit 1
fi

# Test 3: Check if Makefile exists
print_test "Checking Makefile..."
if [ -f "$ROOT_DIR/Makefile" ]; then
    print_pass "Makefile exists"
else
    print_fail "Makefile not found"
    exit 1
fi

# Test 4: Check if Python 3 is available
print_test "Checking Python 3..."
if command -v python3 &>/dev/null; then
    PYTHON_VERSION=$(python3 --version)
    print_pass "Python 3 is available: $PYTHON_VERSION"
else
    print_fail "Python 3 not found"
    exit 1
fi

# Test 5: Check if PyYAML is installed
print_test "Checking PyYAML..."
if python3 -c "import yaml" 2>/dev/null; then
    print_pass "PyYAML is installed"
else
    print_fail "PyYAML not installed"
    exit 1
fi

# Test 6: Check if nx wrapper exists
print_test "Checking nx wrapper..."
if [ -f "$ROOT_DIR/nx" ]; then
    print_pass "nx wrapper exists"
else
    print_fail "nx wrapper not found"
    exit 1
fi

# Test 7: Check if stacks directory exists
print_test "Checking stacks directory..."
if [ -d "$ROOT_DIR/stacks" ]; then
    STACK_COUNT=$(find "$ROOT_DIR/stacks" -maxdepth 1 -mindepth 1 -type d | wc -l)
    print_pass "stacks directory exists with $STACK_COUNT stacks"
else
    print_fail "stacks directory not found"
    exit 1
fi

# Test 8: Test update-readme.py (dry run)
print_test "Testing update-readme.py..."
if python3 "$SCRIPT_DIR/update-readme.py" > /dev/null 2>&1; then
    print_pass "update-readme.py executes successfully"
else
    print_fail "update-readme.py failed"
    exit 1
fi

# Test 9: Check if documentation exists
print_test "Checking documentation files..."
DOC_FILES=("README.md" "SETUP.md" "MAKEFILE.md" "SUMMARY.md")
ALL_DOCS_FOUND=true
for doc in "${DOC_FILES[@]}"; do
    if [ ! -f "$ROOT_DIR/$doc" ]; then
        print_fail "$doc not found"
        ALL_DOCS_FOUND=false
    fi
done
if [ "$ALL_DOCS_FOUND" = true ]; then
    print_pass "All documentation files present"
fi

# Test 10: Check if Homebrew is installed (optional)
print_test "Checking Homebrew installation..."
if [ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
    BREW_VERSION=$(/home/linuxbrew/.linuxbrew/bin/brew --version 2>/dev/null | head -n 1 || echo "unknown")
    print_pass "Homebrew is installed: $BREW_VERSION"
elif command -v brew &>/dev/null; then
    BREW_VERSION=$(brew --version 2>/dev/null | head -n 1 || echo "unknown")
    print_pass "Homebrew is installed (system): $BREW_VERSION"
else
    print_skip "Homebrew not installed (run setup.sh to install)"
fi

# Test 11: Check if make is available (optional)
print_test "Checking make availability..."
if command -v make &>/dev/null; then
    MAKE_VERSION=$(make --version 2>/dev/null | head -n 1 || echo "unknown")
    print_pass "make is available: $MAKE_VERSION"
else
    print_skip "make not installed (run setup.sh to install)"
fi

# Test 12: Validate Makefile syntax
print_test "Validating Makefile syntax..."
if command -v make &>/dev/null; then
    if make -f "$ROOT_DIR/Makefile" --dry-run help > /dev/null 2>&1; then
        print_pass "Makefile syntax is valid"
    else
        print_fail "Makefile has syntax errors"
        exit 1
    fi
else
    print_skip "make not available, cannot validate Makefile"
fi

# Test 13: Check compose files
print_test "Checking compose files..."
COMPOSE_COUNT=$(find "$ROOT_DIR/stacks" -name "compose.yaml" | wc -l)
if [ "$COMPOSE_COUNT" -gt 0 ]; then
    print_pass "Found $COMPOSE_COUNT compose files"
else
    print_fail "No compose files found"
    exit 1
fi

# Test 14: Validate compose files (if docker is available)
print_test "Validating compose files..."
if command -v docker &>/dev/null; then
    INVALID_COUNT=0
    for compose_file in $(find "$ROOT_DIR/stacks" -name "compose.yaml"); do
        if ! docker compose -f "$compose_file" config > /dev/null 2>&1; then
            print_fail "Invalid: $compose_file"
            INVALID_COUNT=$((INVALID_COUNT + 1))
        fi
    done

    # Check root compose
    if [ -f "$ROOT_DIR/compose.yaml" ]; then
        if ! docker compose -f "$ROOT_DIR/compose.yaml" config > /dev/null 2>&1; then
            print_fail "Invalid: $ROOT_DIR/compose.yaml"
            INVALID_COUNT=$((INVALID_COUNT + 1))
        fi
    fi

    if [ "$INVALID_COUNT" -eq 0 ]; then
        print_pass "All compose files are valid"
    else
        print_fail "$INVALID_COUNT compose file(s) are invalid"
    fi
else
    print_skip "Docker not available, cannot validate compose files"
fi

# Summary
echo ""
echo "========================"
echo -e "${GREEN}Verification Complete!${NC}"
echo ""
echo "Next steps:"
if ! command -v brew &>/dev/null; then
    echo "  1. Run: sudo ./scripts/setup.sh [username]"
fi
if ! command -v make &>/dev/null; then
    echo "  2. Install make via setup script"
fi
echo "  3. Run: make help"
echo "  4. Run: make fmt (to update README)"
echo "  5. Run: make start (to start all stacks)"
echo ""
