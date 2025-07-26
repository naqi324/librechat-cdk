#!/bin/bash
# deep-clean-bootstrap.sh - Deep clean CDK bootstrap resources

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                    ⚠️  WARNING ⚠️                           ║${NC}"
echo -e "${RED}║                                                           ║${NC}"
echo -e "${RED}║  This will DELETE ALL CDK Bootstrap resources including:  ║${NC}"
echo -e "${RED}║  - CDKToolkit CloudFormation stack                        ║${NC}"
echo -e "${RED}║  - ECR repositories for CDK assets                        ║${NC}"
echo -e "${RED}║  - S3 buckets for CDK assets                              ║${NC}"
echo -e "${RED}║  - SSM parameters for CDK bootstrap                       ║${NC}"
echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
echo

# Get AWS account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region || echo "us-east-1")

echo -e "${YELLOW}Account: ${ACCOUNT_ID}${NC}"
echo -e "${YELLOW}Region: ${REGION}${NC}"
echo

# Default CDK bootstrap resources
DEFAULT_QUALIFIER="hnb659fds"
ECR_REPO="cdk-${DEFAULT_QUALIFIER}-container-assets-${ACCOUNT_ID}-${REGION}"
S3_BUCKET="cdk-${DEFAULT_QUALIFIER}-assets-${ACCOUNT_ID}-${REGION}"
STACK_NAME="CDKToolkit"

echo "Resources to be cleaned:"
echo "- CloudFormation Stack: $STACK_NAME"
echo "- ECR Repository: $ECR_REPO"
echo "- S3 Bucket: $S3_BUCKET"
echo "- SSM Parameters: /cdk-bootstrap/${DEFAULT_QUALIFIER}/*"
echo

read -p "Type 'DELETE' to confirm deletion of all CDK bootstrap resources: " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
    echo -e "${GREEN}Cleanup cancelled - no resources were deleted${NC}"
    exit 0
fi

echo -e "\n${BLUE}Starting deep cleanup...${NC}\n"

# 1. Delete CloudFormation Stack (if exists)
echo -e "${BLUE}1. Checking CloudFormation stack...${NC}"
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DOES_NOT_EXIST")

if [ "$STACK_STATUS" != "DOES_NOT_EXIST" ]; then
    echo -e "${YELLOW}Found stack with status: $STACK_STATUS${NC}"
    
    # If stack is in DELETE_IN_PROGRESS, wait for it
    if [ "$STACK_STATUS" == "DELETE_IN_PROGRESS" ]; then
        echo "Stack deletion already in progress, waiting..."
        aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $REGION 2>/dev/null || true
    else
        echo "Deleting CloudFormation stack..."
        aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION 2>/dev/null || true
        echo "Waiting for stack deletion..."
        aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $REGION 2>/dev/null || true
    fi
    echo -e "${GREEN}✅ CloudFormation stack removed${NC}"
else
    echo "No CloudFormation stack found"
fi

# 2. Delete ECR Repository
echo -e "\n${BLUE}2. Cleaning ECR repository...${NC}"
if aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION &>/dev/null; then
    echo "Found ECR repository: $ECR_REPO"
    
    # Delete all images first
    echo "Deleting all images in repository..."
    IMAGE_DIGESTS=$(aws ecr list-images --repository-name $ECR_REPO --region $REGION --query 'imageIds[*].imageDigest' --output text 2>/dev/null || echo "")
    
    if [ ! -z "$IMAGE_DIGESTS" ]; then
        for digest in $IMAGE_DIGESTS; do
            aws ecr batch-delete-image --repository-name $ECR_REPO --image-ids imageDigest=$digest --region $REGION &>/dev/null || true
        done
    fi
    
    # Delete the repository
    echo "Deleting ECR repository..."
    aws ecr delete-repository --repository-name $ECR_REPO --region $REGION --force &>/dev/null || true
    echo -e "${GREEN}✅ ECR repository deleted${NC}"
else
    echo "No ECR repository found"
fi

# 3. Delete S3 Bucket
echo -e "\n${BLUE}3. Cleaning S3 bucket...${NC}"
if aws s3api head-bucket --bucket $S3_BUCKET --region $REGION 2>/dev/null; then
    echo "Found S3 bucket: $S3_BUCKET"
    
    # Delete all objects including versions
    echo "Deleting all objects in bucket..."
    aws s3 rm s3://$S3_BUCKET --recursive --region $REGION 2>/dev/null || true
    
    # Delete all object versions (if versioning was enabled)
    echo "Deleting all object versions..."
    aws s3api list-object-versions --bucket $S3_BUCKET --region $REGION --output json 2>/dev/null | \
    jq -r '.Versions[]? | "--key '\''\(.Key)'\'' --version-id \(.VersionId)"' | \
    xargs -I {} aws s3api delete-object --bucket $S3_BUCKET {} --region $REGION 2>/dev/null || true
    
    # Delete all delete markers
    aws s3api list-object-versions --bucket $S3_BUCKET --region $REGION --output json 2>/dev/null | \
    jq -r '.DeleteMarkers[]? | "--key '\''\(.Key)'\'' --version-id \(.VersionId)"' | \
    xargs -I {} aws s3api delete-object --bucket $S3_BUCKET {} --region $REGION 2>/dev/null || true
    
    # Delete the bucket
    echo "Deleting S3 bucket..."
    aws s3api delete-bucket --bucket $S3_BUCKET --region $REGION 2>/dev/null || true
    echo -e "${GREEN}✅ S3 bucket deleted${NC}"
else
    echo "No S3 bucket found"
fi

# 4. Delete SSM Parameters
echo -e "\n${BLUE}4. Cleaning SSM parameters...${NC}"
SSM_PARAMS=$(aws ssm describe-parameters --region $REGION --parameter-filters "Key=Name,Option=BeginsWith,Values=/cdk-bootstrap/${DEFAULT_QUALIFIER}/" --query 'Parameters[*].Name' --output text 2>/dev/null || echo "")

if [ ! -z "$SSM_PARAMS" ]; then
    echo "Found SSM parameters to delete"
    for param in $SSM_PARAMS; do
        echo "Deleting parameter: $param"
        aws ssm delete-parameter --name $param --region $REGION 2>/dev/null || true
    done
    echo -e "${GREEN}✅ SSM parameters deleted${NC}"
else
    echo "No SSM parameters found"
fi

# 5. Check for any custom bootstrap stacks
echo -e "\n${BLUE}5. Checking for custom bootstrap stacks...${NC}"
CUSTOM_STACKS=$(aws cloudformation list-stacks --region $REGION --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE CREATE_FAILED --query "StackSummaries[?contains(StackName, 'CDKToolkit')].StackName" --output text 2>/dev/null || echo "")

if [ ! -z "$CUSTOM_STACKS" ] && [ "$CUSTOM_STACKS" != "CDKToolkit" ]; then
    echo -e "${YELLOW}Found additional CDK toolkit stacks:${NC}"
    echo "$CUSTOM_STACKS"
    echo -e "${YELLOW}You may want to delete these manually if they're not in use${NC}"
fi

echo -e "\n${GREEN}✅ Deep cleanup complete!${NC}"
echo
echo "Next steps:"
echo "1. Run 'npx cdk bootstrap' to create a fresh bootstrap environment"
echo "2. Then run 'npm run deploy' to deploy your stack"
echo
echo -e "${YELLOW}Note: If you're still having issues, try:${NC}"
echo "- Using a custom bootstrap qualifier: npx cdk bootstrap --qualifier myqualifier"
echo "- Checking for any IAM policies that might be preventing resource deletion"