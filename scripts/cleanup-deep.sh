#!/bin/bash
# cleanup-deep.sh - Deep cleanup of CDK stacks and associated resources
# Use when: Normal cleanup fails or leaves orphaned resources
# Next level: cleanup-nuclear.sh for complete AWS resource removal

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
echo -e "${RED}║                                                           ║${NC}"
echo -e "${RED}║  For COMPLETE resource cleanup, use:                      ║${NC}"
echo -e "${RED}║  ./cleanup-nuclear.sh                                     ║${NC}"
echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
echo

# Function to empty S3 bucket completely
empty_s3_bucket() {
    local bucket=$1
    echo "  Emptying S3 bucket: $bucket"
    
    # Delete all object versions
    echo "    Deleting all object versions..."
    aws s3api list-object-versions --bucket "$bucket" --output json 2>/dev/null | \
        jq -r '.Versions[]?, .DeleteMarkers[]? | "\(.Key) \(.VersionId)"' | \
        while read key version; do
            if [ ! -z "$key" ]; then
                aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version" 2>/dev/null || true
            fi
        done
    
    # Delete all current objects
    aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
}

# Function to delete resources that block stack deletion
delete_blocking_resources() {
    local stack_name=$1
    echo "  Checking for blocking resources in stack: $stack_name"
    
    # Get all resources in the stack
    RESOURCES=$(aws cloudformation list-stack-resources \
        --stack-name "$stack_name" \
        --query "StackResourceSummaries[?ResourceStatus!='DELETE_COMPLETE'].{Type:ResourceType,Id:PhysicalResourceId,Status:ResourceStatus}" \
        --output json 2>/dev/null || echo "[]")
    
    echo "$RESOURCES" | jq -r '.[] | "\(.Type)|\(.Id)|\(.Status)"' | while IFS='|' read -r resource_type physical_id status; do
        case "$resource_type" in
            "AWS::S3::Bucket")
                echo "    Found S3 bucket: $physical_id"
                empty_s3_bucket "$physical_id"
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
            "AWS::ECS::Service")
                # Extract cluster and service name
                if [[ "$physical_id" =~ arn:aws:ecs:[^:]+:[^:]+:service/([^/]+)/(.+) ]]; then
                    cluster="${BASH_REMATCH[1]}"
                    service="${BASH_REMATCH[2]}"
                    echo "    Scaling down and deleting ECS service: $service"
                    aws ecs update-service --cluster "$cluster" --service "$service" --desired-count 0 2>/dev/null || true
                    aws ecs delete-service --cluster "$cluster" --service "$service" --force 2>/dev/null || true
                fi
                ;;
            "AWS::ElasticLoadBalancingV2::LoadBalancer")
                echo "    Deleting load balancer: $physical_id"
                aws elbv2 delete-load-balancer --load-balancer-arn "$physical_id" 2>/dev/null || true
                ;;
            "AWS::RDS::DBInstance")
                echo "    Deleting RDS instance: $physical_id"
                aws rds delete-db-instance --db-instance-identifier "$physical_id" --skip-final-snapshot --delete-automated-backups 2>/dev/null || true
                ;;
            "AWS::RDS::DBCluster")
                echo "    Deleting RDS cluster: $physical_id"
                # Delete cluster members first
                MEMBERS=$(aws rds describe-db-clusters --db-cluster-identifier "$physical_id" --query "DBClusters[0].DBClusterMembers[].DBInstanceIdentifier" --output text 2>/dev/null || echo "")
                for member in $MEMBERS; do
                    aws rds delete-db-instance --db-instance-identifier "$member" --skip-final-snapshot 2>/dev/null || true
                done
                aws rds delete-db-cluster --db-cluster-identifier "$physical_id" --skip-final-snapshot 2>/dev/null || true
                ;;
            "AWS::DocDB::DBCluster")
                echo "    Deleting DocumentDB cluster: $physical_id"
                # Delete cluster members first
                MEMBERS=$(aws docdb describe-db-clusters --db-cluster-identifier "$physical_id" --query "DBClusters[0].DBClusterMembers[].DBInstanceIdentifier" --output text 2>/dev/null || echo "")
                for member in $MEMBERS; do
                    aws docdb delete-db-instance --db-instance-identifier "$member" --skip-final-snapshot 2>/dev/null || true
                done
                aws docdb delete-db-cluster --db-cluster-identifier "$physical_id" --skip-final-snapshot 2>/dev/null || true
                ;;
            "AWS::EFS::FileSystem")
                echo "    Deleting EFS file system: $physical_id"
                # Delete mount targets first
                MTS=$(aws efs describe-mount-targets --file-system-id "$physical_id" --query "MountTargets[].MountTargetId" --output text 2>/dev/null || echo "")
                for mt in $MTS; do
                    aws efs delete-mount-target --mount-target-id "$mt" 2>/dev/null || true
                done
                sleep 5
                aws efs delete-file-system --file-system-id "$physical_id" 2>/dev/null || true
                ;;
            "AWS::SecretsManager::Secret")
                echo "    Deleting secret: $physical_id"
                aws secretsmanager delete-secret --secret-id "$physical_id" --force-delete-without-recovery 2>/dev/null || true
                ;;
        esac
    done
}

