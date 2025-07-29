# DocumentDB Initialization Fix Plan

## Root Cause Analysis

The DocumentDB initialization is failing because:

1. **Lambda in PRIVATE_ISOLATED subnet cannot access AWS Secrets Manager** - No VPC endpoint exists for Secrets Manager in isolated subnets
2. **DNS resolution may be failing** - DocumentDB endpoints might not resolve without proper VPC DNS configuration
3. **TLS certificate issues** - Using outdated CA certificate path
4. **Network path validation** - No verification that Lambda can actually reach DocumentDB

## Fix Implementation Plan

### Step 1: Add Required VPC Endpoints
- Add Secrets Manager endpoint to PRIVATE_ISOLATED subnets
- Add Lambda VPC endpoints for proper function execution
- Ensure DNS is properly configured

### Step 2: Update Lambda Configuration
- Move Lambda to PRIVATE_WITH_EGRESS subnet temporarily OR
- Add proper VPC endpoints for isolated subnet access
- Update TLS certificate to use 2019 or newer bundle

### Step 3: Improve Connection Logic
- Add DNS resolution testing
- Implement better error logging
- Remove replica set requirement if not needed
- Add network connectivity test before MongoDB connection

### Step 4: Update Security Groups
- Ensure bi-directional communication between Lambda and DocumentDB
- Verify no additional ports are blocked

### Step 5: Add Diagnostic Capabilities
- Log DNS resolution attempts
- Log network connectivity tests
- Log secret retrieval success/failure
- Add CloudWatch metrics

## Implementation Order

1. First, update VPC endpoints (most critical)
2. Update Lambda subnet placement or add endpoints
3. Fix TLS certificate issue
4. Improve error handling and diagnostics
5. Test and validate
