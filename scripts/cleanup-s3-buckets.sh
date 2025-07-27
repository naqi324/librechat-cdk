#!/bin/bash
# force-s3-cleanup.sh - Force cleanup of CDK S3 buckets across all regions

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${RED}Force S3 Bucket Cleanup${NC}"
echo "======================="

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
DEFAULT_QUALIFIER="hnb659fds"
S3_BUCKET="cdk-${DEFAULT_QUALIFIER}-assets-${ACCOUNT_ID}-us-east-1"

echo -e "${YELLOW}Looking for bucket: ${S3_BUCKET}${NC}"
echo

# Method 1: Try to find bucket location
echo "Method 1: Checking bucket location..."
BUCKET_LOCATION=$(aws s3api get-bucket-location --bucket $S3_BUCKET 2>&1 || echo "")

if [[ "$BUCKET_LOCATION" == *"NoSuchBucket"* ]]; then
    echo "Bucket not found via get-bucket-location"
else
    echo "Bucket location response: $BUCKET_LOCATION"
fi

# Method 2: List all buckets and search
echo -e "\nMethod 2: Searching all buckets..."
ALL_BUCKETS=$(aws s3api list-buckets --query 'Buckets[].Name' --output text 2>/dev/null || echo "")

if echo "$ALL_BUCKETS" | grep -q "$S3_BUCKET"; then
    echo -e "${YELLOW}Found bucket in bucket list!${NC}"
    
    # Try to force delete
    echo "Attempting force deletion..."
    
    # Try without region first (uses default)
    aws s3 rm s3://$S3_BUCKET --recursive 2>/dev/null || echo "Failed to empty bucket (default region)"
    aws s3 rb s3://$S3_BUCKET --force 2>/dev/null || echo "Failed to delete bucket (default region)"
    
    # Try with us-east-1 explicitly
    aws s3 rm s3://$S3_BUCKET --recursive --region us-east-1 2>/dev/null || echo "Failed to empty bucket (us-east-1)"
    aws s3 rb s3://$S3_BUCKET --force --region us-east-1 2>/dev/null || echo "Failed to delete bucket (us-east-1)"
else
    echo "Bucket not found in bucket list"
fi

# Method 3: Check common regions
echo -e "\nMethod 3: Checking common regions..."
REGIONS="us-east-1 us-west-2 eu-west-1 eu-central-1 ap-southeast-1 ap-northeast-1"

for region in $REGIONS; do
    echo -n "Checking $region... "
    if aws s3api head-bucket --bucket $S3_BUCKET --region $region 2>/dev/null; then
        echo -e "${GREEN}FOUND!${NC}"
        echo "Deleting from region $region..."
        aws s3 rm s3://$S3_BUCKET --recursive --region $region 2>/dev/null || true
        aws s3 rb s3://$S3_BUCKET --force --region $region 2>/dev/null || true
        break
    else
        echo "not found"
    fi
done

# Method 4: Use AWS CLI v2 with all-regions
echo -e "\nMethod 4: Force delete with error suppression..."
aws s3 rb s3://$S3_BUCKET --force 2>&1 | grep -v "does not exist" || true

# Final check
echo -e "\nFinal verification..."
if aws s3api head-bucket --bucket $S3_BUCKET 2>&1 | grep -q "404"; then
    echo -e "${GREEN}✅ Bucket successfully deleted or doesn't exist${NC}"
else
    echo -e "${YELLOW}⚠️  Bucket may still exist. Waiting 30 seconds for propagation...${NC}"
    sleep 30
fi

echo -e "\n${BLUE}Alternative Solutions:${NC}"
echo "1. The bucket name might be taken by another AWS account (S3 names are globally unique)"
echo "2. Try using a custom CDK qualifier:"
echo "   npx cdk bootstrap --qualifier myunique123"
echo "3. Or wait a few hours - sometimes S3 takes time to release bucket names"
echo
echo "To use a custom qualifier, add to cdk.json:"
echo '  "context": {'
echo '    "@aws-cdk/core:bootstrapQualifier": "myunique123"'
echo '  }'