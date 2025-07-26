#!/bin/bash
# check-resources.sh - Check for LibreChat CDK resources in AWS

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}LibreChat CDK Resource Check${NC}"
echo "============================"

# Get environment from .env or default
if [ -f .env ]; then
    source .env
fi
ENVIRONMENT=${DEPLOYMENT_ENV:-development}

echo -e "${YELLOW}Environment: ${ENVIRONMENT}${NC}"
echo

# Function to check resources
check_resource() {
    local resource_type="$1"
    local count="$2"
    
    if [ "$count" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Found $count $resource_type${NC}"
    else
        echo -e "${GREEN}✅ No $resource_type found${NC}"
    fi
}

# Check CloudFormation stacks
echo -e "\n${BLUE}Checking CloudFormation Stacks...${NC}"
STACKS=$(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE DELETE_FAILED --query "StackSummaries[?contains(StackName, 'LibreChat')].StackName" --output text 2>/dev/null || echo "")
if [ ! -z "$STACKS" ]; then
    echo -e "${YELLOW}Found stacks:${NC}"
    for stack in $STACKS; do
        echo "  - $stack"
    done
else
    echo -e "${GREEN}✅ No LibreChat stacks found${NC}"
fi

# Check ECS resources
echo -e "\n${BLUE}Checking ECS Resources...${NC}"
ECS_CLUSTERS=$(aws ecs list-clusters --query "clusterArns[?contains(@, 'LibreChat') || contains(@, '$ENVIRONMENT')]" --output text 2>/dev/null || echo "")
CLUSTER_COUNT=$(echo "$ECS_CLUSTERS" | wc -w)
check_resource "ECS clusters" $CLUSTER_COUNT
if [ ! -z "$ECS_CLUSTERS" ]; then
    for cluster in $ECS_CLUSTERS; do
        CLUSTER_NAME=$(echo $cluster | rev | cut -d'/' -f1 | rev)
        echo "  - Cluster: $CLUSTER_NAME"
        
        # Check services in cluster
        SERVICES=$(aws ecs list-services --cluster "$cluster" --query 'serviceArns[]' --output text 2>/dev/null || echo "")
        SERVICE_COUNT=$(echo "$SERVICES" | wc -w)
        if [ "$SERVICE_COUNT" -gt 0 ]; then
            echo "    - $SERVICE_COUNT services running"
        fi
    done
fi

# Check ECS Task Definitions
TASK_DEFS=$(aws ecs list-task-definitions --family-prefix "LibreChat" --status ACTIVE --query 'taskDefinitionArns[]' --output text 2>/dev/null || echo "")
TASK_DEF_COUNT=$(echo "$TASK_DEFS" | wc -w)
check_resource "ECS task definitions" $TASK_DEF_COUNT

# Check EC2 instances
echo -e "\n${BLUE}Checking EC2 Instances...${NC}"
INSTANCES=$(aws ec2 describe-instances --filters "Name=tag:Stack,Values=LibreChat*" "Name=instance-state-name,Values=running,stopped" --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || echo "")
INSTANCE_COUNT=$(echo "$INSTANCES" | wc -w)
check_resource "EC2 instances" $INSTANCE_COUNT

# Check RDS databases
echo -e "\n${BLUE}Checking RDS Databases...${NC}"
RDS_INSTANCES=$(aws rds describe-db-instances --query "DBInstances[?contains(DBInstanceIdentifier, 'librechat')].DBInstanceIdentifier" --output text 2>/dev/null || echo "")
RDS_COUNT=$(echo "$RDS_INSTANCES" | wc -w)
check_resource "RDS instances" $RDS_COUNT

RDS_CLUSTERS=$(aws rds describe-db-clusters --query "DBClusters[?contains(DBClusterIdentifier, 'librechat')].DBClusterIdentifier" --output text 2>/dev/null || echo "")
CLUSTER_COUNT=$(echo "$RDS_CLUSTERS" | wc -w)
check_resource "RDS clusters" $CLUSTER_COUNT

# Check S3 buckets
echo -e "\n${BLUE}Checking S3 Buckets...${NC}"
S3_BUCKETS=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'librechat')].Name" --output text 2>/dev/null || echo "")
BUCKET_COUNT=$(echo "$S3_BUCKETS" | wc -w)
check_resource "S3 buckets" $BUCKET_COUNT

# Check ECR repositories
echo -e "\n${BLUE}Checking ECR Repositories...${NC}"
ECR_REPOS=$(aws ecr describe-repositories --query "repositories[?contains(repositoryName, 'librechat')].repositoryName" --output text 2>/dev/null || echo "")
REPO_COUNT=$(echo "$ECR_REPOS" | wc -w)
check_resource "ECR repositories" $REPO_COUNT

# Check IAM roles
echo -e "\n${BLUE}Checking IAM Roles...${NC}"
IAM_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, 'LibreChat')].RoleName" --output text 2>/dev/null || echo "")
ROLE_COUNT=$(echo "$IAM_ROLES" | wc -w)
check_resource "IAM roles" $ROLE_COUNT

# Check Security Groups
echo -e "\n${BLUE}Checking Security Groups...${NC}"
SECURITY_GROUPS=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=*LibreChat*" --query 'SecurityGroups[].GroupId' --output text 2>/dev/null || echo "")
SG_COUNT=$(echo "$SECURITY_GROUPS" | wc -w)
check_resource "Security groups" $SG_COUNT

# Check CloudWatch Log Groups
echo -e "\n${BLUE}Checking CloudWatch Log Groups...${NC}"
LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/LibreChat" --query 'logGroups[].logGroupName' --output text 2>/dev/null || echo "")
LOG_COUNT=$(echo "$LOG_GROUPS" | wc -w)
check_resource "CloudWatch log groups" $LOG_COUNT

# Summary
echo -e "\n${BLUE}Summary${NC}"
echo "======="
TOTAL_RESOURCES=$((CLUSTER_COUNT + TASK_DEF_COUNT + INSTANCE_COUNT + RDS_COUNT + BUCKET_COUNT + REPO_COUNT + ROLE_COUNT + SG_COUNT + LOG_COUNT))

if [ "$TOTAL_RESOURCES" -eq 0 ]; then
    echo -e "${GREEN}✅ No LibreChat resources found. Environment is clean!${NC}"
else
    echo -e "${YELLOW}⚠️  Found $TOTAL_RESOURCES LibreChat-related resources${NC}"
    echo
    echo "To clean up all resources, run:"
    echo "  ./scripts/cleanup.sh"
fi