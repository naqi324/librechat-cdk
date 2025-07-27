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
echo "║                                                           ║"
echo "║  For more cleanup options, see:                          ║"
echo "║  - cleanup-deep.sh: Deep cleanup with resource removal    ║"
echo "║  - cleanup-nuclear.sh: Complete AWS resource cleanup      ║"
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

# Function to delete a CloudFormation stack with retries
delete_stack() {
    local stack_name="$1"
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "Deleting CloudFormation stack: $stack_name (attempt $attempt/$max_attempts)"
        
        # Delete the stack
        aws cloudformation delete-stack --stack-name "$stack_name" 2>/dev/null || true
        
        # Wait for deletion
        echo "Waiting for stack deletion..."
        if aws cloudformation wait stack-delete-complete --stack-name "$stack_name" 2>/dev/null; then
            echo -e "${GREEN}✅ Stack $stack_name deleted successfully${NC}"
            return 0
        fi
        
        # Check if stack still exists
        local stack_status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DOES_NOT_EXIST")
        
        if [ "$stack_status" == "DOES_NOT_EXIST" ]; then
            echo -e "${GREEN}✅ Stack $stack_name deleted${NC}"
            return 0
        elif [ "$stack_status" == "DELETE_FAILED" ]; then
            echo -e "${YELLOW}Stack deletion failed, retrying...${NC}"
            # Try to delete retained resources
            local retained_resources=$(aws cloudformation list-stack-resources --stack-name "$stack_name" --query "StackResourceSummaries[?ResourceStatus=='DELETE_FAILED'].LogicalResourceId" --output text 2>/dev/null || echo "")
            if [ ! -z "$retained_resources" ]; then
                echo "Found retained resources: $retained_resources"
            fi
        fi
        
        attempt=$((attempt + 1))
        if [ $attempt -le $max_attempts ]; then
            sleep 10
        fi
    done
    
    echo -e "${RED}Failed to delete stack $stack_name after $max_attempts attempts${NC}"
    return 1
}

# Find all LibreChat-related stacks (including failed ones)
echo -e "${BLUE}Finding all LibreChat CloudFormation stacks...${NC}"

# Get stacks in various states
ALL_STACKS=""
STACK_STATUSES="CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE CREATE_FAILED DELETE_FAILED UPDATE_ROLLBACK_COMPLETE UPDATE_ROLLBACK_FAILED"

for status in $STACK_STATUSES; do
    STACKS=$(aws cloudformation list-stacks --stack-status-filter "$status" --query "StackSummaries[?contains(StackName, 'LibreChat') || contains(StackName, 'librechat') || StackName=='$STACK_NAME'].StackName" --output text 2>/dev/null || echo "")
    if [ ! -z "$STACKS" ]; then
        ALL_STACKS="$ALL_STACKS $STACKS"
    fi
done

# Remove duplicates
ALL_STACKS=$(echo "$ALL_STACKS" | tr ' ' '\n' | sort -u | tr '\n' ' ')

if [ -z "$ALL_STACKS" ]; then
    echo "No LibreChat stacks found"
else
    echo "Found stacks: $ALL_STACKS"
    
    # First, try using CDK if available
    if command -v cdk &> /dev/null && [ -f "cdk.json" ]; then
        echo -e "${BLUE}Using CDK to destroy stacks...${NC}"
        npm run build
        
        # Get the main stack name from CDK
        CDK_STACK=$(npx cdk list 2>/dev/null | grep -E "LibreChat|$STACK_NAME" | head -1 || echo "")
        if [ ! -z "$CDK_STACK" ]; then
            echo "Destroying CDK stack: $CDK_STACK"
            npx cdk destroy "$CDK_STACK" --force || true
        fi
    fi
    
    # Then use AWS CLI to ensure all stacks are deleted
    echo -e "\n${BLUE}Ensuring all stacks are deleted...${NC}"
    
    # Sort stacks to delete nested stacks first
    NESTED_STACKS=""
    ROOT_STACKS=""
    
    for stack in $ALL_STACKS; do
        # Check if it's a nested stack
        PARENT_ID=$(aws cloudformation describe-stacks --stack-name "$stack" --query 'Stacks[0].ParentId' --output text 2>/dev/null || echo "")
        if [ ! -z "$PARENT_ID" ] && [ "$PARENT_ID" != "None" ]; then
            NESTED_STACKS="$NESTED_STACKS $stack"
        else
            ROOT_STACKS="$ROOT_STACKS $stack"
        fi
    done
    
    # Delete nested stacks first
    if [ ! -z "$NESTED_STACKS" ]; then
        echo -e "\n${BLUE}Deleting nested stacks first...${NC}"
        for stack in $NESTED_STACKS; do
            delete_stack "$stack"
        done
    fi
    
    # Then delete root stacks
    if [ ! -z "$ROOT_STACKS" ]; then
        echo -e "\n${BLUE}Deleting root stacks...${NC}"
        for stack in $ROOT_STACKS; do
            delete_stack "$stack"
        done
    fi
fi

