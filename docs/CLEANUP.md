# LibreChat CDK Cleanup Guide

This guide explains how to use the consolidated cleanup script for LibreChat CDK deployments.

## Quick Start

The consolidated `cleanup.sh` script handles all cleanup scenarios:

```bash
./scripts/cleanup.sh
```

## Consolidated Cleanup Script

### Overview
**Version**: 2.0.0  
**Purpose**: Single comprehensive cleanup tool that replaces all previous cleanup scripts  
**Compatibility**: Works in both AWS CloudShell and local environments (no jq/npm dependencies)

### Usage
```bash
./scripts/cleanup.sh [OPTIONS]
```

### Options
- `-m, --mode <mode>` - Cleanup mode: standard|deep|nuclear|rollback-fix (default: standard)
- `-s, --stack-name <name>` - CloudFormation stack name (default: LibreChatStack-development)
- `-e, --environment <env>` - Environment: development|staging|production (default: development)
- `-r, --regions <regions>` - Comma-separated list of regions to clean (default: current region)
- `-a, --all-regions` - Clean resources in all regions
- `-b, --bootstrap` - Also clean CDK bootstrap stacks
- `-f, --force` - Skip confirmation prompts
- `-d, --dry-run` - Show what would be deleted without deleting
- `-v, --verbose` - Enable verbose output
- `-h, --help` - Display help message

### Cleanup Modes

#### 1. **Standard Mode** (default)
Normal cleanup of stack resources:
```bash
./scripts/cleanup.sh
./scripts/cleanup.sh -s MyStack-production
```

#### 2. **Deep Mode**
Thorough cleanup including orphaned resources:
```bash
./scripts/cleanup.sh -m deep
```

#### 3. **Nuclear Mode**
Delete ALL LibreChat resources across the account (use with extreme caution!):
```bash
./scripts/cleanup.sh -m nuclear -f
```

#### 4. **Rollback-Fix Mode**
Fix stacks stuck in UPDATE_ROLLBACK_FAILED state:
```bash
./scripts/cleanup.sh -m rollback-fix -s FailedStack
```

### Examples

```bash
# Standard cleanup with default settings
./scripts/cleanup.sh

# Deep cleanup of specific stack
./scripts/cleanup.sh -m deep -s MyStack

# Nuclear cleanup in all regions (dangerous!)
./scripts/cleanup.sh -m nuclear -a -f

# Fix rollback-failed stack
./scripts/cleanup.sh -m rollback-fix -s FailedStack

# Dry run to see what would be deleted
./scripts/cleanup.sh -d -v

# Clean specific regions
./scripts/cleanup.sh -r us-east-1,us-west-2

# Clean up including CDK bootstrap
./scripts/cleanup.sh -b
```

## Common Scenarios

### Scenario 1: Normal Stack Deletion
```bash
./scripts/cleanup.sh
```

### Scenario 2: Stack Stuck in UPDATE_ROLLBACK_FAILED
```bash
./scripts/cleanup.sh -m rollback-fix -s LibreChatStack-development
```

### Scenario 3: Multiple Failed Deployments
```bash
# Check what resources exist
./scripts/check-resources.sh

# Clean up everything
./scripts/cleanup.sh -m nuclear -f
```

### Scenario 4: Partial Deployment Failure
If the stack fails during creation:
1. Wait for CloudFormation to attempt rollback
2. If rollback fails, use: `./scripts/cleanup.sh -m rollback-fix`
3. If resources remain, use: `./scripts/cleanup.sh -m deep`

## Resource-Specific Issues

### S3 Buckets
**Problem**: Bucket not empty
**Solution**: The cleanup scripts automatically empty buckets before deletion

### Security Groups
**Problem**: Dependency violations
**Solution**: Scripts remove all rules before deleting security groups

### Network Interfaces
**Problem**: ENIs attached to Lambda functions
**Solution**: Wait 15-45 minutes for AWS to clean up, or manually detach

### Load Balancers
**Problem**: Deletion protection enabled
**Solution**: Scripts handle this automatically for non-production environments

### RDS/DocumentDB
**Problem**: Deletion protection or final snapshot required
**Solution**: Scripts skip final snapshots and handle deletion protection

## Troubleshooting Cleanup Failures

### 1. Check Stack Status
```bash
aws cloudformation describe-stacks --stack-name LibreChatStack-development
```

### 2. List Failed Resources
```bash
aws cloudformation list-stack-resources --stack-name LibreChatStack-development \
  --query 'StackResourceSummaries[?ResourceStatus==`DELETE_FAILED`]'
```

