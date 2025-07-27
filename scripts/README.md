# Scripts Directory

## Primary Setup Script

**Use `./setup.sh` in the root directory** - This is the main setup and deployment script that handles everything:
- Environment validation
- Dependency installation
- Interactive configuration
- CDK bootstrap (via manage-bootstrap.sh)
- Stack deployment

## Specialized Scripts

These scripts remain for specific use cases:

### `manage-bootstrap.sh`
Unified CDK bootstrap management with multiple commands:
```bash
# Check bootstrap status
./scripts/manage-bootstrap.sh status

# Fix bootstrap issues
./scripts/manage-bootstrap.sh fix

# Clean and re-bootstrap
./scripts/manage-bootstrap.sh clean

# Show help
./scripts/manage-bootstrap.sh help
```

This script handles all bootstrap-related operations:
- Checking current bootstrap status
- Fixing common bootstrap issues
- Cleaning up conflicting resources
- Re-bootstrapping from scratch

### `estimate-cost.ts`
Estimates AWS costs for different deployment configurations.
```bash
npx ts-node scripts/estimate-cost.ts

# Or compile and run
npm run build
node scripts/estimate-cost.js
```

### `cleanup.sh`
Removes all deployed resources and performs thorough cleanup of the AWS account.
```bash
./scripts/cleanup.sh
```
**Warning:** This will delete all resources created by the stack!

Comprehensive cleanup includes:

**COMPUTE:**
- EC2 instances
- ECS clusters, services, tasks, and task definitions
- Lambda functions

**STORAGE:**
- S3 buckets (with all objects and versions)
- EFS file systems and mount targets
- ECR repositories

**NETWORK:**
- VPCs and subnets
- NAT Gateways (saves ~$45/month each!)
- Internet Gateways
- Elastic IPs
- Route tables
- VPC Endpoints
- Security groups

**DATABASE:**
- RDS instances and clusters
- DocumentDB clusters

**MONITORING & IAM:**
- CloudWatch Log Groups
- IAM roles and policies
- Local build files (optional)

### `deploy.sh`
Advanced deployment script for CI/CD pipelines. Use this when you need:
- Non-interactive deployments
- Custom environment variables
- Integration with CI/CD systems

### `create-one-click-deploy.sh`
Generates a CloudFormation template for one-click deployment via AWS Console.
```bash
./scripts/create-one-click-deploy.sh
```

### `bootstrap-with-custom-qualifier.sh`
Bootstrap CDK with a unique qualifier to avoid global S3 naming conflicts.
```bash
./scripts/bootstrap-with-custom-qualifier.sh
```
Use this when you get "bucket already exists" errors during bootstrap.

### `force-s3-cleanup.sh`
Aggressive S3 bucket cleanup for stubborn CDK bootstrap issues.
```bash
./scripts/force-s3-cleanup.sh
```
Searches multiple regions and uses various methods to find and delete CDK S3 buckets.

### `acknowledge-cdk-notices.sh`
Acknowledge CDK CLI notices to suppress them in future runs.
```bash
./scripts/acknowledge-cdk-notices.sh
```
Acknowledges notices 34892 (telemetry) and 32775 (version divergence).

### `check-resources.sh`
Comprehensive check for all LibreChat CDK resources in your AWS account.
```bash
./scripts/check-resources.sh
```
Checks for:
- CloudFormation stacks (including nested stacks)
- ECS clusters, services, and task definitions
- EC2 instances
- RDS databases and clusters
- S3 buckets
- ECR repositories
- IAM roles
- Security groups
- CloudWatch log groups

### `force-stack-cleanup.sh`
Force cleanup of stubborn CloudFormation stacks that fail to delete.
```bash
./scripts/force-stack-cleanup.sh <stack-name>
```
This script:
- Identifies resources blocking stack deletion
- Manually deletes problematic resources (S3 buckets, ECR repos, etc.)
- Retries stack deletion
- Useful for DELETE_FAILED stacks

### `cleanup-failed.sh`
Quick cleanup for all failed CDK deployments.
```bash
./scripts/cleanup-failed.sh
```
Automatically finds and deletes all stacks in failed states:
- CREATE_FAILED
- ROLLBACK_COMPLETE
- UPDATE_ROLLBACK_COMPLETE
- DELETE_FAILED
- UPDATE_ROLLBACK_FAILED

### `deep-clean-cdk.sh`
Nuclear option - deletes ALL CDK stacks and resources.
```bash
./scripts/deep-clean-cdk.sh
```
**WARNING:** This will delete:
- All CloudFormation stacks (any status)
- CDK bootstrap stacks
- All associated AWS resources
- Orphaned CDK resources (S3 buckets, ECR repos)

## Script Organization

We've consolidated multiple bootstrap-related scripts into a single `manage-bootstrap.sh` script to reduce complexity. The previous individual scripts (check-bootstrap-status.sh, fix-bootstrap.sh, deep-clean-bootstrap.sh, force-clean-bootstrap.sh) have been removed in favor of this unified approach.

## Typical Workflow

1. **Initial Setup**: Run `./setup.sh` from the root directory
2. **Bootstrap Issues**: Use `./scripts/manage-bootstrap.sh` commands
3. **Cost Estimation**: Run `./scripts/estimate-cost.ts` before deployment
4. **Cleanup**: Use `./scripts/cleanup.sh` to remove all resources

## CI/CD Usage

For automated deployments, use the `deploy.sh` script with environment variables:
```bash
export DEPLOYMENT_MODE=ECS
export DEPLOYMENT_ENV=production
./scripts/deploy.sh
```