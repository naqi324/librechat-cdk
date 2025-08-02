# AWS Authentication Guide for LibreChat CDK

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

## Error: "AWS CLI is not configured"

This error occurs when the AWS CLI cannot find valid credentials. Here are several ways to configure AWS access:

## Option 1: AWS CLI Configuration (Simplest)

```bash
aws configure
```

You'll be prompted for:
- **AWS Access Key ID**: Your IAM user access key
- **AWS Secret Access Key**: Your IAM user secret key
- **Default region name**: e.g., `us-east-1`
- **Default output format**: `json` (recommended)

## Option 2: Environment Variables

```bash
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
export AWS_DEFAULT_REGION="us-east-1"

# Then run deployment
./deploy.sh
```

## Option 3: AWS SSO (For Organizations)

```bash
# Configure SSO
aws configure sso

# Login
aws sso login

# Use with profile
export AWS_PROFILE=your-sso-profile
./deploy.sh
```

## Option 4: Named Profiles

```bash
# Configure a named profile
aws configure --profile librechat

# Use the profile
export AWS_PROFILE=librechat
./deploy.sh
```

## Option 5: IAM Role (EC2/CloudShell)

If running from EC2 or CloudShell, use instance/service roles:
```bash
# No configuration needed - uses instance metadata
./deploy.sh
```

## Getting AWS Credentials

### For Personal AWS Account:
1. Sign in to AWS Console
2. Go to IAM → Users → Your User
3. Security credentials tab → Create access key
4. Choose "Command Line Interface (CLI)"
5. Save the credentials securely

### Required IAM Permissions:

Your IAM user/role needs these permissions:
- CloudFormation: Full access
- EC2: Create/manage instances, security groups, VPCs
- RDS: Create/manage databases
- S3: Create/manage buckets
- IAM: Create roles and policies
- Lambda: Create functions
- Secrets Manager: Create/read secrets
- CloudWatch: Create logs and alarms

### Minimal IAM Policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:*",
        "ec2:*",
        "rds:*",
        "s3:*",
        "iam:*",
        "lambda:*",
        "secretsmanager:*",
        "logs:*",
        "ecs:*",
        "elasticloadbalancing:*",
        "route53:*",
        "cloudwatch:*",
        "sns:*",
        "docdb:*",
        "efs:*"
      ],
      "Resource": "*"
    }
  ]
}
```

## Verifying Configuration

```bash
# Test AWS CLI access
aws sts get-caller-identity

# Should return:
# {
#     "UserId": "AIDAI...",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/your-username"
# }
```

## Security Best Practices

1. **Never commit credentials** to version control
2. **Use temporary credentials** when possible (SSO, assume role)
3. **Rotate access keys** regularly
4. **Use least privilege** - only grant necessary permissions
5. **Enable MFA** on your AWS account

## Troubleshooting

### "The security token included in the request is expired":
- **Cause**: SSO token expired and AWS_SDK_LOAD_CONFIG not set
- **Solution**:
  ```bash
  export AWS_SDK_LOAD_CONFIG=1
  aws sso login --profile your-profile
  ```

### "Invalid credentials" error:
- Check access key and secret key are correct
- Ensure the key is active in IAM console
- Verify the key has necessary permissions

### "Access denied" error:
- Your IAM user/role lacks required permissions
- Check the IAM policy attached to your user/role
- Clear CDK context if switching accounts: `cdk context --clear`

### "Region not specified" error:
- Set AWS_DEFAULT_REGION environment variable
- Or specify region in aws configure

### SSO Profile Not Working:
- **Cause**: AWS_SDK_LOAD_CONFIG not set
- **Solution**:
  ```bash
  # Temporary fix
  export AWS_SDK_LOAD_CONFIG=1
  
  # Permanent fix
  echo 'export AWS_SDK_LOAD_CONFIG=1' >> ~/.bashrc
  source ~/.bashrc
  ```

## Quick Authentication Check

Run our authentication check script:
```bash
./scripts/check-aws-auth.sh
```

This script will:
- Detect your authentication method
- Check if credentials are valid
- Automatically prompt for SSO login if needed
- Provide specific guidance for any issues

## For GitHub Actions / CI/CD

Use GitHub secrets:
```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: us-east-1
```
