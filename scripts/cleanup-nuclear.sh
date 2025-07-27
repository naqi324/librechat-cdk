#!/bin/bash
# cleanup-nuclear.sh - Complete removal of ALL AWS resources created by LibreChat
# WARNING: This is the nuclear option - removes everything including IAM roles
# Use when: You need complete cleanup of all AWS resources

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║        COMPLETE AWS RESOURCE CLEANUP - NUCLEAR OPTION      ║${NC}"
echo -e "${RED}║                                                           ║${NC}"
echo -e "${RED}║  This will delete ALL resources including:                ║${NC}"
echo -e "${RED}║  - CloudFormation stacks                                  ║${NC}"
echo -e "${RED}║  - S3 buckets (with contents)                            ║${NC}"
echo -e "${RED}║  - ECS clusters, services, and task definitions          ║${NC}"
echo -e "${RED}║  - EC2 instances and security groups                     ║${NC}"
echo -e "${RED}║  - RDS databases and snapshots                           ║${NC}"
echo -e "${RED}║  - DocumentDB clusters                                   ║${NC}"
echo -e "${RED}║  - VPCs, subnets, and network interfaces                ║${NC}"
echo -e "${RED}║  - Load balancers and target groups                     ║${NC}"
echo -e "${RED}║  - Lambda functions and layers                           ║${NC}"
echo -e "${RED}║  - EFS file systems                                      ║${NC}"
echo -e "${RED}║  - CloudWatch logs                                       ║${NC}"
echo -e "${RED}║  - Secrets Manager secrets                               ║${NC}"
echo -e "${RED}║  - IAM roles and policies (last)                         ║${NC}"
echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
echo

# Get AWS account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)

echo -e "${BLUE}Account: $ACCOUNT_ID${NC}"
echo -e "${BLUE}Region: $REGION${NC}"
echo

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type=$1
    local check_command=$2
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if ! eval "$check_command" > /dev/null 2>&1; then
            echo -e "  ${GREEN}✓ $resource_type deleted${NC}"
            return 0
        fi
        echo -n "."
        sleep 2
        ((attempt++))
    done
    echo -e "  ${YELLOW}⚠ $resource_type deletion timed out${NC}"
    return 1
}

# Get all stacks with LibreChat in the name
echo -e "${BLUE}Finding LibreChat-related stacks...${NC}"
STACKS=$(aws cloudformation list-stacks \
    --query "StackSummaries[?contains(StackName, 'LibreChat') || contains(StackName, 'librechat')].StackName" \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE CREATE_FAILED DELETE_FAILED UPDATE_ROLLBACK_COMPLETE \
    --output text 2>/dev/null || echo "")

if [ -z "$STACKS" ]; then
    echo -e "${YELLOW}No LibreChat stacks found. Checking for orphaned resources...${NC}"
else
    echo -e "${YELLOW}Found stacks: $STACKS${NC}"
fi

read -p "Type 'DELETE ALL RESOURCES' to confirm complete cleanup: " CONFIRM

if [ "$CONFIRM" != "DELETE ALL RESOURCES" ]; then
    echo -e "${GREEN}Cleanup cancelled${NC}"
    exit 0
fi

# Step 1: Empty and delete S3 buckets first (they block stack deletion)
echo -e "\n${BLUE}Step 1: Cleaning S3 buckets...${NC}"
S3_BUCKETS=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'librechat') || contains(Name, 'cdk-')].Name" --output text 2>/dev/null || echo "")
if [ ! -z "$S3_BUCKETS" ]; then
    for bucket in $S3_BUCKETS; do
        echo "  Emptying and deleting bucket: $bucket"
        # Delete all versions and delete markers
        aws s3api list-object-versions --bucket "$bucket" --output json 2>/dev/null | \
            jq -r '.Versions[]?, .DeleteMarkers[]? | "\(.Key) \(.VersionId)"' | \
            while read key version; do
                aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version" 2>/dev/null || true
            done
        # Delete the bucket
        aws s3api delete-bucket --bucket "$bucket" 2>/dev/null || true
    done
