#!/bin/bash
# acknowledge-cdk-notices.sh - Acknowledge CDK CLI notices

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Acknowledging CDK Notices${NC}"
echo "========================"

# Acknowledge telemetry notice (34892)
echo "Acknowledging notice 34892 (CDK telemetry)..."
npx cdk acknowledge 34892

# Acknowledge CLI version divergence notice (32775)
echo "Acknowledging notice 32775 (CLI version divergence)..."
npx cdk acknowledge 32775

echo -e "\n${GREEN}✅ CDK notices acknowledged${NC}"
echo
echo "These notices will no longer appear in CDK output."