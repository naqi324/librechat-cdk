# AWS Credentials Investigation Report - LibreChat CDK

## Executive Summary

This investigation was conducted to analyze AWS authentication issues in the librechat-cdk project, specifically addressing errors related to expired security tokens and missing credentials. The investigation revealed a comprehensive AWS authentication system with multiple authentication methods supported, but potential issues with credential chain configuration and AWS SDK settings.

## Error Context

The reported errors indicate:
- "The security token included in the request is expired"
- "Missing credentials in config"
- Suggestion to set `AWS_SDK_LOAD_CONFIG=1`

## Key Findings

### 1. AWS Authentication Methods Supported

The project supports multiple AWS authentication methods as documented in `AWS_AUTHENTICATION.md`:

1. **AWS CLI Configuration** (via `aws configure`)
2. **Environment Variables**:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_DEFAULT_REGION`
3. **AWS SSO** (for organizations)
4. **Named Profiles** (via `AWS_PROFILE`)
5. **IAM Roles** (for EC2/CloudShell)

### 2. CDK Application Configuration

The main CDK application (`bin/librechat.ts`) uses the following environment variables for AWS configuration:

```typescript
env: {
  account: process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID || 'unknown',
  region: process.env.CDK_DEFAULT_REGION || process.env.AWS_DEFAULT_REGION || 'us-east-1',
}
```

### 3. Credential Chain Usage

The project relies on the AWS SDK's default credential provider chain. Key scripts that check credentials:

1. **deploy.sh** (line 217-225):
   - Uses `aws sts get-caller-identity` to verify credentials
   - Falls back to default region `us-east-1` if not configured

2. **manage-bootstrap.sh** (line 14-15):
   - Uses `aws sts get-caller-identity` to get account ID
   - Uses `aws configure get region` to get region

### 4. AWS SDK Version and Configuration

From `package.json`, the project uses:
- AWS CDK v2.150.0
- AWS SDK v3 clients (`@aws-sdk/client-ec2`, `@aws-sdk/client-pricing`)

### 5. Missing AWS_SDK_LOAD_CONFIG

**Critical Finding**: The project does not explicitly set `AWS_SDK_LOAD_CONFIG=1` anywhere in the codebase. This environment variable is important for:
- Loading AWS configuration from `~/.aws/config`
- Supporting AWS SSO profiles
- Enabling advanced credential provider features

### 6. Cached Account Information

The `cdk.context.json` file contains cached AWS account information:
```json
"availability-zones:account=494328630097:region=us-east-1": [...]
```

This suggests the project was previously deployed with account ID `494328630097`.

### 7. Environment Files

The project uses `.env` files for configuration but these primarily contain deployment settings, not AWS credentials:
- `.env` contains deployment configuration (mode, features, etc.)
- No AWS credentials are stored in environment files (good security practice)

## Root Cause Analysis

The AWS credentials error likely stems from one of these issues:

1. **Expired SSO Session**: If using AWS SSO, the session tokens expire and need renewal via `aws sso login`

2. **Missing AWS_SDK_LOAD_CONFIG**: Without this environment variable, the AWS SDK may not properly load configuration from `~/.aws/config`, especially for SSO profiles

3. **Credential Provider Chain Issues**: The default credential provider chain might not be finding valid credentials in the expected locations

4. **Region Configuration**: Mismatch between configured region and actual resources

## Recommendations

### Immediate Actions

1. **Set AWS_SDK_LOAD_CONFIG**:
   ```bash
   export AWS_SDK_LOAD_CONFIG=1
   ```

2. **Verify Current Credentials**:
   ```bash
   aws sts get-caller-identity
   ```

3. **For AWS SSO Users**:
   ```bash
   aws sso login --profile your-profile-name
   export AWS_PROFILE=your-profile-name
   ```

4. **For IAM Users**:
   ```bash
   aws configure
   # Enter your access key, secret key, and region
   ```

### Code Improvements

1. **Add AWS_SDK_LOAD_CONFIG to deployment scripts**:
   Update `deploy.sh` to include:
   ```bash
   export AWS_SDK_LOAD_CONFIG=1
   ```

2. **Enhance credential checking**:
   Add more detailed error messages in deployment scripts when credentials fail

3. **Document AWS_SDK_LOAD_CONFIG requirement**:
   Update `AWS_AUTHENTICATION.md` to mention this requirement for SSO profiles

4. **Consider adding credential helper script**:
   Create a script to diagnose and fix common credential issues

### Long-term Recommendations

1. **Implement credential validation**:
   Add a pre-flight check in CDK app to validate credentials before deployment

2. **Support credential refresh**:
   For SSO users, add automatic detection of expired tokens with user-friendly messages

3. **Enhanced error handling**:
   Improve error messages to guide users to the specific authentication method they should use

## Security Considerations

The project follows good security practices:
- No hardcoded credentials
- Uses AWS IAM roles and policies appropriately
- Supports temporary credentials (SSO, assume role)
- Credentials are not logged or stored in version control

## Conclusion

The AWS authentication system in librechat-cdk is well-designed and supports multiple authentication methods. The reported error is likely due to expired credentials or missing `AWS_SDK_LOAD_CONFIG` environment variable. Following the recommendations above should resolve the authentication issues.

The project would benefit from:
1. Explicit handling of `AWS_SDK_LOAD_CONFIG`
2. Better error messages for credential failures
3. Documentation updates for SSO configuration requirements