fi

# Step 2: Delete ECS services (they prevent cluster deletion)
echo -e "\n${BLUE}Step 2: Cleaning ECS resources...${NC}"
ECS_CLUSTERS=$(aws ecs list-clusters --query "clusterArns[?contains(@, 'LibreChat') || contains(@, 'librechat')]" --output text 2>/dev/null || echo "")
if [ ! -z "$ECS_CLUSTERS" ]; then
    for cluster in $ECS_CLUSTERS; do
        CLUSTER_NAME=$(echo $cluster | rev | cut -d'/' -f1 | rev)
        echo "  Processing cluster: $CLUSTER_NAME"
        
        # Get and delete services
        SERVICES=$(aws ecs list-services --cluster "$CLUSTER_NAME" --query "serviceArns" --output text 2>/dev/null || echo "")
        if [ ! -z "$SERVICES" ]; then
            for service in $SERVICES; do
                SERVICE_NAME=$(echo $service | rev | cut -d'/' -f1 | rev)
                echo "    Scaling down and deleting service: $SERVICE_NAME"
                aws ecs update-service --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" --desired-count 0 2>/dev/null || true
                aws ecs delete-service --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" --force 2>/dev/null || true
            done
        fi
    done
fi

# Step 3: Delete load balancers and target groups
echo -e "\n${BLUE}Step 3: Cleaning load balancers...${NC}"
# Application Load Balancers
ALBS=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'LibreChat') || contains(LoadBalancerName, 'librechat')].LoadBalancerArn" --output text 2>/dev/null || echo "")
if [ ! -z "$ALBS" ]; then
    for alb in $ALBS; do
        ALB_NAME=$(aws elbv2 describe-load-balancers --load-balancer-arns "$alb" --query "LoadBalancers[0].LoadBalancerName" --output text)
        echo "  Deleting ALB: $ALB_NAME"
        aws elbv2 delete-load-balancer --load-balancer-arn "$alb" 2>/dev/null || true
    done
fi

# Target Groups
TGS=$(aws elbv2 describe-target-groups --query "TargetGroups[?contains(TargetGroupName, 'LibreChat') || contains(TargetGroupName, 'librechat')].TargetGroupArn" --output text 2>/dev/null || echo "")
if [ ! -z "$TGS" ]; then
    for tg in $TGS; do
        echo "  Deleting target group: $tg"
        aws elbv2 delete-target-group --target-group-arn "$tg" 2>/dev/null || true
    done
fi

# Step 4: Delete RDS instances and clusters
echo -e "\n${BLUE}Step 4: Cleaning RDS resources...${NC}"
# RDS instances
RDS_INSTANCES=$(aws rds describe-db-instances --query "DBInstances[?contains(DBInstanceIdentifier, 'librechat')].DBInstanceIdentifier" --output text 2>/dev/null || echo "")
if [ ! -z "$RDS_INSTANCES" ]; then
    for instance in $RDS_INSTANCES; do
        echo "  Deleting RDS instance: $instance"
        aws rds delete-db-instance --db-instance-identifier "$instance" --skip-final-snapshot --delete-automated-backups 2>/dev/null || true
    done
fi

# Aurora clusters
AURORA_CLUSTERS=$(aws rds describe-db-clusters --query "DBClusters[?contains(DBClusterIdentifier, 'librechat')].DBClusterIdentifier" --output text 2>/dev/null || echo "")
if [ ! -z "$AURORA_CLUSTERS" ]; then
    for cluster in $AURORA_CLUSTERS; do
        echo "  Deleting Aurora cluster: $cluster"
        # Delete cluster instances first
        CLUSTER_INSTANCES=$(aws rds describe-db-clusters --db-cluster-identifier "$cluster" --query "DBClusters[0].DBClusterMembers[].DBInstanceIdentifier" --output text 2>/dev/null || echo "")
        for instance in $CLUSTER_INSTANCES; do
            aws rds delete-db-instance --db-instance-identifier "$instance" --skip-final-snapshot 2>/dev/null || true
        done
        # Then delete the cluster
        aws rds delete-db-cluster --db-cluster-identifier "$cluster" --skip-final-snapshot 2>/dev/null || true
    done
