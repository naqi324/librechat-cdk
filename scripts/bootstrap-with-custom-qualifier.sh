#!/bin/bash
# bootstrap-with-custom-qualifier.sh - Bootstrap CDK with a unique qualifier to avoid conflicts

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}CDK Bootstrap with Custom Qualifier${NC}"
echo "===================================="

# Get AWS account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region || echo "us-east-1")

# Generate a unique qualifier (9 chars max, alphanumeric lowercase)
TIMESTAMP=$(date +%s)
QUALIFIER="lc${TIMESTAMP: -7}"

echo -e "${YELLOW}Account: ${ACCOUNT_ID}${NC}"
echo -e "${YELLOW}Region: ${REGION}${NC}"
echo -e "${YELLOW}New Qualifier: ${QUALIFIER}${NC}"
echo

echo "This will create new CDK bootstrap resources with a unique qualifier"
echo "to avoid conflicts with existing resources."
echo

read -p "Continue? (y/n) [y]: " CONTINUE
CONTINUE="${CONTINUE:-y}"

if [ "$CONTINUE" != "y" ]; then
    echo "Cancelled"
    exit 0
fi

# Update cdk.json with the new qualifier
echo -e "\n${BLUE}Updating cdk.json with custom qualifier...${NC}"

if command -v jq &> /dev/null; then
    # Use jq if available
    cp cdk.json cdk.json.backup
    jq --arg qual "$QUALIFIER" '.context."@aws-cdk/core:bootstrapQualifier" = $qual' cdk.json > cdk.json.tmp && mv cdk.json.tmp cdk.json
    echo -e "${GREEN}✅ Updated cdk.json${NC}"
else
    # Manual instruction if jq not available
    echo -e "${YELLOW}Please manually add the following to your cdk.json:${NC}"
    echo
    echo '  "context": {'
    echo '    "@aws-cdk/core:bootstrapQualifier": "'$QUALIFIER'"'
    echo '  }'
    echo
    read -p "Press enter when you've updated cdk.json..."
fi

# Run bootstrap with custom qualifier
echo -e "\n${BLUE}Running CDK bootstrap with custom qualifier...${NC}"

npx cdk bootstrap aws://${ACCOUNT_ID}/${REGION} \
    --qualifier $QUALIFIER \
    --toolkit-stack-name LibreChatCDKToolkit-${QUALIFIER}

echo -e "\n${GREEN}✅ Bootstrap complete!${NC}"
echo
echo "Important notes:"
echo "1. Your CDK is now bootstrapped with qualifier: $QUALIFIER"
echo "2. The toolkit stack is named: LibreChatCDKToolkit-${QUALIFIER}"
echo "3. All deployments will use this custom qualifier"
echo "4. Keep cdk.json in version control to maintain this configuration"
echo
echo "Resources created:"
echo "- S3 Bucket: cdk-${QUALIFIER}-assets-${ACCOUNT_ID}-${REGION}"
echo "- ECR Repository: cdk-${QUALIFIER}-container-assets-${ACCOUNT_ID}-${REGION}"
echo "- Toolkit Stack: LibreChatCDKToolkit-${QUALIFIER}"
echo
echo "You can now run: npm run deploy"