### 3. Manual Resource Deletion
If automated cleanup fails, manually delete resources in this order:

1. ECS Services (scale to 0 first)
2. Load Balancers
3. Target Groups
4. EC2 Instances
5. RDS/DocumentDB Clusters
6. EFS File Systems
7. Lambda Functions
8. S3 Buckets (empty first)
9. CloudWatch Log Groups
10. IAM Roles
11. Security Groups
12. Network Interfaces
13. VPC Resources

### 4. Region Considerations
Ensure you're in the correct AWS region:
```bash
aws configure get region
export AWS_DEFAULT_REGION=us-east-1  # Change as needed
```

## Best Practices

1. **Always check for remaining resources** after cleanup:
   ```bash
   ./scripts/check-resources.sh
   ```

2. **Use the appropriate script** for your environment:
   - CloudShell: Use `cleanup-cloudshell.sh`
   - Local development: Use `cleanup.sh`
   - Stuck rollbacks: Use `fix-rollback-failed.sh`

3. **Monitor costs** by checking for:
   - NAT Gateways (~$45/month each)
   - Elastic IPs (cost when not attached)
   - Running EC2/RDS instances

4. **Document your stack names** to ensure you're deleting the correct resources

## Prevention Tips

To avoid cleanup issues:

1. **Use consistent naming**: Always use the same stack name for each environment
2. **Deploy in stages**: Test in development before production
3. **Monitor deployments**: Watch CloudFormation events during deployment
4. **Set resource limits**: Use smaller instance types for development
5. **Enable auto-cleanup**: Set `autoDeleteObjects: true` for development S3 buckets

## Recent Improvements

The following improvements have been made to prevent cleanup issues:

1. **Lambda Delete Handlers**: All Lambda-backed custom resources now properly handle Delete events
2. **VPC Endpoints**: Added Secrets Manager endpoint to prevent Lambda timeouts
3. **Security Groups**: Fixed circular dependencies and proper deletion order
4. **Deletion Policies**: Conditional deletion protection based on environment
5. **CloudShell Support**: New scripts work without jq or npm dependencies

## Migration from Old Scripts

All previous cleanup scripts have been deprecated and replaced by the consolidated `cleanup.sh`:

| Old Script | New Command |
|------------|-------------|
| `cleanup-cloudshell.sh` | `./cleanup.sh` |
| `cleanup-deep.sh` | `./cleanup.sh -m deep` |
| `cleanup-nuclear.sh` | `./cleanup.sh -m nuclear` |
| `cleanup-failed-stacks.sh` | `./cleanup.sh` |
| `cleanup-s3-buckets.sh` | `./cleanup.sh -a` |
| `fix-rollback-failed.sh` | `./cleanup.sh -m rollback-fix` |

## Features of the Consolidated Script

### 1. **Resource Coverage**
The script handles ALL resource types:
- ✅ VPCs and all networking components (subnets, route tables, NAT gateways, etc.)
- ✅ S3 buckets (including versioned objects and delete markers)
- ✅ Secrets Manager secrets (force delete without recovery)
- ✅ IAM roles, policies, and instance profiles
- ✅ CloudWatch Log Groups
- ✅ Lambda functions and layers
- ✅ ECS clusters, services, and task definitions
- ✅ RDS and DocumentDB clusters
- ✅ Application Load Balancers and Target Groups
- ✅ EFS file systems and mount targets
- ✅ ECR repositories
- ✅ VPC endpoints and Elastic IPs

### 2. **Safety Features**
- Confirmation prompts (bypass with `-f`)
- Dry-run mode to preview deletions (`-d`)
- Verbose logging for debugging (`-v`)
- Progress tracking with timestamps
- Graceful error handling

### 3. **CloudShell Compatibility**
- No dependencies on jq, npm, or CDK tools
- Uses only AWS CLI with built-in JSON parsing
- Detects CloudShell environment automatically

### 4. **Multi-Region Support**
- Clean specific regions with `-r`
- Clean all regions with `-a`
- Preserves original region setting

## Getting Help

If cleanup continues to fail:

1. Run with verbose mode: `./cleanup.sh -v`
2. Try dry-run first: `./cleanup.sh -d`
3. Check CloudWatch Logs for specific error messages
4. Review the AWS Console for remaining resources
5. Contact AWS Support if resources are stuck
6. Open an issue on GitHub with:
   - Stack name and region
   - Error messages
   - Output from `check-resources.sh`
   - CloudFormation events