fi

# Step 5: Delete DocumentDB clusters
echo -e "\n${BLUE}Step 5: Cleaning DocumentDB resources...${NC}"
DOCDB_CLUSTERS=$(aws docdb describe-db-clusters --query "DBClusters[?contains(DBClusterIdentifier, 'librechat')].DBClusterIdentifier" --output text 2>/dev/null || echo "")
if [ ! -z "$DOCDB_CLUSTERS" ]; then
    for cluster in $DOCDB_CLUSTERS; do
        echo "  Deleting DocumentDB cluster: $cluster"
        # Delete cluster instances first
        DOCDB_INSTANCES=$(aws docdb describe-db-clusters --db-cluster-identifier "$cluster" --query "DBClusters[0].DBClusterMembers[].DBInstanceIdentifier" --output text 2>/dev/null || echo "")
        for instance in $DOCDB_INSTANCES; do
            aws docdb delete-db-instance --db-instance-identifier "$instance" --skip-final-snapshot 2>/dev/null || true
        done
        # Then delete the cluster
        aws docdb delete-db-cluster --db-cluster-identifier "$cluster" --skip-final-snapshot 2>/dev/null || true
    done
fi

# Step 6: Delete EFS file systems
echo -e "\n${BLUE}Step 6: Cleaning EFS file systems...${NC}"
EFS_FILESYSTEMS=$(aws efs describe-file-systems --query "FileSystems[?contains(Name, 'LibreChat') || contains(Name, 'librechat')].FileSystemId" --output text 2>/dev/null || echo "")
if [ ! -z "$EFS_FILESYSTEMS" ]; then
    for fs in $EFS_FILESYSTEMS; do
        echo "  Deleting EFS file system: $fs"
        # Delete mount targets first
        MOUNT_TARGETS=$(aws efs describe-mount-targets --file-system-id "$fs" --query "MountTargets[].MountTargetId" --output text 2>/dev/null || echo "")
        for mt in $MOUNT_TARGETS; do
            aws efs delete-mount-target --mount-target-id "$mt" 2>/dev/null || true
        done
        # Wait a bit for mount targets to delete
        sleep 5
        # Delete the file system
        aws efs delete-file-system --file-system-id "$fs" 2>/dev/null || true
    done
fi

# Step 7: Delete Lambda functions
echo -e "\n${BLUE}Step 7: Cleaning Lambda functions...${NC}"
LAMBDA_FUNCTIONS=$(aws lambda list-functions --query "Functions[?contains(FunctionName, 'LibreChat') || contains(FunctionName, 'librechat')].FunctionName" --output text 2>/dev/null || echo "")
if [ ! -z "$LAMBDA_FUNCTIONS" ]; then
    for func in $LAMBDA_FUNCTIONS; do
        echo "  Deleting Lambda function: $func"
        aws lambda delete-function --function-name "$func" 2>/dev/null || true
    done
fi

# Step 8: Delete CloudWatch Log Groups
echo -e "\n${BLUE}Step 8: Cleaning CloudWatch logs...${NC}"
LOG_GROUPS=$(aws logs describe-log-groups --query "logGroups[?contains(logGroupName, 'librechat') || contains(logGroupName, 'LibreChat')].logGroupName" --output text 2>/dev/null || echo "")
if [ ! -z "$LOG_GROUPS" ]; then
    for lg in $LOG_GROUPS; do
        echo "  Deleting log group: $lg"
        aws logs delete-log-group --log-group-name "$lg" 2>/dev/null || true
    done
fi