# Function to delete a stack with retries
delete_stack_with_retry() {
    local stack_name=$1
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "  Attempt $attempt to delete stack: $stack_name"
        
        # First, try to delete blocking resources
        delete_blocking_resources "$stack_name"
        
        # Try to delete the stack
        aws cloudformation delete-stack --stack-name "$stack_name" 2>/dev/null || true
        
        # Wait a bit
        sleep 10
        
        # Check if stack is deleted or deleting
        STATUS=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "DELETED")
        
        if [ "$STATUS" = "DELETE_IN_PROGRESS" ] || [ "$STATUS" = "DELETED" ]; then
            echo "  Stack deletion initiated successfully"
            return 0
        fi
        
        ((attempt++))
    done
    
    echo "  Failed to delete stack after $max_attempts attempts"
    return 1
}

# Get ALL stacks
echo -e "${BLUE}Finding ALL CloudFormation stacks...${NC}"
ALL_STACKS=$(aws cloudformation list-stacks \
    --query "StackSummaries[?StackStatus!='DELETE_COMPLETE'].{Name:StackName,Status:StackStatus}" \
    --output json)

# Filter for LibreChat and CDK stacks
LIBRECHAT_STACKS=$(echo "$ALL_STACKS" | jq -r '.[] | select(.Name | contains("LibreChat") or contains("librechat")) | "\(.Name)|\(.Status)"')
CDK_STACKS=$(echo "$ALL_STACKS" | jq -r '.[] | select(.Name | contains("CDKToolkit")) | "\(.Name)|\(.Status)"')

# Count stacks
LIBRECHAT_COUNT=$(echo -n "$LIBRECHAT_STACKS" | grep -c '^' || echo 0)
CDK_COUNT=$(echo -n "$CDK_STACKS" | grep -c '^' || echo 0)
TOTAL_COUNT=$((LIBRECHAT_COUNT + CDK_COUNT))

if [ "$TOTAL_COUNT" -eq 0 ]; then
    echo -e "\n${GREEN}No CDK or LibreChat stacks found!${NC}"
    
    # Check for orphaned resources anyway
    echo -e "\n${BLUE}Checking for orphaned resources...${NC}"
    
    # S3 buckets
    S3_BUCKETS=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'librechat') || contains(Name, 'cdk-')].Name" --output text 2>/dev/null || echo "")
    if [ ! -z "$S3_BUCKETS" ]; then
        echo -e "${YELLOW}Found orphaned S3 buckets${NC}"
        for bucket in $S3_BUCKETS; do
            empty_s3_bucket "$bucket"
            aws s3api delete-bucket --bucket "$bucket" 2>/dev/null || true
        done
    fi
    
    exit 0
fi

