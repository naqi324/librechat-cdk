# Scripts Directory

## Primary Deployment Script

**Use `./deploy.sh` in the root directory** - This is the main deployment script that handles everything:
- Pre-deployment validation (checks for failed stacks, CDK bootstrap status, key pairs)
- Environment validation
- Dependency installation
- Interactive configuration
- CDK bootstrap (via manage-bootstrap.sh)
- Stack deployment

**Options:**
```bash
./deploy.sh                    # Interactive setup wizard
./deploy.sh --fast             # Fast deployment mode (minimal resources)
./deploy.sh --persistent       # Run in screen/tmux (CloudShell safe)
./deploy.sh --config .env      # Use existing configuration
./deploy.sh --config .env --verbose  # With detailed output
./deploy.sh --help             # Show all options
```

The script now includes built-in validation that:
- Detects failed CloudFormation stacks and suggests cleanup
- Validates CDK bootstrap status
- Verifies EC2 key pairs exist before deployment
- Checks Node.js version and other prerequisites

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

# Bootstrap with custom qualifier (avoids S3 conflicts)
./scripts/manage-bootstrap.sh custom

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
Comprehensive cleanup tool for AWS resources - works in CloudShell without dependencies.
```bash
./scripts/cleanup.sh                    # Standard cleanup
./scripts/cleanup.sh -m deep            # Deep cleanup (all CDK resources)
./scripts/cleanup.sh -m nuclear -f      # Delete everything (dangerous!)
./scripts/cleanup.sh -m rollback-fix    # Fix stuck rollbacks
./scripts/cleanup.sh -d                 # Dry run mode
./scripts/cleanup.sh -r us-west-2       # Specific region
```
**Warning:** This will delete resources based on the mode selected!

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

### `check-resources.sh`
Check AWS resource usage and running costs across all regions.
```bash
./scripts/check-resources.sh
```


## Script Organization

We've consolidated multiple bootstrap-related scripts into a single `manage-bootstrap.sh` script to reduce complexity. The previous individual scripts (check-bootstrap-status.sh, fix-bootstrap.sh, deep-clean-bootstrap.sh, force-clean-bootstrap.sh) have been removed in favor of this unified approach.

## Typical Workflow

1. **Initial Setup**: Run `./deploy.sh` from the root directory
2. **Bootstrap Issues**: Use `./scripts/manage-bootstrap.sh` commands
3. **Cost Estimation**: Run `./scripts/estimate-cost.ts` before deployment
4. **Cleanup**: Use `./scripts/cleanup.sh` to remove all resources

## CI/CD Usage

For automated deployments, use the deployment script with environment variables:
```bash
export DEPLOYMENT_MODE=ECS
export DEPLOYMENT_ENV=production
./deploy.sh --config .env
```