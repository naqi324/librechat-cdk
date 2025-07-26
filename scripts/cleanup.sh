#!/bin/bash
# cleanup.sh - Clean up all LibreChat CDK resources

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${RED}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                    ⚠️  WARNING ⚠️                           ║"
echo "║                                                           ║"
echo "║  This will DELETE ALL LibreChat resources including:      ║"
echo "║  - EC2/ECS instances and services                         ║"
echo "║  - RDS databases (with all data)                         ║"
echo "║  - S3 buckets and stored files                           ║"
echo "║  - VPC and networking resources                          ║"
echo "║  - All other AWS resources created by this stack         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Get environment from .env or default
if [ -f .env ]; then
    source .env
fi
ENVIRONMENT=${DEPLOYMENT_ENV:-development}
STACK_NAME=${1:-"LibreChatStack-${ENVIRONMENT}"}

echo -e "${YELLOW}Stack to be deleted: ${STACK_NAME}${NC}"
echo

read -p "Type 'DELETE' to confirm deletion: " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
    echo -e "${GREEN}Cleanup cancelled - no resources were deleted${NC}"
    exit 0
fi

# Change to project root
cd "$(dirname "$0")/.."

echo -e "\n${BLUE}Starting cleanup process...${NC}"

# Check if CDK is installed
if ! command -v cdk &> /dev/null; then
    echo -e "${YELLOW}CDK not found, using AWS CLI directly${NC}"
    
    # Delete stack using AWS CLI
    echo "Deleting CloudFormation stack: $STACK_NAME"
    aws cloudformation delete-stack --stack-name "$STACK_NAME"
    
    echo "Waiting for stack deletion..."
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" 2>/dev/null || true
else
    # Use CDK destroy
    echo -e "${BLUE}Using CDK to destroy stack...${NC}"
    npm run build
    cdk destroy "$STACK_NAME" --force
fi

# Check if stack was deleted
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" &> /dev/null; then
    echo -e "${RED}Stack deletion may have failed. Please check AWS Console.${NC}"
    exit 1
fi

# Additional cleanup for resources that might not be deleted by CloudFormation
echo -e "\n${BLUE}Performing additional cleanup...${NC}"

# Clean up CloudWatch Log Groups
echo "Cleaning up CloudWatch Log Groups..."
LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/LibreChat" --query 'logGroups[].logGroupName' --output text 2>/dev/null || echo "")
if [ ! -z "$LOG_GROUPS" ]; then
    for log_group in $LOG_GROUPS; do
        echo "  Deleting log group: $log_group"
        aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || true
    done
fi

# Clean up ECS/EC2 related log groups
for prefix in "/ecs/librechat" "/aws/ecs/librechat" "/aws/ec2/librechat"; do
    LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "$prefix" --query 'logGroups[].logGroupName' --output text 2>/dev/null || echo "")
    if [ ! -z "$LOG_GROUPS" ]; then
        for log_group in $LOG_GROUPS; do
            echo "  Deleting log group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || true
        done
    fi
done

# Clean up Lambda execution roles (if any remain)
echo "Checking for orphaned Lambda execution roles..."
LAMBDA_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, 'LibreChatStack') && contains(RoleName, 'Lambda')].RoleName" --output text 2>/dev/null || echo "")
if [ ! -z "$LAMBDA_ROLES" ]; then
    for role in $LAMBDA_ROLES; do
        echo "  Cleaning up role: $role"
        # First detach all policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
        for policy in $ATTACHED_POLICIES; do
            aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" 2>/dev/null || true
        done
        # Delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
        for policy in $INLINE_POLICIES; do
            aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
        done
        # Delete the role
        aws iam delete-role --role-name "$role" 2>/dev/null || true
    done
fi

# Clean up ECS resources
echo "Checking for ECS resources..."

