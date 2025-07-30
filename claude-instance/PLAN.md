# AWS Credentials Error Resolution Plan

## Executive Summary

This plan addresses the critical AWS authentication error: **"The security token included in the request is expired"**. The root cause is the missing `AWS_SDK_LOAD_CONFIG=1` environment variable, which prevents the AWS SDK from properly loading SSO configurations and other advanced authentication methods from `~/.aws/config`. This comprehensive plan provides immediate fixes, long-term improvements, and detailed guidance for all AWS authentication scenarios.

## Root Cause Analysis

### Primary Issue
- **Missing Configuration**: `AWS_SDK_LOAD_CONFIG=1` is not set in any execution path
- **Impact**: AWS SDK cannot read SSO profiles from `~/.aws/config`
- **Result**: SSO tokens expire and cannot be refreshed, causing authentication failures

### Secondary Issues
1. Deploy scripts continue execution despite credential warnings
2. No automatic detection or handling of expired SSO tokens
3. Cached CDK context may cause wrong-account deployments
4. No pre-deployment credential validation

## Immediate Solutions

### 1. Fix Package.json Scripts

**File**: `package.json`

Update all deployment scripts to include `AWS_SDK_LOAD_CONFIG=1`:

```json
{
  "scripts": {
    "deploy": "AWS_SDK_LOAD_CONFIG=1 npm run build && cdk deploy",
    "deploy:dev": "AWS_SDK_LOAD_CONFIG=1 npm run build && cdk deploy -c configSource=standard-dev",
    "deploy:staging": "AWS_SDK_LOAD_CONFIG=1 npm run build && cdk deploy -c configSource=staging",
    "deploy:prod": "AWS_SDK_LOAD_CONFIG=1 npm run build && cdk deploy -c configSource=production-ecs",
    "deploy:all": "AWS_SDK_LOAD_CONFIG=1 npm run build && cdk deploy --all",
    "synth": "AWS_SDK_LOAD_CONFIG=1 npm run build && cdk synth",
    "diff": "AWS_SDK_LOAD_CONFIG=1 npm run build && cdk diff",
    "destroy": "AWS_SDK_LOAD_CONFIG=1 cdk destroy",
    "bootstrap": "AWS_SDK_LOAD_CONFIG=1 cdk bootstrap",
    "wizard": "AWS_SDK_LOAD_CONFIG=1 npm run build && bash scripts/deploy-interactive.sh"
  }
}
```

### 2. Fix deploy.sh Script

**File**: `deploy.sh`

Add at line 1 (after shebang):
```bash
#!/bin/bash

# Enable AWS SDK to load config file (required for SSO and advanced auth)
export AWS_SDK_LOAD_CONFIG=1
```

Update credential check (line 217-225) to fail fast:
```bash
# Check AWS credentials
print_status "Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured or expired"
    
    # Check if using SSO
    if [ -n "$AWS_PROFILE" ] && grep -q "sso_start_url" ~/.aws/config 2>/dev/null; then
        print_warning "SSO session appears to be expired"
        echo "Please run: aws sso login --profile $AWS_PROFILE"
    else
        echo "Please configure AWS credentials using one of these methods:"
        echo "  1. AWS SSO: aws configure sso"
        echo "  2. IAM User: aws configure"
        echo "  3. Environment variables: export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=..."
    fi
    exit 1
else
    AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    AWS_PROFILE_NAME=${AWS_PROFILE:-"default"}
    print_success "AWS authenticated successfully"
    print_status "Account: $AWS_ACCOUNT | Region: $AWS_REGION | Profile: $AWS_PROFILE_NAME"
fi
```

### 3. Fix manage-bootstrap.sh Script

**File**: `scripts/manage-bootstrap.sh`

Add after line 10:
```bash
#!/bin/bash

# Enable AWS SDK to load config file (required for SSO and advanced auth)
export AWS_SDK_LOAD_CONFIG=1
```

Update the check_aws_config function (line 58-63):
```bash
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
```

### 4. Create Credential Helper Script

**New File**: `scripts/check-aws-auth.sh`

```bash
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
```

Make the script executable:
```bash
chmod +x scripts/check-aws-auth.sh
```

