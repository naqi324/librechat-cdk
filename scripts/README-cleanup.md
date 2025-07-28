# LibreChat CDK Cleanup Scripts

This directory contains the consolidated cleanup script for managing LibreChat CDK resources.

## Consolidated Cleanup Script

### `cleanup.sh` - Universal Cleanup Tool (v2.0.0)

A comprehensive cleanup script that replaces all previous individual cleanup scripts. This single tool handles all cleanup scenarios with different modes and options.

**Features:**
- CloudShell compatible (no jq/npm dependencies)
- Multiple cleanup modes (standard, deep, nuclear, rollback-fix)
- Multi-region support
- Dry-run capability
- Verbose logging
- Handles all resource types

**Usage:**
```bash
./scripts/cleanup.sh [OPTIONS]

Options:
  -m, --mode <mode>         Cleanup mode: standard|deep|nuclear|rollback-fix
  -s, --stack-name <name>   CloudFormation stack name
  -e, --environment <env>   Environment: development|staging|production
  -r, --regions <regions>   Comma-separated list of regions
  -a, --all-regions         Clean resources in all regions
  -b, --bootstrap           Also clean CDK bootstrap stacks
  -f, --force               Skip confirmation prompts
  -d, --dry-run             Show what would be deleted
  -v, --verbose             Enable verbose output
  -h, --help                Display help message
```

**Examples:**
```bash
# Standard cleanup
./scripts/cleanup.sh

# Deep cleanup of specific stack
./scripts/cleanup.sh -m deep -s MyStack

# Fix rollback-failed stack
./scripts/cleanup.sh -m rollback-fix -s FailedStack

# Nuclear cleanup (delete everything)
./scripts/cleanup.sh -m nuclear -f

# Dry run with verbose output
./scripts/cleanup.sh -d -v
```

## Deprecated Scripts

The following scripts have been deprecated and replaced by `cleanup.sh`:

| Old Script | Replacement Command |
|------------|---------------------|
| `cleanup-cloudshell.sh` | `./cleanup.sh` |
| `cleanup-deep.sh` | `./cleanup.sh -m deep` |
| `cleanup-nuclear.sh` | `./cleanup.sh -m nuclear` |
| `cleanup-failed-stacks.sh` | `./cleanup.sh` |
| `cleanup-s3-buckets.sh` | `./cleanup.sh -a` |
| `fix-rollback-failed.sh` | `./cleanup.sh -m rollback-fix` |

## Resource Checking

### `check-resources.sh`
Check for remaining LibreChat resources in your AWS account.

```bash
./scripts/check-resources.sh
```

This script helps verify that cleanup was successful and identifies any remaining resources.

## Best Practices

1. **Always run `check-resources.sh` after cleanup** to verify all resources were removed
2. **Use dry-run mode first** (`-d`) to see what will be deleted
3. **Start with standard mode** before trying more aggressive cleanup modes
4. **Be extremely careful with nuclear mode** - it deletes ALL LibreChat resources

## Troubleshooting

If cleanup fails:
1. Run with verbose mode: `./cleanup.sh -v`
2. Check the specific error messages
3. Try rollback-fix mode if stack is stuck: `./cleanup.sh -m rollback-fix`
4. Use deep or nuclear mode for stubborn resources
5. See [CLEANUP.md](../docs/CLEANUP.md) for detailed troubleshooting

## CloudShell Usage

The consolidated cleanup script is fully compatible with AWS CloudShell:

```bash
# In CloudShell
cd librechat-cdk
./scripts/cleanup.sh
```

No additional tools or dependencies required!