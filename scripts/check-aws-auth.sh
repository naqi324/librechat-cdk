#!/bin/bash

# Enable AWS SDK to load config file
export AWS_SDK_LOAD_CONFIG=1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 Checking AWS Authentication Status..."

# Function to check and refresh SSO
check_sso_auth() {
    local profile=$1
    
    # Check if this is an SSO profile
    if grep -q "sso_start_url" ~/.aws/config 2>/dev/null; then
        echo "📋 SSO Profile detected: $profile"
        
        # Try to get caller identity
        if ! aws sts get-caller-identity --profile "$profile" &>/dev/null; then
            echo -e "${YELLOW}⚠️  SSO session expired or not authenticated${NC}"
            echo "🔄 Initiating SSO login..."
            
            if aws sso login --profile "$profile"; then
                echo -e "${GREEN}✅ SSO authentication successful${NC}"
                return 0
            else
                echo -e "${RED}❌ SSO authentication failed${NC}"
                return 1
            fi
        else
            echo -e "${GREEN}✅ SSO session is active${NC}"
            return 0
        fi
    fi
    return 2
}

# Main authentication check
if [ -n "$AWS_PROFILE" ]; then
    echo "🔧 Using AWS Profile: $AWS_PROFILE"
    check_sso_auth "$AWS_PROFILE"
    sso_status=$?
    
    if [ $sso_status -eq 2 ]; then
        # Not an SSO profile, check standard credentials
        if aws sts get-caller-identity &>/dev/null; then
            echo -e "${GREEN}✅ AWS credentials are valid${NC}"
        else
            echo -e "${RED}❌ AWS credentials are invalid or expired${NC}"
            exit 1
        fi
    elif [ $sso_status -ne 0 ]; then
        exit 1
    fi
else
    # No profile specified, check default credentials
    if aws sts get-caller-identity &>/dev/null; then
        echo -e "${GREEN}✅ Default AWS credentials are valid${NC}"
    else
        echo -e "${RED}❌ No valid AWS credentials found${NC}"
        echo ""
        echo "Configure AWS credentials using one of these methods:"
        echo "  1. AWS SSO (recommended for organizations):"
        echo "     aws configure sso"
        echo ""
        echo "  2. IAM User credentials:"
        echo "     aws configure"
        echo ""
        echo "  3. Environment variables:"
        echo "     export AWS_ACCESS_KEY_ID=your-access-key"
        echo "     export AWS_SECRET_ACCESS_KEY=your-secret-key"
        echo "     export AWS_DEFAULT_REGION=us-east-1"
        echo ""
        echo "  4. Use existing profile:"
        echo "     export AWS_PROFILE=your-profile-name"
        exit 1
    fi
fi

# Display current identity
echo ""
echo "📍 Current AWS Identity:"
aws sts get-caller-identity --output table

# Check for potential issues
echo ""
echo "🔍 Checking for potential issues..."

# Check if AWS_SDK_LOAD_CONFIG is set
if [ "$AWS_SDK_LOAD_CONFIG" != "1" ]; then
    echo -e "${YELLOW}⚠️  AWS_SDK_LOAD_CONFIG is not set. SSO profiles may not work.${NC}"
    echo "   Run: export AWS_SDK_LOAD_CONFIG=1"
fi

# Check for cached context mismatches
if [ -f "cdk.context.json" ]; then
    cached_account=$(grep -o '"account":[[:space:]]*"[0-9]*"' cdk.context.json | grep -o '[0-9]\+' | head -1)
    current_account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    
    if [ -n "$cached_account" ] && [ "$cached_account" != "$current_account" ]; then
        echo -e "${YELLOW}⚠️  CDK context cached for different account ($cached_account)${NC}"
        echo "   Current account: $current_account"
        echo "   Consider running: cdk context --clear"
    fi
fi

echo ""
echo -e "${GREEN}✅ Authentication check complete${NC}"