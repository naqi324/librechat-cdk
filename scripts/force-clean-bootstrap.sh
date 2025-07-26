#!/bin/bash
# force-clean-bootstrap.sh - Force clean CDK bootstrap resources (non-interactive)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get AWS account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region || echo "us-east-1")

# Default CDK bootstrap resources
DEFAULT_QUALIFIER="hnb659fds"
ECR_REPO="cdk-${DEFAULT_QUALIFIER}-container-assets-${ACCOUNT_ID}-${REGION}"
S3_BUCKET="cdk-${DEFAULT_QUALIFIER}-assets-${ACCOUNT_ID}-${REGION}"

echo -e "${BLUE}Force cleaning CDK bootstrap resources...${NC}"
echo "Account: $ACCOUNT_ID"
echo "Region: $REGION"
echo

# Force delete ECR repository
echo "Deleting ECR repository: $ECR_REPO"
aws ecr delete-repository --repository-name $ECR_REPO --force --region $REGION 2>/dev/null || echo "ECR repository not found or already deleted"

# Force delete S3 bucket
echo "Deleting S3 bucket: $S3_BUCKET"
# Empty bucket first
aws s3 rm s3://$S3_BUCKET --recursive --region $REGION 2>/dev/null || true
# Delete bucket
aws s3 rb s3://$S3_BUCKET --force --region $REGION 2>/dev/null || echo "S3 bucket not found or already deleted"

# Delete CloudFormation stack
echo "Deleting CloudFormation stack: CDKToolkit"
aws cloudformation delete-stack --stack-name CDKToolkit --region $REGION 2>/dev/null || true

echo
echo -e "${GREEN}✅ Cleanup initiated. Waiting for resources to be deleted...${NC}"

# Wait a bit for resources to be deleted
sleep 5

echo
echo "Now running CDK bootstrap..."
npx cdk bootstrap aws://${ACCOUNT_ID}/${REGION}

echo
echo -e "${GREEN}✅ Bootstrap complete!${NC}"