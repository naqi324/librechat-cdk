#!/bin/bash
# deep-clean-cdk.sh - Comprehensive CDK stack cleanup

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║              CDK Deep Clean - Nuclear Option              ║${NC}"
echo -e "${RED}║                                                           ║${NC}"
echo -e "${RED}║  This will delete ALL CDK stacks and resources including: ║${NC}"
echo -e "${RED}║  - All CloudFormation stacks (any status)                 ║${NC}"
echo -e "${RED}║  - CDK bootstrap stacks                                   ║${NC}"
echo -e "${RED}║  - All associated AWS resources                           ║${NC}"
echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
echo

# Function to delete any CloudFormation stack
delete_any_stack() {
    local stack_name="$1"
    local stack_status="$2"
    
    echo -e "\n${YELLOW}Stack: $stack_name (Status: $stack_status)${NC}"
    
    # Handle different stack states
    case "$stack_status" in
        "CREATE_IN_PROGRESS"|"UPDATE_IN_PROGRESS"|"DELETE_IN_PROGRESS")
            echo "  Stack operation in progress, waiting..."
            # Cancel update if possible
            aws cloudformation cancel-update-stack --stack-name "$stack_name" 2>/dev/null || true
            sleep 10
            ;;
        "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS")
            echo "  Stack cleanup in progress, waiting..."
            sleep 10
            ;;
        "REVIEW_IN_PROGRESS")
            echo "  Stack in review, deleting changeset..."
            # Delete any changesets
            CHANGESETS=$(aws cloudformation list-change-sets --stack-name "$stack_name" --query 'Summaries[].ChangeSetName' --output text 2>/dev/null || echo "")
            for cs in $CHANGESETS; do
                aws cloudformation delete-change-set --stack-name "$stack_name" --change-set-name "$cs" 2>/dev/null || true
            done
            ;;
    esac
    
    # Force delete the stack
    echo "  Attempting to delete stack..."
    aws cloudformation delete-stack --stack-name "$stack_name" 2>/dev/null || true
    
    # For failed stacks, try to identify and remove blocking resources
    if [[ "$stack_status" == *"FAILED"* ]] || [[ "$stack_status" == "ROLLBACK_COMPLETE" ]]; then
        echo "  Stack in failed state, checking for blocking resources..."
        
        # Get stack resources
        RESOURCES=$(aws cloudformation list-stack-resources --stack-name "$stack_name" --query "StackResourceSummaries[?ResourceStatus!='DELETE_COMPLETE'].{Type:ResourceType,Id:PhysicalResourceId}" --output text 2>/dev/null || echo "")
        
        if [ ! -z "$RESOURCES" ]; then
            echo "  Found resources to clean up..."
            while IFS=$'\t' read -r resource_type physical_id; do
                case "$resource_type" in
                    "AWS::S3::Bucket")
                        echo "    Emptying S3 bucket: $physical_id"
                        aws s3 rm "s3://$physical_id" --recursive 2>/dev/null || true
                        aws s3api delete-bucket --bucket "$physical_id" 2>/dev/null || true
                        ;;
                    "AWS::ECR::Repository")
                        echo "    Deleting ECR repository: $physical_id"
                        aws ecr delete-repository --repository-name "$physical_id" --force 2>/dev/null || true
                        ;;
                    "AWS::Logs::LogGroup")
                        echo "    Deleting log group: $physical_id"
                        aws logs delete-log-group --log-group-name "$physical_id" 2>/dev/null || true
                        ;;
                esac
            done <<< "$RESOURCES"
        fi
        
        # Try deleting again
        aws cloudformation delete-stack --stack-name "$stack_name" 2>/dev/null || true
    fi
    
    # Don't wait for completion, move to next stack
    echo "  Delete command issued"
}

# Get ALL stacks, including those in any state
echo -e "${BLUE}Finding ALL CloudFormation stacks...${NC}"