# Final verification
echo -e "\n${BLUE}Verifying all stacks are deleted...${NC}"
REMAINING_STACKS=$(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE DELETE_FAILED --query "StackSummaries[?contains(StackName, 'LibreChat') || StackName=='$STACK_NAME'].StackName" --output text 2>/dev/null || echo "")

if [ ! -z "$REMAINING_STACKS" ]; then
    echo -e "${RED}Warning: Some stacks may still exist: $REMAINING_STACKS${NC}"
    echo "Please check the AWS Console and delete them manually if needed"
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

# Clean up EFS file systems
echo "Checking for EFS file systems..."
EFS_SYSTEMS=$(aws efs describe-file-systems --query "FileSystems[?contains(Name, 'librechat') || contains(Name, 'LibreChat')].FileSystemId" --output text 2>/dev/null || echo "")
if [ ! -z "$EFS_SYSTEMS" ]; then
    for fs_id in $EFS_SYSTEMS; do
        echo "  Deleting EFS file system: $fs_id"
        # First delete mount targets
        MOUNT_TARGETS=$(aws efs describe-mount-targets --file-system-id "$fs_id" --query 'MountTargets[].MountTargetId' --output text 2>/dev/null || echo "")
        for mt_id in $MOUNT_TARGETS; do
            echo "    Deleting mount target: $mt_id"
            aws efs delete-mount-target --mount-target-id "$mt_id" 2>/dev/null || true
        done
        # Wait for mount targets to be deleted
        sleep 10
        # Delete the file system
        aws efs delete-file-system --file-system-id "$fs_id" 2>/dev/null || true
    done
fi

# Clean up S3 buckets
echo "Checking for S3 buckets..."
S3_BUCKETS=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'librechat')].Name" --output text 2>/dev/null || echo "")
if [ ! -z "$S3_BUCKETS" ]; then
    for bucket in $S3_BUCKETS; do
        echo "  Emptying and deleting S3 bucket: $bucket"
        # Delete all objects including versions
        aws s3 rm s3://$bucket --recursive 2>/dev/null || true
        # Delete all object versions
        aws s3api delete-objects --bucket $bucket \
            --delete "$(aws s3api list-object-versions --bucket $bucket \
            --output json --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' 2>/dev/null || echo '{}')" 2>/dev/null || true
        # Delete delete markers
        aws s3api delete-objects --bucket $bucket \
            --delete "$(aws s3api list-object-versions --bucket $bucket \
            --output json --query '{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' 2>/dev/null || echo '{}')" 2>/dev/null || true
        # Delete the bucket
        aws s3api delete-bucket --bucket $bucket 2>/dev/null || true
    done
fi

# Clean up VPC resources
echo "Checking for VPC resources..."

# First, clean up NAT Gateways (they cost money!)
NAT_GATEWAYS=$(aws ec2 describe-nat-gateways --filter "Name=tag:aws:cloudformation:stack-name,Values=LibreChatStack-*" "Name=state,Values=available,pending,deleting" --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null || echo "")
if [ ! -z "$NAT_GATEWAYS" ]; then
    for nat_id in $NAT_GATEWAYS; do
        echo "  Deleting NAT Gateway: $nat_id"
        aws ec2 delete-nat-gateway --nat-gateway-id "$nat_id" 2>/dev/null || true
    done
    # Wait for NAT gateways to be deleted
    echo "  Waiting for NAT Gateways to be deleted..."
    sleep 30
fi

# Release Elastic IPs
echo "Checking for Elastic IPs..."
ELASTIC_IPS=$(aws ec2 describe-addresses --filters "Name=tag:aws:cloudformation:stack-name,Values=LibreChatStack-*" --query 'Addresses[].AllocationId' --output text 2>/dev/null || echo "")
if [ ! -z "$ELASTIC_IPS" ]; then
    for eip_id in $ELASTIC_IPS; do
        echo "  Releasing Elastic IP: $eip_id"
        aws ec2 release-address --allocation-id "$eip_id" 2>/dev/null || true
    done
fi

# Clean up VPC Endpoints
VPC_ENDPOINTS=$(aws ec2 describe-vpc-endpoints --filters "Name=tag:aws:cloudformation:stack-name,Values=LibreChatStack-*" --query 'VpcEndpoints[].VpcEndpointId' --output text 2>/dev/null || echo "")
if [ ! -z "$VPC_ENDPOINTS" ]; then
    for endpoint_id in $VPC_ENDPOINTS; do
        echo "  Deleting VPC Endpoint: $endpoint_id"
        aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$endpoint_id" 2>/dev/null || true
    done
fi

# Clean up Internet Gateways
IGW_IDS=$(aws ec2 describe-internet-gateways --filters "Name=tag:aws:cloudformation:stack-name,Values=LibreChatStack-*" --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null || echo "")
if [ ! -z "$IGW_IDS" ]; then
    for igw_id in $IGW_IDS; do
        echo "  Checking Internet Gateway: $igw_id"
        # Get attached VPCs
        VPC_ATTACHMENTS=$(aws ec2 describe-internet-gateways --internet-gateway-ids "$igw_id" --query 'InternetGateways[0].Attachments[].VpcId' --output text 2>/dev/null || echo "")
        for vpc_id in $VPC_ATTACHMENTS; do
            echo "    Detaching from VPC: $vpc_id"
            aws ec2 detach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" 2>/dev/null || true
        done
        echo "    Deleting Internet Gateway: $igw_id"
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" 2>/dev/null || true
    done