# Step 9: Delete Secrets
echo -e "\n${BLUE}Step 9: Cleaning Secrets Manager secrets...${NC}"
SECRETS=$(aws secretsmanager list-secrets --query "SecretList[?contains(Name, 'librechat') || contains(Name, 'LibreChat')].ARN" --output text 2>/dev/null || echo "")
if [ ! -z "$SECRETS" ]; then
    for secret in $SECRETS; do
        echo "  Deleting secret: $secret"
        aws secretsmanager delete-secret --secret-id "$secret" --force-delete-without-recovery 2>/dev/null || true
    done
fi

# Step 10: Delete EC2 instances
echo -e "\n${BLUE}Step 10: Cleaning EC2 instances...${NC}"
EC2_INSTANCES=$(aws ec2 describe-instances --filters "Name=tag:aws:cloudformation:stack-name,Values=LibreChat*" "Name=instance-state-name,Values=running,stopped" --query "Reservations[].Instances[].InstanceId" --output text 2>/dev/null || echo "")
if [ ! -z "$EC2_INSTANCES" ]; then
    for instance in $EC2_INSTANCES; do
        echo "  Terminating instance: $instance"
        aws ec2 terminate-instances --instance-ids "$instance" 2>/dev/null || true
    done
fi

# Step 11: Try to delete CloudFormation stacks
echo -e "\n${BLUE}Step 11: Deleting CloudFormation stacks...${NC}"
if [ ! -z "$STACKS" ]; then
    for stack in $STACKS; do
        echo "  Deleting stack: $stack"
        aws cloudformation delete-stack --stack-name "$stack" 2>/dev/null || true
    done
fi

# Wait for some deletions to complete
echo -e "\n${BLUE}Waiting for resources to delete...${NC}"
sleep 30

# Step 12: Clean up remaining network interfaces
echo -e "\n${BLUE}Step 12: Cleaning network interfaces...${NC}"
# Get VPCs with LibreChat tag
VPCS=$(aws ec2 describe-vpcs --filters "Name=tag:aws:cloudformation:stack-name,Values=LibreChat*" --query "Vpcs[].VpcId" --output text 2>/dev/null || echo "")
if [ ! -z "$VPCS" ]; then
    for vpc in $VPCS; do
        # Delete network interfaces
        ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpc" --query "NetworkInterfaces[].NetworkInterfaceId" --output text 2>/dev/null || echo "")
        for eni in $ENIS; do
            echo "  Detaching and deleting ENI: $eni"
            # Get attachment ID if attached
            ATTACHMENT=$(aws ec2 describe-network-interfaces --network-interface-ids "$eni" --query "NetworkInterfaces[0].Attachment.AttachmentId" --output text 2>/dev/null || echo "")
            if [ "$ATTACHMENT" != "None" ] && [ ! -z "$ATTACHMENT" ]; then
                aws ec2 detach-network-interface --attachment-id "$ATTACHMENT" --force 2>/dev/null || true
                sleep 2
            fi
            aws ec2 delete-network-interface --network-interface-id "$eni" 2>/dev/null || true
        done
    done
fi

# Step 13: Delete security groups
echo -e "\n${BLUE}Step 13: Cleaning security groups...${NC}"
if [ ! -z "$VPCS" ]; then
    for vpc in $VPCS; do
        # Get custom security groups (not default)
        SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text 2>/dev/null || echo "")
        for sg in $SGS; do
            echo "  Deleting security group: $sg"
            # Remove all ingress rules first
            aws ec2 revoke-security-group-ingress --group-id "$sg" --ip-permissions "$(aws ec2 describe-security-groups --group-ids "$sg" --query 'SecurityGroups[0].IpPermissions' 2>/dev/null || echo '[]')" 2>/dev/null || true
            # Try to delete
            aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
        done
    done
fi

