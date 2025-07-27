# Cleanup Scripts Overview

This directory contains various cleanup scripts for different scenarios:

## Main Cleanup Scripts

### 1. `cleanup.sh` - Standard Cleanup
- **Use when**: Normal stack deletion via `cdk destroy`
- **What it does**: Cleanly removes a specific LibreChat stack
- **Safety**: High - only deletes specified stack

### 2. `cleanup-deep.sh` - Deep Cleanup (renamed from deep-clean-cdk.sh)
- **Use when**: Stack deletion fails or leaves orphaned resources
- **What it does**: 
  - Deletes CloudFormation stacks
  - Removes blocking resources (S3, ECS, RDS, etc.)
  - Cleans up CDK bootstrap stack
- **Safety**: Medium - deletes all LibreChat and CDK resources

### 3. `cleanup-nuclear.sh` - Nuclear Cleanup (renamed from deep-clean-all-resources.sh)
- **Use when**: Complete AWS account cleanup needed
- **What it does**: 
  - Everything in deep cleanup PLUS
  - Manually deletes ALL AWS resources (VPCs, ENIs, etc.)
  - Removes IAM roles and policies (last)
- **Safety**: Low - comprehensive deletion

## Utility Scripts

### 4. `cleanup-failed-stacks.sh` (renamed from cleanup-failed.sh)
- **Use when**: Multiple stacks in FAILED states
- **What it does**: Finds and deletes all failed stacks
- **Safety**: High - only targets failed stacks

### 5. `cleanup-s3-buckets.sh` (renamed from force-s3-cleanup.sh)
- **Use when**: S3 buckets blocking deletion
- **What it does**: Empties and deletes S3 buckets across regions
- **Safety**: Medium - deletes bucket contents

### 6. `cleanup-stuck-stack.sh` (renamed from force-stack-cleanup.sh)
- **Use when**: Single stack stuck in DELETE_FAILED
- **What it does**: Force deletes specific stuck stack
- **Safety**: Medium - targets specific stack

## Usage Progression

1. Try `cleanup.sh` first (safest)
2. If that fails, use `cleanup-deep.sh`
3. For complete removal, use `cleanup-nuclear.sh`
4. Use utility scripts for specific issues