### 5. Update AWS_AUTHENTICATION.md

**File**: `AWS_AUTHENTICATION.md`

Add a new section after the introduction:

```markdown
## Important Configuration Requirement

⚠️ **Critical**: For AWS SSO and some advanced authentication methods to work properly with CDK, you must set:

```bash
export AWS_SDK_LOAD_CONFIG=1
```

This environment variable enables the AWS SDK to read configuration from `~/.aws/config`, which is required for:
- AWS SSO profiles
- Named profiles with assume role configurations
- Custom credential process configurations

**We recommend adding this to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.):**

```bash
echo 'export AWS_SDK_LOAD_CONFIG=1' >> ~/.bashrc
source ~/.bashrc
```
```

### 6. Add Pre-deployment Validation

**File**: `bin/librechat.ts`

Add credential validation before stack creation (after line 130):

```typescript
// Validate AWS credentials before proceeding
async function validateCredentials() {
  try {
    const sts = new AWS.STS();
    const identity = await sts.getCallerIdentity().promise();
    console.log(`✅ Authenticated as: ${identity.Arn}`);
    console.log(`   Account: ${identity.Account}`);
    
    // Warn if account doesn't match expected
    if (process.env.AWS_ACCOUNT_ID && identity.Account !== process.env.AWS_ACCOUNT_ID) {
      console.warn(`⚠️  Warning: Current account (${identity.Account}) doesn't match AWS_ACCOUNT_ID (${process.env.AWS_ACCOUNT_ID})`);
    }
    
    return identity.Account;
  } catch (error) {
    console.error('❌ AWS Authentication Error:', error.message);
    
    if (error.code === 'ExpiredToken' || error.code === 'ExpiredTokenException') {
      console.error('\n🔄 Your AWS session has expired.');
      
      if (process.env.AWS_PROFILE) {
        console.error(`   Run: aws sso login --profile ${process.env.AWS_PROFILE}`);
      } else {
        console.error('   If using SSO, run: aws sso login --profile <your-profile>');
        console.error('   If using IAM credentials, run: aws configure');
      }
    } else if (error.code === 'CredentialsNotFound' || error.code === 'NoCredentialsError') {
      console.error('\n❓ No AWS credentials found.');
      console.error('   See AWS_AUTHENTICATION.md for setup instructions.');
    }
    
    console.error('\n💡 Tip: Make sure AWS_SDK_LOAD_CONFIG=1 is set for SSO profiles to work.');
    process.exit(1);
  }
}

// Call validation before creating stack
validateCredentials().then(accountId => {
  const stack = new LibreChatStack(app, `LibreChatStack-${config.environment}`, {
    ...config,
    env: {
      account: process.env.CDK_DEFAULT_ACCOUNT || accountId || 'unknown',
      region: process.env.CDK_DEFAULT_REGION || process.env.AWS_DEFAULT_REGION || 'us-east-1',
    },
  });
});
```

## Resolution Steps by Authentication Method

### For AWS SSO Users

1. **Immediate Fix**:
   ```bash
   # Set the required environment variable
   export AWS_SDK_LOAD_CONFIG=1
   
   # Add to your shell profile for persistence
   echo 'export AWS_SDK_LOAD_CONFIG=1' >> ~/.bashrc
   
   # Login to SSO
   aws sso login --profile your-sso-profile
   
   # Set the profile
   export AWS_PROFILE=your-sso-profile
   
   # Verify authentication
   ./scripts/check-aws-auth.sh
   
   # Deploy
   npm run deploy
   ```

2. **If SSO session expired during deployment**:
   ```bash
   # The new scripts will detect this and prompt you
   aws sso login --profile your-sso-profile
   
   # Resume deployment
   npm run deploy
   ```

### For IAM User Credentials

1. **Using aws configure**:
   ```bash
   aws configure
   # Enter your Access Key ID
   # Enter your Secret Access Key
   # Enter your default region
   # Enter output format (json recommended)
   
   # Verify
   ./scripts/check-aws-auth.sh
   ```

2. **Using environment variables**:
   ```bash
   export AWS_ACCESS_KEY_ID=your-access-key
   export AWS_SECRET_ACCESS_KEY=your-secret-key
   export AWS_DEFAULT_REGION=us-east-1
   
   # Verify
   ./scripts/check-aws-auth.sh
   ```

### For Named Profiles

```bash
# Set the required environment variable
export AWS_SDK_LOAD_CONFIG=1

