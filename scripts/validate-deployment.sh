#!/bin/bash

# LibreChat CDK Deployment Validation Script
# This script performs pre and post deployment checks to ensure successful deployment

set -e

# Export AWS_SDK_LOAD_CONFIG for SSO support
export AWS_SDK_LOAD_CONFIG=1

echo "🔍 LibreChat CDK Deployment Validator"
echo "===================================="

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "success") echo -e "${GREEN}✓${NC} $message" ;;
        "error") echo -e "${RED}✗${NC} $message" ;;
        "warning") echo -e "${YELLOW}⚠${NC} $message" ;;
        "info") echo -e "ℹ $message" ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    echo -e "\n📋 Checking Prerequisites..."
    
    # Node.js version
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version | cut -d 'v' -f 2)
        MAJOR_VERSION=$(echo $NODE_VERSION | cut -d '.' -f 1)
        if [ "$MAJOR_VERSION" -ge 18 ]; then
            print_status "success" "Node.js version: v$NODE_VERSION"
        else
            print_status "error" "Node.js version v$NODE_VERSION is too old. Required: v18+"
            exit 1
        fi
    else
        print_status "error" "Node.js is not installed"
        exit 1
    fi
    
    # AWS CLI
    if command -v aws &> /dev/null; then
        AWS_VERSION=$(aws --version 2>&1 | cut -d ' ' -f 1 | cut -d '/' -f 2)
        print_status "success" "AWS CLI version: $AWS_VERSION"
    else
        print_status "error" "AWS CLI is not installed"
        exit 1
    fi
    
    # CDK CLI
    if command -v cdk &> /dev/null; then
        CDK_VERSION=$(cdk --version 2>&1 | cut -d ' ' -f 1)
        print_status "success" "CDK version: $CDK_VERSION"
    else
        print_status "error" "AWS CDK is not installed"
        exit 1
    fi
}

# Check AWS credentials
check_aws_credentials() {
    echo -e "\n🔐 Checking AWS Credentials..."
    
    if aws sts get-caller-identity &> /dev/null; then
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        REGION=$(aws configure get region || echo "us-east-1")
        print_status "success" "AWS Account: $ACCOUNT_ID"
        print_status "success" "AWS Region: $REGION"
    else
        print_status "error" "AWS credentials not configured or invalid"
        exit 1
    fi
}

# Check Lambda layers
check_lambda_layers() {
    echo -e "\n📦 Checking Lambda Layers..."
    
    # Check psycopg2 layer
    if [ -f "lambda/layers/psycopg2/psycopg2-layer.zip" ]; then
        SIZE=$(du -h lambda/layers/psycopg2/psycopg2-layer.zip | cut -f1)
        print_status "success" "psycopg2 layer exists ($SIZE)"
    else
        print_status "warning" "psycopg2 layer not found. Building..."
        (cd lambda/layers/psycopg2 && ./build-layer.sh)
    fi
    
    # Check pymongo layer
    if [ -f "lambda/layers/pymongo/pymongo-layer.zip" ]; then
        SIZE=$(du -h lambda/layers/pymongo/pymongo-layer.zip | cut -f1)
        print_status "success" "pymongo layer exists ($SIZE)"
    else
        print_status "warning" "pymongo layer not found. Building..."
        (cd lambda/layers/pymongo && ./build-layer.sh)
    fi
}

# Check TypeScript build
check_typescript_build() {
    echo -e "\n🏗️  Checking TypeScript Build..."
    
    if npm run build 2>&1 | grep -q "error"; then
        print_status "error" "TypeScript compilation failed"
        npm run build
        exit 1
    else
        print_status "success" "TypeScript compilation successful"
    fi
}

# Validate CDK synthesis
validate_cdk_synthesis() {
    echo -e "\n🔧 Validating CDK Synthesis..."
    
    CONFIG_SOURCE=${1:-minimal-dev}
    KEY_PAIR=${2:-}
    
    if [ -z "$KEY_PAIR" ] && [ "$CONFIG_SOURCE" != "production-ecs" ]; then
        print_status "error" "KEY_PAIR_NAME is required for EC2 deployments"
        exit 1
    fi
    
    CDK_COMMAND="cdk synth -c configSource=$CONFIG_SOURCE"
    if [ -n "$KEY_PAIR" ]; then
        CDK_COMMAND="$CDK_COMMAND -c keyPairName=$KEY_PAIR"
    fi
    
    if $CDK_COMMAND --quiet 2>&1 | grep -q "Error"; then
        print_status "error" "CDK synthesis failed"
        $CDK_COMMAND
        exit 1
    else
        print_status "success" "CDK synthesis successful"
    fi
}

