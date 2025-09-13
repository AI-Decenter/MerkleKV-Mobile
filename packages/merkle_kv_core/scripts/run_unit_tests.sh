#!/bin/bash

# Unit Test Runner with Coverage Analysis
# This script runs the comprehensive unit test suite and generates coverage reports

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== MerkleKV Core Unit Test Suite ===${NC}"
echo "Running comprehensive unit tests with coverage analysis..."

# Change to package directory
cd "$(dirname "$0")"

# Install dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"
dart pub get

# Generate mocks if needed
echo -e "${YELLOW}Generating mocks...${NC}"
dart run build_runner build --delete-conflicting-outputs

# Create coverage directory
mkdir -p coverage

echo -e "${YELLOW}Running unit tests with coverage...${NC}"

# Run unit tests with coverage
dart test --coverage=coverage test/unit/ --timeout=30s --concurrency=4

# Generate coverage report
echo -e "${YELLOW}Generating coverage report...${NC}"
dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --packages=.packages --report-on=lib

# Generate HTML coverage report
if command -v genhtml &> /dev/null; then
    echo -e "${YELLOW}Generating HTML coverage report...${NC}"
    genhtml coverage/lcov.info -o coverage/html
    echo -e "${GREEN}HTML coverage report generated at: coverage/html/index.html${NC}"
else
    echo -e "${YELLOW}genhtml not found. Install lcov package to generate HTML reports.${NC}"
fi

# Parse coverage percentage
if [ -f "coverage/lcov.info" ]; then
    # Calculate coverage percentage
    TOTAL_LINES=$(grep -c "^DA:" coverage/lcov.info || echo "0")
    HIT_LINES=$(grep "^DA:" coverage/lcov.info | grep -v ",0$" | wc -l || echo "0")
    
    if [ "$TOTAL_LINES" -gt 0 ]; then
        COVERAGE_PERCENT=$(echo "scale=2; $HIT_LINES * 100 / $TOTAL_LINES" | bc -l 2>/dev/null || echo "0")
        echo -e "${BLUE}Coverage Summary:${NC}"
        echo -e "  Lines hit: $HIT_LINES"
        echo -e "  Total lines: $TOTAL_LINES"
        echo -e "  Coverage: ${COVERAGE_PERCENT}%"
        
        # Check if coverage meets target (95%)
        COVERAGE_INT=$(echo "$COVERAGE_PERCENT" | cut -d. -f1)
        if [ "$COVERAGE_INT" -ge 95 ]; then
            echo -e "${GREEN}✓ Coverage target met (≥95%)${NC}"
        else
            echo -e "${RED}✗ Coverage below target (target: ≥95%, actual: ${COVERAGE_PERCENT}%)${NC}"
            exit 1
        fi
    else
        echo -e "${RED}✗ Could not calculate coverage${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ Coverage file not generated${NC}"
    exit 1
fi

echo -e "${GREEN}=== Unit test suite completed successfully ===${NC}"