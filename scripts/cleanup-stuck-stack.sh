#!/bin/bash
# force-stack-cleanup.sh - Force cleanup of stubborn CloudFormation stacks

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${RED}Force CloudFormation Stack Cleanup${NC}"
echo "=================================="

# Function to delete stack resources manually
delete_stack_resources() {
    local stack_name="$1"
    
    echo -e "\n${BLUE}Analyzing stack resources for: $stack_name${NC}"
    
    # Get all resources in the stack
    RESOURCES=$(aws cloudformation list-stack-resources --stack-name "$stack_name" --query "StackResourceSummaries[].{Type:ResourceType,LogicalId:LogicalResourceId,PhysicalId:PhysicalResourceId,Status:ResourceStatus}" --output json 2>/dev/null || echo "[]")
    
    if [ "$RESOURCES" == "[]" ]; then
        echo "No resources found in stack"
        return 0
    fi
    
    echo "$RESOURCES" | jq -r '.[] | "\(.Type)|\(.LogicalId)|\(.PhysicalId)|\(.Status)"' | while IFS='|' read -r resource_type logical_id physical_id status; do
        echo -e "\n${YELLOW}Resource: $logical_id${NC}"
        echo "  Type: $resource_type"
        echo "  Physical ID: $physical_id"
        echo "  Status: $status"
        
        # Skip if already deleted
        if [[ "$status" == "DELETE_COMPLETE" ]]; then
            echo "  Already deleted, skipping..."
            continue
        fi
        
        # Handle specific resource types that might block deletion
        case "$resource_type" in
            "AWS::S3::Bucket")
                echo "  Emptying and deleting S3 bucket..."
                aws s3 rm "s3://$physical_id" --recursive 2>/dev/null || true
                aws s3api delete-bucket --bucket "$physical_id" 2>/dev/null || true
                ;;
                
            "AWS::ECR::Repository")
                echo "  Deleting ECR repository..."
                aws ecr delete-repository --repository-name "$physical_id" --force 2>/dev/null || true
                ;;
                
            "AWS::ECS::Service")
                # Extract cluster name from service ARN
                cluster_name=$(echo "$physical_id" | cut -d'/' -f2)
                service_name=$(echo "$physical_id" | cut -d'/' -f3)
                echo "  Scaling down and deleting ECS service..."
                aws ecs update-service --cluster "$cluster_name" --service "$service_name" --desired-count 0 2>/dev/null || true
                aws ecs delete-service --cluster "$cluster_name" --service "$service_name" --force 2>/dev/null || true
                ;;
                
            "AWS::ECS::Cluster")
                echo "  Deleting ECS cluster..."
                aws ecs delete-cluster --cluster "$physical_id" 2>/dev/null || true
                ;;
                
            "AWS::RDS::DBInstance")
                echo "  Deleting RDS instance (without final snapshot)..."
                aws rds delete-db-instance --db-instance-identifier "$physical_id" --skip-final-snapshot --delete-automated-backups 2>/dev/null || true
                ;;
                
            "AWS::RDS::DBCluster")
                echo "  Deleting RDS cluster (without final snapshot)..."
                aws rds delete-db-cluster --db-cluster-identifier "$physical_id" --skip-final-snapshot 2>/dev/null || true
                ;;
                
            "AWS::EC2::SecurityGroup")
                echo "  Removing security group rules and deleting..."
                # Remove all ingress rules
                aws ec2 revoke-security-group-ingress --group-id "$physical_id" --protocol all --source-group "$physical_id" 2>/dev/null || true
                # Delete the security group
                aws ec2 delete-security-group --group-id "$physical_id" 2>/dev/null || true
                ;;
                
            "AWS::EFS::FileSystem")
                echo "  Deleting EFS mount targets and file system..."
                # Delete mount targets first
                MOUNT_TARGETS=$(aws efs describe-mount-targets --file-system-id "$physical_id" --query 'MountTargets[].MountTargetId' --output text 2>/dev/null || echo "")
                for mt in $MOUNT_TARGETS; do
                    aws efs delete-mount-target --mount-target-id "$mt" 2>/dev/null || true
                done
                sleep 5
                # Delete file system
                aws efs delete-file-system --file-system-id "$physical_id" 2>/dev/null || true
                ;;
                
            "AWS::CloudWatch::LogGroup")
                echo "  Deleting CloudWatch log group..."
                aws logs delete-log-group --log-group-name "$physical_id" 2>/dev/null || true
                ;;
                
            *)
                echo "  Resource type $resource_type - manual deletion may be required"
                ;;
        esac
    done
}

# Main script
if [ -z "$1" ]; then
    echo "Usage: $0 <stack-name>"
    echo
    echo "This script will:"
    echo "1. Identify all resources in the stack"
    echo "2. Force delete resources that might be blocking stack deletion"
    echo "3. Retry stack deletion"
    echo
    exit 1
fi

STACK_NAME="$1"

# Check if stack exists
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DOES_NOT_EXIST")

if [ "$STACK_STATUS" == "DOES_NOT_EXIST" ]; then
    echo -e "${GREEN}Stack $STACK_NAME does not exist${NC}"
    exit 0
fi

echo -e "${YELLOW}Stack Status: $STACK_STATUS${NC}"

# If stack is in DELETE_FAILED state, try to identify the problem
if [ "$STACK_STATUS" == "DELETE_FAILED" ]; then
    echo -e "\n${RED}Stack is in DELETE_FAILED state${NC}"
    echo "Checking for resources that failed to delete..."
    
    FAILED_RESOURCES=$(aws cloudformation list-stack-resources --stack-name "$STACK_NAME" --query "StackResourceSummaries[?ResourceStatus=='DELETE_FAILED'].{Type:ResourceType,LogicalId:LogicalResourceId,PhysicalId:PhysicalResourceId}" --output table 2>/dev/null || echo "")
    
    if [ ! -z "$FAILED_RESOURCES" ]; then
        echo -e "\n${YELLOW}Resources that failed to delete:${NC}"
        echo "$FAILED_RESOURCES"
    fi
fi

# Attempt to delete stack resources manually
delete_stack_resources "$STACK_NAME"

# Wait a bit for resources to be deleted
echo -e "\n${BLUE}Waiting for resource deletion to complete...${NC}"
sleep 10

# Try to delete the stack again
echo -e "\n${BLUE}Attempting to delete stack again...${NC}"
aws cloudformation delete-stack --stack-name "$STACK_NAME" 2>/dev/null || true

# Wait for deletion
echo "Waiting for stack deletion..."
if aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" 2>/dev/null; then
    echo -e "${GREEN}✅ Stack deleted successfully!${NC}"
else
    # Final status check
    FINAL_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DOES_NOT_EXIST")
    
    if [ "$FINAL_STATUS" == "DOES_NOT_EXIST" ]; then
        echo -e "${GREEN}✅ Stack deleted successfully!${NC}"
    else
        echo -e "${RED}Stack deletion failed. Final status: $FINAL_STATUS${NC}"
        echo
        echo "You may need to:"
        echo "1. Check the AWS Console for specific error messages"
        echo "2. Manually delete remaining resources"
        echo "3. Contact AWS Support if resources are stuck"
        exit 1
    fi
fi