# Use your profile
export AWS_PROFILE=your-profile-name

# Verify
./scripts/check-aws-auth.sh

# Deploy
npm run deploy
```

### For Instance Roles (EC2/CloudShell)

Instance roles should work without changes, but verify:

```bash
# Check instance metadata
curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/

# Verify authentication
./scripts/check-aws-auth.sh
```

## Testing and Validation

### 1. Test Authentication Script

```bash
# Run the new credential checker
./scripts/check-aws-auth.sh

# Expected output:
# ✅ AWS credentials are valid
# 📍 Current AWS Identity: [your details]
```

### 2. Test CDK Commands

```bash
# Test synthesis (doesn't deploy)
npm run synth

# Test diff (shows what would change)
npm run diff

# If both work, proceed with deployment
npm run deploy
```

### 3. Validate Environment Variable

```bash
# Check if AWS_SDK_LOAD_CONFIG is set
echo $AWS_SDK_LOAD_CONFIG
# Should output: 1

# If not set:
export AWS_SDK_LOAD_CONFIG=1
```

### 4. Clear CDK Context if Switching Accounts

```bash
# Check current context
cat cdk.context.json | grep account

# Clear if switching accounts
cdk context --clear

# Or remove the file
rm cdk.context.json
```

## Long-term Improvements

### 1. Enhanced Credential Management Script

Create `scripts/aws-auth-manager.sh`:

```bash
#!/bin/bash

# Comprehensive AWS authentication manager
# Handles SSO, IAM, and profile management

source scripts/check-aws-auth.sh

case "$1" in
  "login")
    # Smart login based on current configuration
    if [ -n "$AWS_PROFILE" ]; then
      aws sso login --profile "$AWS_PROFILE"
    else
      echo "No AWS_PROFILE set. Use: aws-auth-manager switch <profile>"
    fi
    ;;
    
  "switch")
    # Switch between profiles
    export AWS_PROFILE=$2
    echo "Switched to profile: $AWS_PROFILE"
    check_sso_auth "$AWS_PROFILE"
    ;;
    
  "status")
    # Show current status
    ./scripts/check-aws-auth.sh
    ;;
    
  "refresh")
    # Refresh credentials
    if [ -n "$AWS_PROFILE" ]; then
      aws sso login --profile "$AWS_PROFILE"
    fi
    ;;
    
  *)
    echo "Usage: aws-auth-manager {login|switch|status|refresh}"
    ;;
esac
```

### 2. Add to .env.example

Create `.env.example` with AWS configuration hints:

```bash
# AWS Configuration (optional - can use AWS CLI/SSO instead)
# AWS_PROFILE=your-profile-name
# AWS_DEFAULT_REGION=us-east-1
# AWS_SDK_LOAD_CONFIG=1

# Deployment Configuration
DEPLOYMENT_MODE=EC2
DEPLOYMENT_ENV=development
# ... rest of configuration
```

### 3. Automated Token Refresh

Add to `deploy.sh` for long-running deployments:

```bash
# Function to refresh credentials if needed
refresh_credentials_if_needed() {
    if ! aws sts get-caller-identity &>/dev/null; then
        echo "🔄 Credentials expired during deployment. Refreshing..."
        
        if [ -n "$AWS_PROFILE" ] && aws sso login --profile "$AWS_PROFILE"; then
            echo "✅ Credentials refreshed successfully"
            return 0
        else
            echo "❌ Failed to refresh credentials"
            return 1
        fi
    fi
    return 0
}

# Call before each major CDK operation
refresh_credentials_if_needed || exit 1
```

### 4. GitHub Actions / CI/CD Configuration

For CI/CD environments, add to workflow:

```yaml
env:
  AWS_SDK_LOAD_CONFIG: 1
  