# Get stacks in various states
ALL_STACKS=""
for status in "CREATE_COMPLETE" "UPDATE_COMPLETE" "ROLLBACK_COMPLETE" "CREATE_FAILED" "DELETE_FAILED" "UPDATE_ROLLBACK_COMPLETE" "IMPORT_COMPLETE" "IMPORT_ROLLBACK_COMPLETE" "UPDATE_ROLLBACK_FAILED" "CREATE_IN_PROGRESS" "DELETE_IN_PROGRESS" "REVIEW_IN_PROGRESS"; do
    STACKS=$(aws cloudformation list-stacks --stack-status-filter "$status" --query "StackSummaries[*].[StackName,StackStatus]" --output text 2>/dev/null || echo "")
    if [ ! -z "$STACKS" ]; then
        ALL_STACKS="$ALL_STACKS$STACKS"$'\n'
    fi
done

# Filter for CDK-related stacks
CDK_STACKS=""
BOOTSTRAP_STACKS=""
LIBRECHAT_STACKS=""

if [ ! -z "$ALL_STACKS" ]; then
    while IFS=$'\t' read -r stack_name stack_status; do
        if [ -z "$stack_name" ]; then
            continue
        fi
        
        # Check for CDK bootstrap stacks
        if [[ "$stack_name" == "CDKToolkit"* ]] || [[ "$stack_name" == *"CDKToolkit"* ]]; then
            BOOTSTRAP_STACKS="$BOOTSTRAP_STACKS$stack_name|$stack_status"$'\n'
        # Check for LibreChat stacks
        elif [[ "$stack_name" == *"LibreChat"* ]] || [[ "$stack_name" == *"librechat"* ]]; then
            LIBRECHAT_STACKS="$LIBRECHAT_STACKS$stack_name|$stack_status"$'\n'
        # Check for other CDK patterns
        elif [[ "$stack_name" == *"Stack"* ]] && [[ ! "$stack_name" == "aws-"* ]]; then
            # Check if it has CDK metadata
            HAS_CDK=$(aws cloudformation describe-stack-resources --stack-name "$stack_name" --query "StackResources[?ResourceType=='AWS::CDK::Metadata']" --output text 2>/dev/null || echo "")
            if [ ! -z "$HAS_CDK" ]; then
                CDK_STACKS="$CDK_STACKS$stack_name|$stack_status"$'\n'
            fi
        fi
    done <<< "$ALL_STACKS"
fi

# Count stacks found
TOTAL_COUNT=0
if [ ! -z "$BOOTSTRAP_STACKS" ]; then
    BOOTSTRAP_COUNT=$(echo -n "$BOOTSTRAP_STACKS" | grep -c '^')
    TOTAL_COUNT=$((TOTAL_COUNT + BOOTSTRAP_COUNT))
    echo -e "\n${YELLOW}Found $BOOTSTRAP_COUNT CDK Bootstrap stack(s)${NC}"
fi
if [ ! -z "$LIBRECHAT_STACKS" ]; then
    LIBRECHAT_COUNT=$(echo -n "$LIBRECHAT_STACKS" | grep -c '^')
    TOTAL_COUNT=$((TOTAL_COUNT + LIBRECHAT_COUNT))
    echo -e "${YELLOW}Found $LIBRECHAT_COUNT LibreChat stack(s)${NC}"
fi
if [ ! -z "$CDK_STACKS" ]; then
    CDK_COUNT=$(echo -n "$CDK_STACKS" | grep -c '^')
    TOTAL_COUNT=$((TOTAL_COUNT + CDK_COUNT))
    echo -e "${YELLOW}Found $CDK_COUNT other CDK stack(s)${NC}"
fi

if [ "$TOTAL_COUNT" -eq 0 ]; then
    echo -e "\n${GREEN}No CDK stacks found!${NC}"
    exit 0
fi

echo -e "\n${RED}Total stacks to delete: $TOTAL_COUNT${NC}"
echo
read -p "Type 'DELETE ALL' to confirm deletion of ALL stacks: " CONFIRM

if [ "$CONFIRM" != "DELETE ALL" ]; then
    echo -e "${GREEN}Cleanup cancelled${NC}"
    exit 0
