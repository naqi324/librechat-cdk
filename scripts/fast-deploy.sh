#!/bin/bash
# fast-deploy.sh - Optimized deployment for faster stack creation

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Fast Deployment Mode${NC}"
echo "========================"
echo
echo -e "${YELLOW}This deployment mode optimizes for speed by:${NC}"
echo "  • Using smaller instance sizes initially"
echo "  • Deploying stacks in parallel where possible"
echo "  • Skipping optional features"
echo "  • Using CDK hotswap for code changes"
echo

# Load environment
if [ -f .env ]; then
    source .env
fi

# Check if this is an update or new deployment
STACK_EXISTS=$(aws cloudformation describe-stacks --stack-name "LibreChatStack-${DEPLOYMENT_ENV:-development}" 2>/dev/null || echo "")

if [ ! -z "$STACK_EXISTS" ]; then
    echo -e "${BLUE}🔄 Detected existing stack - using hotswap deployment${NC}"
    echo "This will update Lambda functions and ECS tasks without full CloudFormation update"
    echo
    
    # Use CDK hotswap for faster updates
    npx cdk deploy --hotswap --all
else
    echo -e "${BLUE}🆕 New deployment - using optimized settings${NC}"
    echo
    
    # Build
    npm run build
    
    # Deploy with fast settings
    FAST_DEPLOY=true npx cdk deploy \
        --all \
        --concurrency 10 \
        --require-approval never \
        -c fastDeploy=true
fi

echo -e "\n${GREEN}✅ Fast deployment complete!${NC}"
echo
echo -e "${YELLOW}Note: Remember to scale up resources for production use${NC}"