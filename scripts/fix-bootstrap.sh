#!/bin/bash
# fix-bootstrap.sh - Fix CDK bootstrap conflicts

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}CDK Bootstrap Conflict Resolution${NC}"
echo "=================================="

# Get AWS account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region || echo "us-east-1")
STACK_NAME="CDKToolkit"

echo -e "${YELLOW}Account: ${ACCOUNT_ID}${NC}"
echo -e "${YELLOW}Region: ${REGION}${NC}"
echo

# Check if CDKToolkit stack exists
echo -e "${BLUE}Checking existing CDKToolkit stack...${NC}"
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DOES_NOT_EXIST")

if [ "$STACK_STATUS" != "DOES_NOT_EXIST" ]; then
    echo -e "${YELLOW}Found existing CDKToolkit stack with status: ${STACK_STATUS}${NC}"
    
    if [ "$STACK_STATUS" == "ROLLBACK_COMPLETE" ] || [ "$STACK_STATUS" == "CREATE_FAILED" ]; then
        echo -e "${RED}Stack is in failed state and needs to be deleted${NC}"
        echo
        echo "Options:"
        echo "1) Delete the existing CDKToolkit stack and re-bootstrap"
        echo "2) Use a custom bootstrap stack with a different qualifier"
        echo "3) Exit and manually fix"
        echo
        read -p "Select option (1-3): " OPTION
        
        case $OPTION in
            1)
                echo -e "${YELLOW}Deleting existing CDKToolkit stack...${NC}"
                
                # First, try to empty and delete the ECR repository
                ECR_REPO="cdk-hnb659fds-container-assets-${ACCOUNT_ID}-${REGION}"
                echo -e "${BLUE}Checking for ECR repository: ${ECR_REPO}${NC}"
                
                if aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION &>/dev/null; then
                    echo -e "${YELLOW}Deleting images from ECR repository...${NC}"
                    aws ecr list-images --repository-name $ECR_REPO --region $REGION --query 'imageIds[*]' --output json | \
                    jq -r '.[] | @base64' | while read IMAGE; do
                        IMAGE_ID=$(echo $IMAGE | base64 -d)
                        aws ecr batch-delete-image --repository-name $ECR_REPO --image-ids "$IMAGE_ID" --region $REGION &>/dev/null || true
                    done
                fi
                
                # Delete the stack
                aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION
                echo -e "${BLUE}Waiting for stack deletion...${NC}"
                aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $REGION
                echo -e "${GREEN}✅ Stack deleted successfully${NC}"
                
                # Re-bootstrap
                echo -e "${BLUE}Re-bootstrapping CDK...${NC}"
                npx cdk bootstrap aws://${ACCOUNT_ID}/${REGION}
                ;;
                
            2)
                echo -e "${BLUE}Using custom bootstrap qualifier...${NC}"
                QUALIFIER="librechat$(date +%s)"
                echo -e "${YELLOW}New qualifier: ${QUALIFIER}${NC}"
                
                # Bootstrap with custom qualifier
                npx cdk bootstrap aws://${ACCOUNT_ID}/${REGION} \
                    --qualifier $QUALIFIER \
                    --toolkit-stack-name LibreChatCDKToolkit
                
                # Update cdk.json to use the new qualifier
                echo -e "${BLUE}Updating cdk.json with new qualifier...${NC}"
                if command -v jq &> /dev/null; then
                    jq --arg qual "$QUALIFIER" '.context."@aws-cdk/core:bootstrapQualifier" = $qual' cdk.json > cdk.json.tmp && mv cdk.json.tmp cdk.json
                else
                    echo -e "${YELLOW}Please manually add the following to your cdk.json context:${NC}"
                    echo "\"@aws-cdk/core:bootstrapQualifier\": \"$QUALIFIER\""
                fi
                ;;
                
            3)
                echo -e "${YELLOW}Exiting. Please manually resolve the issue.${NC}"
                echo
                echo "To manually fix:"
                echo "1. Go to AWS CloudFormation console"
                echo "2. Delete the CDKToolkit stack"
                echo "3. Run: npx cdk bootstrap"
                exit 0
                ;;
                
            *)
                echo -e "${RED}Invalid option${NC}"
                exit 1
                ;;
        esac
    else
        echo -e "${GREEN}CDKToolkit stack exists and is healthy${NC}"
        echo -e "${YELLOW}If you're still having issues, you may want to delete and re-create it${NC}"
    fi
else
    echo -e "${BLUE}No existing CDKToolkit stack found. Running bootstrap...${NC}"
    npx cdk bootstrap aws://${ACCOUNT_ID}/${REGION}
fi

echo
echo -e "${GREEN}✅ Bootstrap process complete!${NC}"
echo
echo "Next steps:"
echo "1. Run 'npm run deploy' to deploy the LibreChat stack"
echo "2. If you used a custom qualifier, make sure to commit the changes to cdk.json"