steps:
  - name: Configure AWS credentials
    uses: aws-actions/configure-aws-credentials@v2
    with:
      role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
      aws-region: us-east-1
      
  - name: Deploy CDK
    run: |
      export AWS_SDK_LOAD_CONFIG=1
      npm run deploy
```

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. "The security token included in the request is expired"

**Cause**: SSO token expired and AWS_SDK_LOAD_CONFIG not set
**Solution**:
```bash
export AWS_SDK_LOAD_CONFIG=1
aws sso login --profile your-profile
```

#### 2. "Missing credentials in config"

**Cause**: No credentials configured or wrong profile
**Solution**:
```bash
# Check current profile
echo $AWS_PROFILE

# List available profiles
aws configure list-profiles

# Set correct profile
export AWS_PROFILE=correct-profile
```

#### 3. "Could not load credentials from any providers"

**Cause**: AWS SDK can't find credentials in the chain
**Solution**:
```bash
# Run the auth checker
./scripts/check-aws-auth.sh

# Follow its recommendations
```

#### 4. "AccessDenied" with valid credentials

**Cause**: Account mismatch or insufficient permissions
**Solution**:
```bash
# Clear CDK context
cdk context --clear

# Verify account
aws sts get-caller-identity

# Check required permissions in SECURITY.md
```

#### 5. SSO Profile Not Working

**Cause**: AWS_SDK_LOAD_CONFIG not set
**Solution**:
```bash
# Temporary fix
export AWS_SDK_LOAD_CONFIG=1

# Permanent fix
echo 'export AWS_SDK_LOAD_CONFIG=1' >> ~/.bashrc
source ~/.bashrc
```

### Debug Mode

Enable verbose output for troubleshooting:

```bash
# Enable CDK debug output
export CDK_DEBUG=true

# Enable AWS SDK debug output
export AWS_SDK_LOAD_CONFIG=1
export DEBUG=aws-sdk:*

# Run deployment
npm run deploy 2>&1 | tee deploy-debug.log
```

## Security Best Practices

### 1. Never Commit Credentials

- Add to `.gitignore`:
  ```
  .env
  .env.local
  .aws/
  ```

### 2. Use Temporary Credentials

- Prefer AWS SSO over long-lived IAM credentials
- Use role assumption for cross-account access
- Implement credential rotation

### 3. Validate Account Before Deployment

- Always verify you're deploying to the correct account:
  ```bash
  aws sts get-caller-identity
  ```

### 4. Use MFA When Possible

- Configure MFA for IAM users
- SSO enforces MFA at the organization level

### 5. Principle of Least Privilege

- Grant only necessary permissions
- Use separate roles for dev/staging/prod

## Implementation Timeline

### Phase 1: Immediate (Do Now)
1. ✅ Add `export AWS_SDK_LOAD_CONFIG=1` to your shell
2. ✅ Update package.json scripts
3. ✅ Fix deploy.sh and manage-bootstrap.sh
4. ✅ Create check-aws-auth.sh script
5. ✅ Test with your current authentication method

### Phase 2: Short-term (This Week)
1. 📝 Update AWS_AUTHENTICATION.md documentation
2. 📝 Add pre-deployment validation to CDK app
3. 📝 Create comprehensive auth manager script
4. 📝 Test with all authentication methods

### Phase 3: Long-term (This Month)
1. 📋 Implement automated token refresh
2. 📋 Add CI/CD configurations
3. 📋 Create team onboarding guide
4. 📋 Implement monitoring for auth failures

## Success Metrics

After implementing this plan:

1. ✅ No more "expired token" errors for SSO users
2. ✅ Clear error messages guide users to solutions
3. ✅ Deployment scripts fail fast with helpful messages
4. ✅ All authentication methods work consistently
5. ✅ Reduced support requests for auth issues

## Conclusion

The AWS credential expiration issue is primarily caused by the missing `AWS_SDK_LOAD_CONFIG=1` environment variable. This plan provides immediate fixes that can be implemented in minutes, plus long-term improvements for robust credential management. Following this plan will resolve current authentication issues and prevent future occurrences.

Remember: **Always set `export AWS_SDK_LOAD_CONFIG=1` when using AWS SSO or advanced authentication methods.**