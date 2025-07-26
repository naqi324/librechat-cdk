#!/bin/bash
# check-bootstrap-status.sh - Check CDK bootstrap status

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}CDK Bootstrap Status Check${NC}"
echo "=========================="

# Get AWS account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "Not configured")
REGION=$(aws configure get region || echo "us-east-1")

if [ "$ACCOUNT_ID" == "Not configured" ]; then
    echo -e "${RED}AWS CLI is not configured. Please run 'aws configure'${NC}"
    exit 1
fi

echo -e "${YELLOW}Account: ${ACCOUNT_ID}${NC}"
echo -e "${YELLOW}Region: ${REGION}${NC}"
echo

# Check CDKToolkit stack
echo -e "${BLUE}Checking CDKToolkit stack...${NC}"
STACK_INFO=$(aws cloudformation describe-stacks --stack-name CDKToolkit --region $REGION 2>/dev/null || echo "NOT_FOUND")

if [ "$STACK_INFO" == "NOT_FOUND" ]; then
    echo -e "${RED}❌ CDKToolkit stack not found${NC}"
    echo "   Run 'npx cdk bootstrap' to create it"
else
    STACK_STATUS=$(echo "$STACK_INFO" | jq -r '.Stacks[0].StackStatus')
    CREATION_TIME=$(echo "$STACK_INFO" | jq -r '.Stacks[0].CreationTime')
    
    if [ "$STACK_STATUS" == "CREATE_COMPLETE" ] || [ "$STACK_STATUS" == "UPDATE_COMPLETE" ]; then
        echo -e "${GREEN}✅ CDKToolkit stack is healthy${NC}"
    else
        echo -e "${RED}⚠️  CDKToolkit stack status: $STACK_STATUS${NC}"
    fi
    echo "   Created: $CREATION_TIME"
    
    # Check for ECR repository
    ECR_REPO="cdk-hnb659fds-container-assets-${ACCOUNT_ID}-${REGION}"
    echo
    echo -e "${BLUE}Checking ECR repository...${NC}"
    if aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION &>/dev/null; then
        echo -e "${GREEN}✅ ECR repository exists: $ECR_REPO${NC}"
    else
        echo -e "${YELLOW}⚠️  ECR repository not found (may use custom qualifier)${NC}"
    fi
fi

# Check for custom qualifier in cdk.json
echo
echo -e "${BLUE}Checking for custom bootstrap qualifier...${NC}"
if [ -f cdk.json ]; then
    QUALIFIER=$(jq -r '.context."@aws-cdk/core:bootstrapQualifier" // "default"' cdk.json 2>/dev/null || echo "default")
    if [ "$QUALIFIER" != "default" ] && [ "$QUALIFIER" != "null" ]; then
        echo -e "${YELLOW}Custom qualifier found: $QUALIFIER${NC}"
        
        # Check for custom toolkit stack
        CUSTOM_STACK="LibreChatCDKToolkit"
        CUSTOM_INFO=$(aws cloudformation describe-stacks --stack-name $CUSTOM_STACK --region $REGION 2>/dev/null || echo "NOT_FOUND")
        if [ "$CUSTOM_INFO" != "NOT_FOUND" ]; then
            echo -e "${GREEN}✅ Custom toolkit stack found: $CUSTOM_STACK${NC}"
        fi
    else
        echo "Using default CDK qualifier"
    fi
fi

echo
echo -e "${BLUE}Summary:${NC}"
echo "--------"
if [ "$STACK_INFO" != "NOT_FOUND" ] && ([ "$STACK_STATUS" == "CREATE_COMPLETE" ] || [ "$STACK_STATUS" == "UPDATE_COMPLETE" ]); then
    echo -e "${GREEN}✅ CDK bootstrap is properly configured${NC}"
    echo "   You can proceed with deployment"
elif [ "$STACK_STATUS" == "ROLLBACK_COMPLETE" ] || [ "$STACK_STATUS" == "CREATE_FAILED" ]; then
    echo -e "${RED}❌ CDK bootstrap is in failed state${NC}"
    echo "   Run './scripts/fix-bootstrap.sh' to fix it"
else
    echo -e "${YELLOW}⚠️  CDK bootstrap needs attention${NC}"
    echo "   Run './scripts/fix-bootstrap.sh' for options"
fi