# Check configuration compatibility
check_configuration_compatibility() {
    echo -e "\n🔧 Checking Configuration Compatibility..."
    
    CONFIG_SOURCE=${1:-minimal-dev}
    
    # Check for known good configurations
    case "$CONFIG_SOURCE" in
        "minimal-dev")
            print_status "success" "Minimal dev config: No DocumentDB, no NAT gateways required"
            ;;
        "development")
            print_status "success" "Development config: PostgreSQL only, no NAT gateways required"
            ;;
        "standard-dev"|"full-dev")
            print_status "warning" "This configuration may require NAT gateways for full functionality"
            ;;
        "production-ec2"|"production-ecs"|"enterprise")
            print_status "info" "Production configurations include NAT gateways and full features"
            ;;
    esac
    
    # Check environment variables for conflicts
    NAT_GATEWAYS=${NAT_GATEWAYS:-}
    DATABASE_ENGINE=${DATABASE_ENGINE:-}
    DEPLOYMENT_MODE=${DEPLOYMENT_MODE:-EC2}
    
    # Critical: DocumentDB without NAT gateways
    if [[ "$DATABASE_ENGINE" == *"documentdb"* ]] && [[ "$NAT_GATEWAYS" == "0" ]]; then
        print_status "error" "DocumentDB requires NAT gateways for Lambda initialization"
        echo "  Fix: Use 'postgres' engine only or set NAT_GATEWAYS=1"
        return 1
    fi
    
    # Critical: ECS without NAT gateways  
    if [[ "$DEPLOYMENT_MODE" == "ECS" ]] && [[ "$NAT_GATEWAYS" == "0" ]]; then
        print_status "error" "ECS deployment requires NAT gateways for container image pulls"
        echo "  Fix: Set NAT_GATEWAYS=1 for ECS deployments"
        return 1
    fi
    
    # Check for existing failed stacks
    STACK_NAME="LibreChatStack-${CONFIG_SOURCE//-*/}"
    if aws cloudformation describe-stacks --stack-name $STACK_NAME &> /dev/null 2>&1; then
        STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].StackStatus" --output text)
        if [[ "$STATUS" == "CREATE_FAILED" ]] || [[ "$STATUS" == "ROLLBACK_COMPLETE" ]]; then
            print_status "warning" "Existing stack $STACK_NAME is in failed state: $STATUS"
            echo "  Consider running 'cdk destroy' before redeploying"
        fi
    fi
}

# Check CDK bootstrap
check_cdk_bootstrap() {
    echo -e "\n🥾 Checking CDK Bootstrap..."
    
    REGION=$(aws configure get region || echo "us-east-1")
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    if aws cloudformation describe-stacks --stack-name CDKToolkit --region $REGION &> /dev/null; then
        print_status "success" "CDK is bootstrapped in $REGION"
    else
        print_status "warning" "CDK is not bootstrapped. Run: cdk bootstrap aws://$ACCOUNT_ID/$REGION"
    fi
}

# Post-deployment validation
validate_deployment() {
    echo -e "\n✅ Post-Deployment Validation..."
    
    STACK_NAME=${1:-LibreChatStack-development}
    
    # Check if stack exists
    if aws cloudformation describe-stacks --stack-name $STACK_NAME &> /dev/null; then
        STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].StackStatus" --output text)
        
        if [ "$STATUS" = "CREATE_COMPLETE" ] || [ "$STATUS" = "UPDATE_COMPLETE" ]; then
            print_status "success" "Stack $STACK_NAME is deployed successfully (Status: $STATUS)"
            
            # Get outputs
            echo -e "\n📊 Stack Outputs:"
            aws cloudformation describe-stacks --stack-name $STACK_NAME \
                --query "Stacks[0].Outputs[*].[OutputKey,OutputValue]" \
                --output table
        else
            print_status "error" "Stack $STACK_NAME is in state: $STATUS"
            
            # Show recent events if failed
            if [[ "$STATUS" == *"FAILED"* ]] || [[ "$STATUS" == *"ROLLBACK"* ]]; then
                echo -e "\n📋 Recent Stack Events:"
                aws cloudformation describe-stack-events --stack-name $STACK_NAME \
                    --query "StackEvents[?ResourceStatus=='CREATE_FAILED' || ResourceStatus=='UPDATE_FAILED'][ResourceType,LogicalResourceId,ResourceStatusReason]" \
                    --output table
            fi
        fi
    else
        print_status "info" "Stack $STACK_NAME does not exist"
    fi
}

# Main execution
main() {
    local MODE=${1:-pre-deploy}
    local CONFIG_SOURCE=${2:-minimal-dev}
    local KEY_PAIR=${3:-}
    
    if [ "$MODE" = "pre-deploy" ]; then
        echo "Running pre-deployment checks..."
        check_prerequisites
        check_aws_credentials
        check_configuration_compatibility "$CONFIG_SOURCE"
        check_lambda_layers
        check_typescript_build
        validate_cdk_synthesis "$CONFIG_SOURCE" "$KEY_PAIR"
        check_cdk_bootstrap
        echo -e "\n${GREEN}✅ All pre-deployment checks passed!${NC}"
    elif [ "$MODE" = "post-deploy" ]; then
        echo "Running post-deployment validation..."
        STACK_NAME="LibreChatStack-${CONFIG_SOURCE//-*/}"
        validate_deployment "$STACK_NAME"
    else
        echo "Usage: $0 [pre-deploy|post-deploy] [config-source] [key-pair-name]"
        echo "Example: $0 pre-deploy minimal-dev my-key-pair"
        echo "Example: $0 post-deploy production"
        exit 1
    fi
}

# Run main function
main "$@"