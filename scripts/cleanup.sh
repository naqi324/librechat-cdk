#!/bin/bash
# cleanup.sh - Clean up all LibreChat CDK resources

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${RED}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                    ⚠️  WARNING ⚠️                           ║"
echo "║                                                           ║"
echo "║  This will DELETE ALL LibreChat resources including:      ║"
echo "║  - EC2/ECS instances and services                         ║"
echo "║  - RDS databases (with all data)                         ║"
echo "║  - S3 buckets and stored files                           ║"
echo "║  - VPC and networking resources                          ║"
echo "║  - All other AWS resources created by this stack         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Get environment from .env or default
if [ -f .env ]; then
    source .env
fi
ENVIRONMENT=${DEPLOYMENT_ENV:-development}
STACK_NAME=${1:-"LibreChatStack-${ENVIRONMENT}"}

echo -e "${YELLOW}Stack to be deleted: ${STACK_NAME}${NC}"
echo

read -p "Type 'DELETE' to confirm deletion: " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
    echo -e "${GREEN}Cleanup cancelled - no resources were deleted${NC}"
    exit 0
fi

# Change to project root
cd "$(dirname "$0")/.."

echo -e "\n${BLUE}Starting cleanup process...${NC}"

# Check if CDK is installed
if ! command -v cdk &> /dev/null; then
    echo -e "${YELLOW}CDK not found, using AWS CLI directly${NC}"
    
    # Delete stack using AWS CLI
    echo "Deleting CloudFormation stack: $STACK_NAME"
    aws cloudformation delete-stack --stack-name "$STACK_NAME"
    
    echo "Waiting for stack deletion..."
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" 2>/dev/null || true
else
    # Use CDK destroy
    echo -e "${BLUE}Using CDK to destroy stack...${NC}"
    npm run build
    cdk destroy "$STACK_NAME" --force
fi

# Check if stack was deleted
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" &> /dev/null; then
    echo -e "${RED}Stack deletion may have failed. Please check AWS Console.${NC}"
    exit 1
fi

echo -e "\n${GREEN}✅ Cleanup complete!${NC}"
echo
echo "The following have been deleted:"
echo "  - All compute resources (EC2/ECS)"
echo "  - All databases"
echo "  - All storage buckets"
echo "  - All networking resources"
echo
echo -e "${YELLOW}Note: Some resources like CloudWatch logs may be retained based on your configuration.${NC}"

# Offer to clean local files
echo
read -p "Also clean local build files? (y/n) [n]: " CLEAN_LOCAL
if [ "$CLEAN_LOCAL" = "y" ]; then
    echo "Cleaning local files..."
    npm run clean
    rm -f .env deployment-info.json
    echo -e "${GREEN}Local files cleaned${NC}"
fi
