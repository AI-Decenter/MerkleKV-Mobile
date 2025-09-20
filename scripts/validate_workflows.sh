#!/bin/bash

# Workflow Validation Script
# This script validates all GitHub Actions workflows for proper syntax and structure

set -e

echo "🔍 Validating GitHub Actions Workflows..."
echo "================================================="

WORKFLOW_DIR=".github/workflows"
VALIDATION_ERRORS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to validate YAML syntax
validate_yaml() {
    local file="$1"
    echo -e "${BLUE}Validating:${NC} $(basename "$file")"
    
    # Check if file exists
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}❌ File not found: $file${NC}"
        return 1
    fi
    
    # Validate YAML syntax using Python
    python3 -c "
import yaml
import sys
try:
    with open('$file', 'r') as f:
        yaml.safe_load(f)
    print('✅ YAML syntax valid')
except yaml.YAMLError as e:
    print('❌ YAML syntax error:', e)
    sys.exit(1)
except Exception as e:
    print('❌ Error reading file:', e)
    sys.exit(1)
"
    
    if [[ $? -ne 0 ]]; then
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        return 1
    fi
    
    return 0
}

# Function to check workflow structure
check_workflow_structure() {
    local file="$1"
    local filename=$(basename "$file")
    
    echo -e "${BLUE}Checking structure:${NC} $filename"
    
    # Check for required sections
    if ! grep -q "^name:" "$file"; then
        echo -e "${YELLOW}⚠️  Missing 'name' field${NC}"
    fi
    
    if ! grep -q "^on:" "$file"; then
        echo -e "${RED}❌ Missing 'on' trigger section${NC}"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    fi
    
    if ! grep -q "^jobs:" "$file"; then
        echo -e "${RED}❌ Missing 'jobs' section${NC}"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    fi
    
    # Check for runs-on in jobs
    if ! grep -q "runs-on:" "$file"; then
        echo -e "${RED}❌ No 'runs-on' specified in jobs${NC}"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    fi
    
    echo -e "${GREEN}✅ Structure check completed${NC}"
}

# Function to check Flutter-specific workflows
check_flutter_workflow() {
    local file="$1"
    local filename=$(basename "$file")
    
    if [[ "$filename" == *"flutter"* ]] || [[ "$filename" == *"mobile"* ]] || [[ "$filename" == *"android"* ]] || [[ "$filename" == *"ios"* ]]; then
        echo -e "${BLUE}Checking Flutter-specific requirements:${NC} $filename"
        
        # Check for Flutter setup
        if grep -q "flutter-action" "$file" || grep -q "flutter/" "$file"; then
            echo -e "${GREEN}✅ Flutter setup found${NC}"
        else
            echo -e "${YELLOW}⚠️  No Flutter setup detected (may not be needed)${NC}"
        fi
        
        # Check for platform-specific setup
        if [[ "$filename" == *"android"* ]]; then
            if grep -q "android" "$file"; then
                echo -e "${GREEN}✅ Android configuration found${NC}"
            else
                echo -e "${YELLOW}⚠️  Android workflow without Android configuration${NC}"
            fi
        fi
        
        if [[ "$filename" == *"ios"* ]]; then
            if grep -q "ios\|macos" "$file"; then
                echo -e "${GREEN}✅ iOS/macOS configuration found${NC}"
            else
                echo -e "${YELLOW}⚠️  iOS workflow without iOS/macOS configuration${NC}"
            fi
        fi
    fi
}

# Main validation
echo -e "${BLUE}Starting workflow validation...${NC}"
echo ""

# Check if workflow directory exists
if [[ ! -d "$WORKFLOW_DIR" ]]; then
    echo -e "${RED}❌ Workflow directory not found: $WORKFLOW_DIR${NC}"
    exit 1
fi

# Get list of workflow files
WORKFLOW_FILES=$(find "$WORKFLOW_DIR" -name "*.yml" -o -name "*.yaml")

if [[ -z "$WORKFLOW_FILES" ]]; then
    echo -e "${YELLOW}⚠️  No workflow files found in $WORKFLOW_DIR${NC}"
    exit 0
fi

# Validate each workflow file
for workflow_file in $WORKFLOW_FILES; do
    echo ""
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}Validating: $(basename "$workflow_file")${NC}"
    echo -e "${BLUE}===========================================${NC}"
    
    # Validate YAML syntax
    validate_yaml "$workflow_file"
    
    # Check workflow structure
    check_workflow_structure "$workflow_file"
    
    # Check Flutter-specific requirements
    check_flutter_workflow "$workflow_file"
    
    echo -e "${GREEN}✅ Validation completed for $(basename "$workflow_file")${NC}"
done

echo ""
echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}VALIDATION SUMMARY${NC}"
echo -e "${BLUE}===========================================${NC}"

# Count total workflows
TOTAL_WORKFLOWS=$(echo "$WORKFLOW_FILES" | wc -l)
echo -e "${BLUE}Total workflows validated:${NC} $TOTAL_WORKFLOWS"

if [[ $VALIDATION_ERRORS -eq 0 ]]; then
    echo -e "${GREEN}🎉 All workflows passed validation!${NC}"
    echo -e "${GREEN}✅ No errors found${NC}"
    exit 0
else
    echo -e "${RED}❌ Validation failed with $VALIDATION_ERRORS error(s)${NC}"
    echo -e "${YELLOW}Please review and fix the issues above${NC}"
    exit 1
fi