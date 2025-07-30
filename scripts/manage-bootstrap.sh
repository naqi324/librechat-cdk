#!/bin/bash
# manage-bootstrap.sh - Unified CDK bootstrap management script

set -e

# Enable AWS SDK to load config file (required for SSO and advanced auth)
export AWS_SDK_LOAD_CONFIG=1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get AWS account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
REGION=$(aws configure get region || echo "us-east-1")

# Default CDK bootstrap resources
DEFAULT_QUALIFIER="hnb659fds"
ECR_REPO="cdk-${DEFAULT_QUALIFIER}-container-assets-${ACCOUNT_ID}-${REGION}"
S3_BUCKET="cdk-${DEFAULT_QUALIFIER}-assets-${ACCOUNT_ID}-${REGION}"
STACK_NAME="CDKToolkit"

show_help() {
    echo "CDK Bootstrap Manager"
    echo "===================="
    echo
    echo "Usage: $0 [command]"
    echo
    echo "Commands:"
    echo "  status    Check the current bootstrap status (default)"
    echo "  fix       Fix bootstrap issues interactively"
    echo "  clean     Clean all bootstrap resources and re-bootstrap"
    echo "  custom    Bootstrap with custom qualifier (avoids conflicts)"
    echo "  help      Show this help message"
    echo
    echo "Examples:"
    echo "  $0              # Check status"
    echo "  $0 status       # Check status"
    echo "  $0 fix          # Fix bootstrap issues"
    echo "  $0 clean        # Clean and re-bootstrap"
    echo "  $0 custom       # Use custom qualifier"
}

prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    if [ -z "$default" ]; then
        read -p "$prompt: " value
    else
        read -p "$prompt [$default]: " value
        value="${value:-$default}"
    fi
    eval "$var_name='$value'"
}

check_aws_config() {
    if [ -z "$ACCOUNT_ID" ]; then
        echo -e "${RED}AWS credentials not configured or expired${NC}"
        
        if [ -n "$AWS_PROFILE" ] && grep -q "sso_start_url" ~/.aws/config 2>/dev/null; then
            echo -e "${YELLOW}SSO session appears to be expired${NC}"
            echo "Please run: aws sso login --profile $AWS_PROFILE"
        else
            echo "Please run 'aws configure' or set up AWS SSO"
        fi
        exit 1
    fi
    echo -e "${GREEN}✓ AWS CLI configured - Account: $ACCOUNT_ID, Region: $REGION${NC}"
}

check_status() {
    echo -e "${BLUE}CDK Bootstrap Status Check${NC}"
    echo "=========================="
    
    check_aws_config
    
    echo -e "${YELLOW}Account: ${ACCOUNT_ID}${NC}"
    echo -e "${YELLOW}Region: ${REGION}${NC}"
    echo

    # Check CloudFormation stack
    echo -e "${BLUE}Checking CDKToolkit stack...${NC}"
    STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DOES_NOT_EXIST")
    
    if [ "$STACK_STATUS" == "DOES_NOT_EXIST" ]; then
        echo -e "${RED}❌ CDKToolkit stack not found${NC}"
        echo "   Run '$0 fix' to bootstrap"
        return 1
    elif [ "$STACK_STATUS" == "CREATE_COMPLETE" ] || [ "$STACK_STATUS" == "UPDATE_COMPLETE" ]; then
        echo -e "${GREEN}✅ CDKToolkit stack is healthy (Status: $STACK_STATUS)${NC}"
    else
        echo -e "${RED}⚠️  CDKToolkit stack status: $STACK_STATUS${NC}"
        echo "   Run '$0 fix' to repair"
        return 1
    fi
    
    # Check ECR repository
    echo
    echo -e "${BLUE}Checking ECR repository...${NC}"
    if aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION &>/dev/null; then
        echo -e "${GREEN}✅ ECR repository exists: $ECR_REPO${NC}"
    else
        echo -e "${YELLOW}⚠️  ECR repository not found${NC}"
    fi
    
    # Check S3 bucket
    echo
    echo -e "${BLUE}Checking S3 bucket...${NC}"
    if aws s3api head-bucket --bucket $S3_BUCKET --region $REGION 2>/dev/null; then
        echo -e "${GREEN}✅ S3 bucket exists: $S3_BUCKET${NC}"
    else
        echo -e "${YELLOW}⚠️  S3 bucket not found${NC}"
    fi
    
    echo
    echo -e "${GREEN}Bootstrap check complete${NC}"
    return 0
}

