# AWS Isengard Token Expiration Workarounds

This guide provides solutions for deploying LibreChat CDK when facing AWS Isengard token expiration issues.

## Problem
AWS Isengard tokens expire after ~2 hours, but the full deployment can take 2+ hours, causing deployment failures.

## Solutions (in order of recommendation)

### 1. AWS CloudShell Deployment (Easiest & Fastest)

AWS CloudShell provides a browser-based shell with AWS credentials that don't expire during your session.

**Steps:**
```bash
# 1. Open AWS CloudShell from AWS Console
#    - Log into AWS Console
#    - Click the CloudShell icon (terminal icon) in the top navigation bar
#    - Wait for CloudShell to initialize

# 2. Clone your repository
git clone https://github.com/your-org/librechat-cdk.git
cd librechat-cdk

# 3. Install dependencies
npm install
npm install -g aws-cdk

# 4. Build the project
npm run build

# 5. Deploy using ultra-minimal configuration for speed
cdk deploy --all --require-approval never -c configSource=ultra-minimal-dev

# OR deploy with standard configuration
cdk deploy --all --require-approval never
```

**Advantages:**
- No token expiration issues
- Pre-configured AWS environment
- No local setup required
- Can run for hours without interruption

### 2. Deploy from EC2 Instance

Launch an EC2 instance with an IAM role to avoid token expiration entirely.

**Quick Setup:**
```bash
# 1. Launch EC2 instance with appropriate IAM role
aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \  # Amazon Linux 2023
  --instance-type t3.medium \
  --iam-instance-profile Name=EC2-CDK-Deploy-Role \
  --key-name your-key-pair \
  --security-group-ids sg-xxxxxx \
  --subnet-id subnet-xxxxxx \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=CDK-Deploy-Instance}]' \
  --user-data file://ec2-deploy-script.sh
```

**ec2-deploy-script.sh:**
```bash
#!/bin/bash
# Update system
yum update -y

# Install Node.js
curl -sL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs git

# Install CDK
npm install -g aws-cdk

# Clone and deploy
git clone https://github.com/your-org/librechat-cdk.git
cd librechat-cdk
npm install
npm run build
cdk deploy --all --require-approval never -c configSource=ultra-minimal-dev

# Shutdown instance after deployment (optional)
# shutdown -h now
```

### 3. Local Deployment with Ultra-Minimal Configuration

Use the optimized configuration to complete deployment within the 2-hour token window.

**Steps:**
```bash
# 1. Ensure you have the latest code with optimizations
git pull

# 2. Use ultra-minimal configuration
export DEPLOYMENT_MODE=EC2
export RESOURCE_SIZE=xs

# 3. Deploy with ultra-minimal preset
cdk deploy -c configSource=ultra-minimal-dev --require-approval never

# Expected deployment time: 60-80 minutes (within token lifetime)
```

### 4. Phased Deployment with Token Refresh

Deploy in phases, refreshing your token between each phase.

**Steps:**
```bash
# Phase 1: Deploy infrastructure (VPC, databases)
cdk deploy LibreChatStack-development --exclusively \
  -c configSource=ultra-minimal-dev \
  --require-approval never

# Check if token is still valid
aws sts get-caller-identity || aws sso login --profile your-profile

# Phase 2: Complete deployment
cdk deploy LibreChatStack-development \
  -c configSource=ultra-minimal-dev \
  --require-approval never
```

### 5. AWS CodeBuild One-Time Deployment

Create a CodeBuild project for deployment without token constraints.

**Setup CodeBuild Project:**
```json
{
  "name": "librechat-deploy",
  "source": {
    "type": "GITHUB",
    "location": "https://github.com/your-org/librechat-cdk.git"
  },
  "artifacts": {
    "type": "NO_ARTIFACTS"
  },
  "environment": {
    "type": "LINUX_CONTAINER",
    "image": "aws/codebuild/standard:7.0",
    "computeType": "BUILD_GENERAL1_MEDIUM"
  },
  "serviceRole": "arn:aws:iam::YOUR_ACCOUNT:role/CodeBuildServiceRole"
}
```

**buildspec.yml:**
```yaml
version: 0.2

phases:
  install:
    runtime-versions:
      nodejs: 18
    commands:
      - npm install -g aws-cdk
      - npm install
  
  build:
    commands:
      - npm run build
      - cdk deploy --all --require-approval never -c configSource=ultra-minimal-dev

  post_build:
    commands:
      - echo "Deployment completed at $(date)"
```

## Deployment Time Optimizations Applied

1. **Ultra-minimal configuration** removes:
   - DocumentDB (saves 25-30 minutes)
   - Multiple AZs (saves 5-10 minutes)
   - Enhanced monitoring (saves 2-5 minutes)
   - Switches to EC2 mode (saves 10-15 minutes vs ECS)

2. **Lambda optimization** reduces:
   - Timeout from 15 to 10 minutes
   - PostgreSQL retries from 90 to 30
   - DocumentDB retries from 60 to 20
   - Retry delay from 10 to 5 seconds

3. **Expected deployment times**:
   - Ultra-minimal: 60-80 minutes
   - Standard: 90-120 minutes
   - Full production: 120-150 minutes

## Monitoring Deployment Progress

```bash
# Watch CloudFormation stack events
watch -n 30 'aws cloudformation describe-stack-events \
  --stack-name LibreChatStack-development \
  --query "StackEvents[0:5].[Timestamp,ResourceStatus,ResourceType]" \
  --output table'

# Check current resource count
aws cloudformation describe-stack-resources \
  --stack-name LibreChatStack-development \
  --query 'length(StackResources[?ResourceStatus==`CREATE_COMPLETE`])' \
  --output text
```

## Troubleshooting

### If deployment fails due to token expiration:

1. **Check stack status:**
   ```bash
   aws cloudformation describe-stacks \
     --stack-name LibreChatStack-development \
     --query 'Stacks[0].StackStatus'
   ```

2. **If CREATE_IN_PROGRESS:**
   - Wait for rollback to complete
   - Use CloudShell or EC2 for retry

3. **Clean up failed deployment:**
   ```bash
   cdk destroy --force
   ```

4. **Retry with alternative method** (CloudShell recommended)

## Best Practices

1. **Always use CloudShell** for deployments over 90 minutes
2. **Monitor token expiration** before starting deployment
3. **Use ultra-minimal configuration** for development/testing
4. **Consider setting up CI/CD pipeline** for regular deployments

## Support

If you continue to experience issues:
1. Use AWS CloudShell (most reliable)
2. Create an EC2 deployment instance
3. Contact your AWS administrator about extended IAM session options