fi

# Delete LibreChat stacks first (they might have dependencies)
if [ ! -z "$LIBRECHAT_STACKS" ]; then
    echo -e "\n${BLUE}Deleting LibreChat stacks...${NC}"
    while IFS='|' read -r stack_name stack_status; do
        if [ ! -z "$stack_name" ]; then
            delete_any_stack "$stack_name" "$stack_status"
        fi
    done <<< "$LIBRECHAT_STACKS"
fi

# Delete other CDK stacks
if [ ! -z "$CDK_STACKS" ]; then
    echo -e "\n${BLUE}Deleting other CDK stacks...${NC}"
    while IFS='|' read -r stack_name stack_status; do
        if [ ! -z "$stack_name" ]; then
            delete_any_stack "$stack_name" "$stack_status"
        fi
    done <<< "$CDK_STACKS"
fi

# Delete bootstrap stacks last
if [ ! -z "$BOOTSTRAP_STACKS" ]; then
    echo -e "\n${BLUE}Deleting CDK bootstrap stacks...${NC}"
    while IFS='|' read -r stack_name stack_status; do
        if [ ! -z "$stack_name" ]; then
            delete_any_stack "$stack_name" "$stack_status"
        fi
    done <<< "$BOOTSTRAP_STACKS"
fi

# Wait a bit for deletions to process
echo -e "\n${BLUE}Waiting for deletions to process...${NC}"
sleep 10

# Check what's left
echo -e "\n${BLUE}Checking remaining stacks...${NC}"
REMAINING=0
for status in "CREATE_COMPLETE" "UPDATE_COMPLETE" "ROLLBACK_COMPLETE" "CREATE_FAILED" "DELETE_FAILED" "UPDATE_ROLLBACK_COMPLETE"; do
    STACKS=$(aws cloudformation list-stacks --stack-status-filter "$status" --query "StackSummaries[?contains(StackName, 'LibreChat') || contains(StackName, 'CDKToolkit') || contains(StackName, 'librechat')].StackName" --output text 2>/dev/null || echo "")
    if [ ! -z "$STACKS" ]; then
        for stack in $STACKS; do
            echo -e "${YELLOW}Still exists: $stack${NC}"
            REMAINING=$((REMAINING + 1))
        done
    fi
done

if [ "$REMAINING" -gt 0 ]; then
    echo -e "\n${YELLOW}$REMAINING stack(s) still exist. They may be deleting or require manual intervention.${NC}"
    echo "Run this script again in a few minutes or check AWS Console for specific errors."
else
    echo -e "\n${GREEN}✅ All CDK stacks have been deleted or are deleting!${NC}"
fi

# Also clean up common CDK resources that might be orphaned
echo -e "\n${BLUE}Cleaning up orphaned CDK resources...${NC}"

# S3 buckets with CDK patterns
S3_BUCKETS=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'cdk-') || contains(Name, 'librechat')].Name" --output text 2>/dev/null || echo "")
if [ ! -z "$S3_BUCKETS" ]; then
    echo "Found S3 buckets to clean:"
    for bucket in $S3_BUCKETS; do
        echo "  Deleting bucket: $bucket"
        aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
        aws s3api delete-bucket --bucket "$bucket" 2>/dev/null || true
    done
fi

# ECR repositories
ECR_REPOS=$(aws ecr describe-repositories --query "repositories[?contains(repositoryName, 'cdk-') || contains(repositoryName, 'librechat')].repositoryName" --output text 2>/dev/null || echo "")
if [ ! -z "$ECR_REPOS" ]; then
    echo "Found ECR repositories to clean:"
    for repo in $ECR_REPOS; do
        echo "  Deleting repository: $repo"
        aws ecr delete-repository --repository-name "$repo" --force 2>/dev/null || true
    done
fi

echo -e "\n${GREEN}Deep clean complete!${NC}"
echo
echo "Note: Some resources may take several minutes to fully delete."
echo "Check AWS CloudFormation console for status."