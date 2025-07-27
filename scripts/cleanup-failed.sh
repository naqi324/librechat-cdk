#!/bin/bash
# cleanup-failed.sh - Quick cleanup for failed CDK deployments

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Cleaning up failed CDK deployments${NC}"
echo "=================================="

# Find all stacks in failed states
echo -e "\n${BLUE}Finding failed stacks...${NC}"

FAILED_STACKS=""
FAILED_STATUSES="CREATE_FAILED ROLLBACK_COMPLETE UPDATE_ROLLBACK_COMPLETE DELETE_FAILED UPDATE_ROLLBACK_FAILED"

for status in $FAILED_STATUSES; do
    STACKS=$(aws cloudformation list-stacks --stack-status-filter "$status" --query "StackSummaries[*].[StackName,StackStatus]" --output text 2>/dev/null || echo "")
    if [ ! -z "$STACKS" ]; then
        while IFS=$'\t' read -r stack_name stack_status; do
            # Skip AWS internal stacks
            if [[ ! "$stack_name" == "aws-"* ]] && [[ ! "$stack_name" == "Amazon-"* ]]; then
                echo -e "${YELLOW}Found: $stack_name (Status: $stack_status)${NC}"
                FAILED_STACKS="$FAILED_STACKS$stack_name|$stack_status"$'\n'
            fi
        done <<< "$STACKS"
    fi
done

if [ -z "$FAILED_STACKS" ]; then
    echo -e "${GREEN}No failed stacks found!${NC}"
    exit 0
fi

# Count stacks
STACK_COUNT=$(echo -n "$FAILED_STACKS" | grep -c '^' || echo 0)
echo -e "\n${RED}Found $STACK_COUNT failed stack(s)${NC}"

echo
read -p "Delete all failed stacks? (y/n) [y]: " CONFIRM
CONFIRM="${CONFIRM:-y}"

if [ "$CONFIRM" != "y" ]; then
    echo -e "${GREEN}Cleanup cancelled${NC}"
    exit 0
fi

# Delete each failed stack
echo -e "\n${BLUE}Deleting failed stacks...${NC}"

while IFS='|' read -r stack_name stack_status; do
    if [ -z "$stack_name" ]; then
        continue
    fi
    
    echo -e "\n${YELLOW}Deleting: $stack_name${NC}"
    
    # For ROLLBACK_COMPLETE stacks, we can just delete
    if [ "$stack_status" == "ROLLBACK_COMPLETE" ]; then
        aws cloudformation delete-stack --stack-name "$stack_name" 2>/dev/null || true
        echo "  Delete command issued"
    # For other failed states, try to clean resources first
    else
        # Check for blocking resources
        echo "  Checking for blocking resources..."
        
        # S3 buckets
        S3_BUCKETS=$(aws cloudformation list-stack-resources --stack-name "$stack_name" --query "StackResourceSummaries[?ResourceType=='AWS::S3::Bucket'].PhysicalResourceId" --output text 2>/dev/null || echo "")
        if [ ! -z "$S3_BUCKETS" ]; then
            for bucket in $S3_BUCKETS; do
                echo "    Emptying S3 bucket: $bucket"
                aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
            done
        fi
        
        # ECR repositories
        ECR_REPOS=$(aws cloudformation list-stack-resources --stack-name "$stack_name" --query "StackResourceSummaries[?ResourceType=='AWS::ECR::Repository'].PhysicalResourceId" --output text 2>/dev/null || echo "")
        if [ ! -z "$ECR_REPOS" ]; then
            for repo in $ECR_REPOS; do
                echo "    Deleting ECR repository: $repo"
                aws ecr delete-repository --repository-name "$repo" --force 2>/dev/null || true
            done
        fi
        
        # Delete the stack
        aws cloudformation delete-stack --stack-name "$stack_name" 2>/dev/null || true
        echo "  Delete command issued"
    fi
done <<< "$FAILED_STACKS"

echo -e "\n${BLUE}Waiting for deletions to process...${NC}"
sleep 5

# Check results
echo -e "\n${BLUE}Checking results...${NC}"
REMAINING=0
for status in $FAILED_STATUSES; do
    COUNT=$(aws cloudformation list-stacks --stack-status-filter "$status" --query "length(StackSummaries[?!(starts_with(StackName, 'aws-') || starts_with(StackName, 'Amazon-'))])" --output text 2>/dev/null || echo "0")
    REMAINING=$((REMAINING + COUNT))
done

if [ "$REMAINING" -gt 0 ]; then
    echo -e "${YELLOW}$REMAINING failed stack(s) still exist. They may be deleting or require manual intervention.${NC}"
else
    echo -e "${GREEN}✅ All failed stacks have been cleaned up!${NC}"
fi

echo
echo "Tip: Run './scripts/check-resources.sh' to see all remaining resources"