#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧪 Testing CDK Deployment Configurations${NC}"
echo "======================================"
echo "This will test synthesis without AWS credentials"
echo

# Set dummy credentials for synthesis
export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
export AWS_DEFAULT_REGION=us-east-1

# Function to test configuration
test_config() {
    local config=$1
    local description=$2
    echo -e "\n${BLUE}📋 Testing: $config${NC} - $description"
    
    # Synthesize
    if cdk synth -c configSource=$config --quiet 2>/dev/null; then
        # Count resources
        TEMPLATE_FILE=$(find cdk.out -name "*.template.json" | head -1)
        if [ -f "$TEMPLATE_FILE" ]; then
            RESOURCE_COUNT=$(cat "$TEMPLATE_FILE" | jq '.Resources | length' 2>/dev/null || echo "?")
            TEMPLATE_SIZE=$(ls -lh "$TEMPLATE_FILE" | awk '{print $5}')
            
            # Check for slow resources
            DOCDB_COUNT=$(cat "$TEMPLATE_FILE" | jq '[.Resources[] | select(.Type | contains("DocDB"))] | length' 2>/dev/null || echo "0")
            RDS_COUNT=$(cat "$TEMPLATE_FILE" | jq '[.Resources[] | select(.Type | contains("RDS"))] | length' 2>/dev/null || echo "0")
            ECS_COUNT=$(cat "$TEMPLATE_FILE" | jq '[.Resources[] | select(.Type | contains("ECS"))] | length' 2>/dev/null || echo "0")
            CUSTOM_COUNT=$(cat "$TEMPLATE_FILE" | jq '[.Resources[] | select(.Type | startswith("Custom::"))] | length' 2>/dev/null || echo "0")
            LAMBDA_COUNT=$(cat "$TEMPLATE_FILE" | jq '[.Resources[] | select(.Type == "AWS::Lambda::Function")] | length' 2>/dev/null || echo "0")
            
            echo -e "  ${GREEN}✅ Synthesis successful${NC}"
            echo "  📊 Total Resources: $RESOURCE_COUNT"
            echo "  📦 Template size: $TEMPLATE_SIZE"
            echo "  🗄️  Databases: RDS=$RDS_COUNT, DocumentDB=$DOCDB_COUNT"
            echo "  📦 Compute: ECS=$ECS_COUNT, Lambda=$LAMBDA_COUNT"
            echo "  🔧 Custom resources: $CUSTOM_COUNT"
            
            # Estimate time (rough calculation)
            EST_TIME=$((10 + CUSTOM_COUNT * 5 + DOCDB_COUNT * 15 + RDS_COUNT * 10 + ECS_COUNT * 10))
            echo -e "  ⏱️  Estimated deployment time: ${EST_TIME}-$((EST_TIME + 20)) minutes"
            
            if [ $EST_TIME -gt 90 ]; then
                echo -e "  ${RED}⚠️  WARNING: Will exceed 2-hour token lifetime!${NC}"
            elif [ $EST_TIME -gt 60 ]; then
                echo -e "  ${YELLOW}⚡ CAUTION: Approaching token lifetime limit${NC}"
            else
                echo -e "  ${GREEN}✅ Should complete within token lifetime${NC}"
            fi
        else
            echo -e "  ${YELLOW}⚠️  No template file found${NC}"
        fi
    else
        echo -e "  ${RED}❌ Synthesis failed${NC}"
    fi
}

# Build first
echo -e "${BLUE}🔨 Building project...${NC}"
if npm run build >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Build successful${NC}"
else
    echo -e "${RED}❌ Build failed. Please run 'npm run build' to see errors.${NC}"
    exit 1
fi

# Test current configuration
echo -e "\n${BLUE}📊 Current Configuration (from .env)${NC}"
if cdk synth --quiet 2>/dev/null; then
    TEMPLATE_FILE=$(find cdk.out -name "*.template.json" | head -1)
    if [ -f "$TEMPLATE_FILE" ]; then
        RESOURCE_COUNT=$(cat "$TEMPLATE_FILE" | jq '.Resources | length' 2>/dev/null || echo "?")
        echo -e "  ${GREEN}✅ Current config has $RESOURCE_COUNT resources${NC}"
    fi
else
    echo -e "  ${RED}❌ Failed to synthesize current configuration${NC}"
fi

# Test configurations
test_config "ultra-minimal-dev" "Fastest deployment for Isengard"
test_config "minimal-dev" "Basic development setup"
test_config "standard-dev" "Standard development with features"

echo -e "\n${GREEN}✅ Testing complete!${NC}"
echo
echo "💡 Recommendations:"
echo "1. Use 'ultra-minimal-dev' for Isengard deployments"
echo "2. Deploy from AWS CloudShell to avoid token issues"
echo "3. Run 'node scripts/analyze-deployment.js' for detailed analysis"
echo
echo "To deploy with ultra-minimal configuration:"
echo -e "${YELLOW}cdk deploy -c configSource=ultra-minimal-dev --require-approval never${NC}"