# List and delete ECS services
ECS_CLUSTERS=$(aws ecs list-clusters --query 'clusterArns[]' --output text 2>/dev/null || echo "")
if [ ! -z "$ECS_CLUSTERS" ]; then
    for cluster_arn in $ECS_CLUSTERS; do
        CLUSTER_NAME=$(echo $cluster_arn | rev | cut -d'/' -f1 | rev)
        if [[ "$CLUSTER_NAME" == *"LibreChat"* ]] || [[ "$CLUSTER_NAME" == *"$ENVIRONMENT"* ]]; then
            echo "  Found ECS cluster: $CLUSTER_NAME"
            
            # List and delete services in the cluster
            SERVICES=$(aws ecs list-services --cluster "$cluster_arn" --query 'serviceArns[]' --output text 2>/dev/null || echo "")
            if [ ! -z "$SERVICES" ]; then
                for service_arn in $SERVICES; do
                    SERVICE_NAME=$(echo $service_arn | rev | cut -d'/' -f1 | rev)
                    echo "    Deleting service: $SERVICE_NAME"
                    # Update desired count to 0
                    aws ecs update-service --cluster "$cluster_arn" --service "$SERVICE_NAME" --desired-count 0 2>/dev/null || true
                    # Delete the service
                    aws ecs delete-service --cluster "$cluster_arn" --service "$SERVICE_NAME" --force 2>/dev/null || true
                done
                
                # Wait for services to be deleted
                echo "    Waiting for services to be deleted..."
                sleep 10
            fi
            
            # List and stop tasks
            TASKS=$(aws ecs list-tasks --cluster "$cluster_arn" --query 'taskArns[]' --output text 2>/dev/null || echo "")
            if [ ! -z "$TASKS" ]; then
                echo "    Stopping running tasks..."
                for task_arn in $TASKS; do
                    aws ecs stop-task --cluster "$cluster_arn" --task "$task_arn" 2>/dev/null || true
                done
                sleep 5
            fi
            
            # Delete the cluster
            echo "    Deleting cluster: $CLUSTER_NAME"
            aws ecs delete-cluster --cluster "$cluster_arn" 2>/dev/null || true
        fi
    done
fi

# Clean up ECS task definitions
echo "Checking for ECS task definitions..."
TASK_DEFS=$(aws ecs list-task-definitions --family-prefix "LibreChat" --query 'taskDefinitionArns[]' --output text 2>/dev/null || echo "")
if [ ! -z "$TASK_DEFS" ]; then
    for task_def in $TASK_DEFS; do
        echo "  Deregistering task definition: $task_def"
        aws ecs deregister-task-definition --task-definition "$task_def" 2>/dev/null || true
    done
fi

# Clean up ECR repositories (from ECS deployments)
echo "Checking for ECR repositories..."
ECR_REPOS=$(aws ecr describe-repositories --query "repositories[?contains(repositoryName, 'librechat')].repositoryName" --output text 2>/dev/null || echo "")
if [ ! -z "$ECR_REPOS" ]; then
    for repo in $ECR_REPOS; do
        echo "  Deleting ECR repository: $repo"
        aws ecr delete-repository --repository-name "$repo" --force 2>/dev/null || true
    done
fi

# Clean up security groups (sometimes they stick around)
echo "Checking for orphaned security groups..."
SG_IDS=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=LibreChatStack-*" --query 'SecurityGroups[].GroupId' --output text 2>/dev/null || echo "")
if [ ! -z "$SG_IDS" ]; then
    for sg_id in $SG_IDS; do
        echo "  Attempting to delete security group: $sg_id"
        aws ec2 delete-security-group --group-id "$sg_id" 2>/dev/null || echo "    (May still be in use)"
    done
fi

echo -e "\n${GREEN}✅ Cleanup complete!${NC}"
echo
echo "The following have been deleted:"
echo "  - All compute resources (EC2/ECS)"
echo "  - ECS clusters, services, and tasks"
echo "  - ECS task definitions"
echo "  - ECR repositories"
echo "  - All databases"
echo "  - All storage buckets"
echo "  - All networking resources"
echo "  - CloudWatch Log Groups"
echo "  - Orphaned IAM roles"
echo "  - Orphaned security groups"
echo
echo -e "${YELLOW}Note: Some service-linked roles are managed by AWS and cannot be deleted immediately.${NC}"

# Offer to clean local files
echo
read -p "Also clean local build files? (y/n) [n]: " CLEAN_LOCAL
if [ "$CLEAN_LOCAL" = "y" ]; then
    echo "Cleaning local files..."
    npm run clean
    rm -f .env deployment-info.json
    echo -e "${GREEN}Local files cleaned${NC}"
fi