echo -e "\n${YELLOW}Found $LIBRECHAT_COUNT LibreChat stack(s)${NC}"
echo -e "${YELLOW}Found $CDK_COUNT CDK Bootstrap stack(s)${NC}"
echo -e "${RED}Total stacks to delete: $TOTAL_COUNT${NC}"

# Show stacks
if [ ! -z "$LIBRECHAT_STACKS" ]; then
    echo -e "\nLibreChat stacks:"
    echo "$LIBRECHAT_STACKS" | while IFS='|' read -r name status; do
        echo "  - $name ($status)"
    done
fi

if [ ! -z "$CDK_STACKS" ]; then
    echo -e "\nCDK Bootstrap stacks:"
    echo "$CDK_STACKS" | while IFS='|' read -r name status; do
        echo "  - $name ($status)"
    done
fi

echo
read -p "Type 'DELETE ALL' to confirm deletion of ALL stacks: " CONFIRM

if [ "$CONFIRM" != "DELETE ALL" ]; then
    echo -e "${GREEN}Cleanup cancelled${NC}"
    exit 0
fi

# Delete LibreChat stacks first
if [ ! -z "$LIBRECHAT_STACKS" ]; then
    echo -e "\n${BLUE}Deleting LibreChat stacks...${NC}"
    echo "$LIBRECHAT_STACKS" | while IFS='|' read -r stack_name stack_status; do
        if [ ! -z "$stack_name" ]; then
            delete_stack_with_retry "$stack_name"
        fi
    done
fi

# Wait for LibreChat stacks to start deleting
echo -e "\n${BLUE}Waiting for LibreChat stack deletions to process...${NC}"
sleep 20

# Delete CDK bootstrap stacks
if [ ! -z "$CDK_STACKS" ]; then
    echo -e "\n${BLUE}Deleting CDK bootstrap stacks...${NC}"
    echo "$CDK_STACKS" | while IFS='|' read -r stack_name stack_status; do
        if [ ! -z "$stack_name" ]; then
            # CDK bootstrap bucket needs special handling
            CDK_BUCKET=$(aws cloudformation describe-stack-resources \
                --stack-name "$stack_name" \
                --query "StackResources[?ResourceType=='AWS::S3::Bucket'].PhysicalResourceId" \
                --output text 2>/dev/null || echo "")
            
            if [ ! -z "$CDK_BUCKET" ]; then
                empty_s3_bucket "$CDK_BUCKET"
            fi
            
            delete_stack_with_retry "$stack_name"
        fi
    done
fi

# Final cleanup of any remaining resources
echo -e "\n${BLUE}Final cleanup of orphaned resources...${NC}"

# VPCs with LibreChat tags
VPCS=$(aws ec2 describe-vpcs --filters "Name=tag:aws:cloudformation:stack-name,Values=LibreChat*" --query "Vpcs[].VpcId" --output text 2>/dev/null || echo "")
if [ ! -z "$VPCS" ]; then
    echo "Found orphaned VPCs, cleaning up..."
    for vpc in $VPCS; do
        # Delete all dependent resources first
        # ... (network interfaces, security groups, etc.)
        aws ec2 delete-vpc --vpc-id "$vpc" 2>/dev/null || true
    done
fi

# ECS clusters
ECS_CLUSTERS=$(aws ecs list-clusters --query "clusterArns[?contains(@, 'LibreChat') || contains(@, 'librechat')]" --output text 2>/dev/null || echo "")
if [ ! -z "$ECS_CLUSTERS" ]; then
    echo "Found orphaned ECS clusters, cleaning up..."
    for cluster in $ECS_CLUSTERS; do
        CLUSTER_NAME=$(echo $cluster | rev | cut -d'/' -f1 | rev)
        aws ecs delete-cluster --cluster "$CLUSTER_NAME" 2>/dev/null || true
    done
fi

echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                   CLEANUP COMPLETE                        ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo
echo "Note: Some resources may take several minutes to fully delete."
echo "Check AWS CloudFormation console for status."
echo
echo "For complete resource cleanup including IAM roles and all AWS resources,"
echo "run: ./cleanup-nuclear.sh"