fi

# Clean up security groups (sometimes they stick around)
echo "Checking for orphaned security groups..."
SG_IDS=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=LibreChatStack-*" --query 'SecurityGroups[].GroupId' --output text 2>/dev/null || echo "")
if [ ! -z "$SG_IDS" ]; then
    for sg_id in $SG_IDS; do
        echo "  Attempting to delete security group: $sg_id"
        # First try to remove all ingress and egress rules
        aws ec2 revoke-security-group-ingress --group-id "$sg_id" --source-group "$sg_id" --protocol all 2>/dev/null || true
        aws ec2 revoke-security-group-egress --group-id "$sg_id" --protocol all --cidr 0.0.0.0/0 2>/dev/null || true
        # Then delete the security group
        aws ec2 delete-security-group --group-id "$sg_id" 2>/dev/null || echo "    (May still be in use)"
    done
fi

# Clean up subnets
echo "Checking for subnets..."
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=tag:aws:cloudformation:stack-name,Values=LibreChatStack-*" --query 'Subnets[].SubnetId' --output text 2>/dev/null || echo "")
if [ ! -z "$SUBNET_IDS" ]; then
    for subnet_id in $SUBNET_IDS; do
        echo "  Attempting to delete subnet: $subnet_id"
        aws ec2 delete-subnet --subnet-id "$subnet_id" 2>/dev/null || echo "    (May still have dependencies)"
    done
fi

# Clean up route tables
echo "Checking for route tables..."
ROUTE_TABLES=$(aws ec2 describe-route-tables --filters "Name=tag:aws:cloudformation:stack-name,Values=LibreChatStack-*" --query 'RouteTables[].RouteTableId' --output text 2>/dev/null || echo "")
if [ ! -z "$ROUTE_TABLES" ]; then
    for rt_id in $ROUTE_TABLES; do
        echo "  Attempting to delete route table: $rt_id"
        # First disassociate from subnets
        ASSOCIATIONS=$(aws ec2 describe-route-tables --route-table-ids "$rt_id" --query 'RouteTables[0].Associations[?SubnetId!=`null`].RouteTableAssociationId' --output text 2>/dev/null || echo "")
        for assoc_id in $ASSOCIATIONS; do
            aws ec2 disassociate-route-table --association-id "$assoc_id" 2>/dev/null || true
        done
        # Delete the route table
        aws ec2 delete-route-table --route-table-id "$rt_id" 2>/dev/null || echo "    (May be main route table)"
    done
fi

# Finally, clean up VPCs
echo "Checking for VPCs..."
VPC_IDS=$(aws ec2 describe-vpcs --filters "Name=tag:aws:cloudformation:stack-name,Values=LibreChatStack-*" --query 'Vpcs[].VpcId' --output text 2>/dev/null || echo "")
if [ ! -z "$VPC_IDS" ]; then
    for vpc_id in $VPC_IDS; do
        echo "  Attempting to delete VPC: $vpc_id"
        aws ec2 delete-vpc --vpc-id "$vpc_id" 2>/dev/null || echo "    (May still have dependencies)"
    done
fi

echo -e "\n${GREEN}✅ Cleanup complete!${NC}"
echo
echo "The following have been deleted:"
echo
echo "COMPUTE:"
echo "  - EC2 instances"
echo "  - ECS clusters, services, and tasks"
echo "  - ECS task definitions"
echo "  - Lambda functions"
echo
echo "STORAGE:"
echo "  - S3 buckets (with all objects and versions)"
echo "  - EFS file systems and mount targets"
echo "  - ECR repositories"
echo
echo "NETWORK:"
echo "  - VPCs and subnets"
echo "  - NAT Gateways ($$$ saved!)"
echo "  - Internet Gateways"
echo "  - Elastic IPs"
echo "  - Route tables"
echo "  - VPC Endpoints"
echo "  - Security groups"
echo
echo "DATABASE:"
echo "  - RDS instances and clusters"
echo "  - DocumentDB clusters"
echo
echo "MONITORING & IAM:"
echo "  - CloudWatch Log Groups"
echo "  - IAM roles and policies"
echo
echo -e "${YELLOW}Note: Some resources managed by CloudFormation may require the stack deletion to complete first.${NC}"
echo -e "${YELLOW}If any resources remain, wait a few minutes and run the cleanup script again.${NC}"

# Offer to clean local files
echo
read -p "Also clean local build files? (y/n) [n]: " CLEAN_LOCAL
if [ "$CLEAN_LOCAL" = "y" ]; then
    echo "Cleaning local files..."
    npm run clean
    rm -f .env deployment-info.json
    echo -e "${GREEN}Local files cleaned${NC}"
fi