fix_bootstrap() {
    echo -e "${BLUE}CDK Bootstrap Fix${NC}"
    echo "================="
    
    check_aws_config
    
    # Check current status
    STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DOES_NOT_EXIST")
    
    if [ "$STACK_STATUS" == "CREATE_COMPLETE" ] || [ "$STACK_STATUS" == "UPDATE_COMPLETE" ]; then
        echo -e "${GREEN}✅ Bootstrap stack is already healthy${NC}"
        return 0
    fi
    
    if [ "$STACK_STATUS" == "DOES_NOT_EXIST" ]; then
        echo -e "${YELLOW}No bootstrap stack found. Running bootstrap...${NC}"
        npx cdk bootstrap aws://${ACCOUNT_ID}/${REGION}
    else
        echo -e "${YELLOW}Bootstrap stack exists but is in state: $STACK_STATUS${NC}"
        echo
        echo "This usually means there are conflicting resources."
        echo
        echo "Options:"
        echo "1) Try to fix by re-running bootstrap"
        echo "2) Clean everything and start fresh"
        echo "3) Exit and fix manually"
        echo
        read -p "Select option (1-3): " OPTION
        
        case $OPTION in
            1)
                echo -e "${BLUE}Attempting to fix by re-running bootstrap...${NC}"
                npx cdk bootstrap aws://${ACCOUNT_ID}/${REGION} --force || {
                    echo -e "${RED}Bootstrap failed. Try option 2 (clean) instead.${NC}"
                    exit 1
                }
                ;;
            2)
                clean_bootstrap
                ;;
            3)
                echo -e "${YELLOW}Exiting. To manually fix:${NC}"
                echo "1. Go to AWS CloudFormation console"
                echo "2. Delete the $STACK_NAME stack"
                echo "3. Run: npx cdk bootstrap"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                exit 1
                ;;
        esac
    fi
}

clean_bootstrap() {
    echo -e "${RED}⚠️  WARNING: This will delete all CDK bootstrap resources${NC}"
    echo
    read -p "Type 'CLEAN' to confirm: " CONFIRM
    
    if [ "$CONFIRM" != "CLEAN" ]; then
        echo -e "${GREEN}Clean cancelled${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Cleaning CDK bootstrap resources...${NC}"
    
    # Delete CloudFormation stack
    if aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION &>/dev/null; then
        echo "Deleting CloudFormation stack..."
        aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION
        aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $REGION 2>/dev/null || true
    fi
    
    # Force delete ECR repository
    if aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION &>/dev/null; then
        echo "Deleting ECR repository..."
        aws ecr delete-repository --repository-name $ECR_REPO --force --region $REGION 2>/dev/null || true
    fi
    
    # Force delete S3 bucket (check all regions since S3 is global)
    echo "Checking for S3 bucket: $S3_BUCKET"
    
    # First try to get bucket location
    BUCKET_REGION=$(aws s3api get-bucket-location --bucket $S3_BUCKET 2>/dev/null | jq -r '.LocationConstraint // "us-east-1"' || echo "")
    
    if [ ! -z "$BUCKET_REGION" ]; then
        # Bucket exists somewhere
        if [ "$BUCKET_REGION" = "null" ]; then
            BUCKET_REGION="us-east-1"
        fi
        echo "Found bucket in region: $BUCKET_REGION"
        
        # Empty the bucket first
        echo "Emptying bucket..."
        aws s3 rm s3://$S3_BUCKET --recursive --region $BUCKET_REGION 2>/dev/null || true
        
        # Delete all versions if versioning is enabled
        aws s3api delete-objects --bucket $S3_BUCKET --region $BUCKET_REGION \
            --delete "$(aws s3api list-object-versions --bucket $S3_BUCKET --region $BUCKET_REGION \
            --output json --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' 2>/dev/null || echo '{}')" 2>/dev/null || true
        
        # Delete the bucket
        echo "Deleting bucket..."
        aws s3api delete-bucket --bucket $S3_BUCKET --region $BUCKET_REGION 2>/dev/null || true
        aws s3 rb s3://$S3_BUCKET --force --region $BUCKET_REGION 2>/dev/null || true
        
        # Wait a moment for deletion to propagate
        sleep 5
    else
        echo "Bucket not found or not accessible"
    fi
    
    # Also check for ECS-related CDK resources
    echo "Checking for CDK-related ECS resources..."
    
    # Clean up any CDK-related ECR repositories that might block bootstrap
    CDK_ECR_REPOS=$(aws ecr describe-repositories --query "repositories[?contains(repositoryName, 'cdk-${DEFAULT_QUALIFIER}')].repositoryName" --output text 2>/dev/null || echo "")
    if [ ! -z "$CDK_ECR_REPOS" ]; then
        for repo in $CDK_ECR_REPOS; do
            echo "  Deleting ECR repository: $repo"
            aws ecr delete-repository --repository-name "$repo" --force 2>/dev/null || true
        done
    fi
    
    echo -e "${GREEN}✅ Cleanup complete${NC}"
    echo
    echo -e "${BLUE}Running fresh bootstrap...${NC}"
    npx cdk bootstrap aws://${ACCOUNT_ID}/${REGION}
}