# Step 14: Delete VPCs and related resources
echo -e "\n${BLUE}Step 14: Cleaning VPC resources...${NC}"
if [ ! -z "$VPCS" ]; then
    for vpc in $VPCS; do
        echo "  Processing VPC: $vpc"
        
        # Delete NAT Gateways
        NATS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc" "Name=state,Values=available" --query "NatGateways[].NatGatewayId" --output text 2>/dev/null || echo "")
        for nat in $NATS; do
            echo "    Deleting NAT Gateway: $nat"
            aws ec2 delete-nat-gateway --nat-gateway-id "$nat" 2>/dev/null || true
        done
        
        # Delete Internet Gateways
        IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" --query "InternetGateways[].InternetGatewayId" --output text 2>/dev/null || echo "")
        for igw in $IGWS; do
            echo "    Detaching and deleting IGW: $igw"
            aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc" 2>/dev/null || true
            aws ec2 delete-internet-gateway --internet-gateway-id "$igw" 2>/dev/null || true
        done
        
        # Delete subnets
        SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --query "Subnets[].SubnetId" --output text 2>/dev/null || echo "")
        for subnet in $SUBNETS; do
            echo "    Deleting subnet: $subnet"
            aws ec2 delete-subnet --subnet-id "$subnet" 2>/dev/null || true
        done
        
        # Delete route tables (except main)
        RTS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" --query "RouteTables[?Associations[0].Main!=\`true\`].RouteTableId" --output text 2>/dev/null || echo "")
        for rt in $RTS; do
            echo "    Deleting route table: $rt"
            aws ec2 delete-route-table --route-table-id "$rt" 2>/dev/null || true
        done
        
        # Finally, delete the VPC
        echo "    Deleting VPC: $vpc"
        aws ec2 delete-vpc --vpc-id "$vpc" 2>/dev/null || true
    done
fi

# Step 15: Final CloudFormation stack cleanup attempt
echo -e "\n${BLUE}Step 15: Final stack cleanup...${NC}"
if [ ! -z "$STACKS" ]; then
    for stack in $STACKS; do
        STATUS=$(aws cloudformation describe-stacks --stack-name "$stack" --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "DELETED")
        if [ "$STATUS" != "DELETED" ] && [ "$STATUS" != "DELETE_IN_PROGRESS" ]; then
            echo "  Retrying stack deletion: $stack"
            aws cloudformation delete-stack --stack-name "$stack" 2>/dev/null || true
        fi
    done
fi

# Step 16: Delete IAM roles and policies (LAST!)
echo -e "\n${BLUE}Step 16: Cleaning IAM resources (final step)...${NC}"
# Get IAM roles created by CloudFormation
IAM_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, 'LibreChat') || contains(RoleName, 'librechat')].RoleName" --output text 2>/dev/null || echo "")
if [ ! -z "$IAM_ROLES" ]; then
    for role in $IAM_ROLES; do
        echo "  Processing IAM role: $role"
        
        # Detach managed policies
        POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null || echo "")
        for policy in $POLICIES; do
            aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" 2>/dev/null || true
        done
        
        # Delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies --role-name "$role" --query "PolicyNames" --output text 2>/dev/null || echo "")
        for policy in $INLINE_POLICIES; do
            aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
        done
        
        # Delete the role
        aws iam delete-role --role-name "$role" 2>/dev/null || true
    done
fi

# Delete customer managed policies
IAM_POLICIES=$(aws iam list-policies --scope Local --query "Policies[?contains(PolicyName, 'LibreChat') || contains(PolicyName, 'librechat')].PolicyArn" --output text 2>/dev/null || echo "")
if [ ! -z "$IAM_POLICIES" ]; then
    for policy in $IAM_POLICIES; do
        echo "  Deleting IAM policy: $policy"
        aws iam delete-policy --policy-arn "$policy" 2>/dev/null || true
    done
fi

# Final summary
echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                   CLEANUP COMPLETE                        ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo
echo "All LibreChat resources have been cleaned up!"
echo "Some resources may still be deleting in the background."
echo
echo "To verify cleanup:"
echo "  aws cloudformation list-stacks --stack-status-filter DELETE_IN_PROGRESS"
echo "  aws ec2 describe-vpcs --filters 'Name=tag:aws:cloudformation:stack-name,Values=LibreChat*'"
echo