custom_bootstrap() {
    echo -e "${BLUE}CDK Bootstrap with Custom Qualifier${NC}"
    echo "===================================="
    
    check_aws_config
    
    echo -e "${YELLOW}⚠️  Using a custom qualifier helps avoid S3 bucket naming conflicts${NC}"
    echo -e "${YELLOW}   when multiple users share the same AWS account.${NC}"
    echo
    echo "The qualifier must be:"
    echo "  • 4-10 lowercase alphanumeric characters"
    echo "  • Must start with a letter"
    echo "  • Must be unique in your AWS account"
    echo
    
    # Generate a suggested qualifier
    SUGGESTED_QUALIFIER="lc$(date +%y%m%d)"
    
    while true; do
        prompt_with_default "Enter custom qualifier" "$SUGGESTED_QUALIFIER" CUSTOM_QUALIFIER
        
        # Validate qualifier
        if ! [[ "$CUSTOM_QUALIFIER" =~ ^[a-z][a-z0-9]{3,9}$ ]]; then
            echo -e "${RED}Invalid qualifier. Must be 4-10 lowercase alphanumeric characters starting with a letter.${NC}"
            continue
        fi
        
        # Check if S3 bucket would conflict
        TEST_BUCKET="cdk-${CUSTOM_QUALIFIER}-assets-${ACCOUNT_ID}-${REGION}"
        echo "Testing bucket name: $TEST_BUCKET"
        
        if aws s3api head-bucket --bucket "$TEST_BUCKET" 2>/dev/null; then
            echo -e "${RED}A bucket with this qualifier already exists: $TEST_BUCKET${NC}"
            echo "Please choose a different qualifier."
            continue
        fi
        
        echo -e "${GREEN}✅ Qualifier is available${NC}"
        break
    done
    
    echo
    echo -e "${BLUE}Bootstrap Configuration:${NC}"
    echo "  Account: $ACCOUNT_ID"
    echo "  Region: $REGION"
    echo "  Qualifier: $CUSTOM_QUALIFIER"
    echo "  S3 Bucket: cdk-${CUSTOM_QUALIFIER}-assets-${ACCOUNT_ID}-${REGION}"
    echo "  ECR Repository: cdk-${CUSTOM_QUALIFIER}-container-assets-${ACCOUNT_ID}-${REGION}"
    echo
    
    read -p "Proceed with bootstrap? (y/n) [y]: " proceed
    proceed="${proceed:-y}"
    
    if [ "$proceed" != "y" ]; then
        echo -e "${YELLOW}Bootstrap cancelled${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Running CDK bootstrap with custom qualifier...${NC}"
    
    # Bootstrap with custom qualifier
    npx cdk bootstrap aws://${ACCOUNT_ID}/${REGION} \
        --qualifier $CUSTOM_QUALIFIER \
        --toolkit-stack-name CDKToolkit-$CUSTOM_QUALIFIER || {
        echo -e "${RED}Bootstrap failed${NC}"
        return 1
    }
    
    echo
    echo -e "${GREEN}✅ Bootstrap complete!${NC}"
    echo
    echo -e "${YELLOW}IMPORTANT: You must now use this qualifier in your CDK deployments:${NC}"
    echo
    echo "  1. Set the environment variable:"
    echo "     export CDK_QUALIFIER=$CUSTOM_QUALIFIER"
    echo
    echo "  2. Or add to your .env file:"
    echo "     CDK_QUALIFIER=$CUSTOM_QUALIFIER"
    echo
    echo "  3. Or use in cdk.json:"
    echo "     {\"context\": {\"@aws-cdk/core:bootstrapQualifier\": \"$CUSTOM_QUALIFIER\"}}"
    echo
    echo -e "${BLUE}The stack will automatically use this qualifier if you set CDK_QUALIFIER.${NC}"
}

# Main script logic
case "${1:-status}" in
    status)
        check_status
        ;;
    fix)
        fix_bootstrap
        ;;
    clean)
        clean_bootstrap
        ;;
    custom)
        custom_bootstrap
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo
        show_help
        exit 1
        ;;
esac