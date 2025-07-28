#!/bin/bash
# cleanup.sh - Comprehensive cleanup script for LibreChat CDK resources
# This script consolidates all cleanup functionality into a single tool
# Compatible with AWS CloudShell and local environments

set -e

# Script version
VERSION="2.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Default values
MODE="standard"
STACK_NAME="LibreChatStack-development"
ENVIRONMENT="development"
FORCE=false
DRY_RUN=false
REGIONS=""
ALL_REGIONS=false
CLEANUP_CDK_BOOTSTRAP=false
VERBOSE=false

# Function to display usage
usage() {
    echo -e "${BLUE}LibreChat CDK Cleanup Script v${VERSION}${NC}"
    echo -e "${CYAN}Comprehensive cleanup tool for all LibreChat resources${NC}"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -m, --mode <mode>         Cleanup mode: standard|deep|nuclear|rollback-fix (default: standard)"
    echo "  -s, --stack-name <name>   CloudFormation stack name (default: LibreChatStack-development)"
    echo "  -e, --environment <env>   Environment: development|staging|production (default: development)"
    echo "  -r, --regions <regions>   Comma-separated list of regions to clean (default: current region)"
    echo "  -a, --all-regions         Clean resources in all regions"
    echo "  -b, --bootstrap           Also clean CDK bootstrap stacks"
    echo "  -f, --force               Skip confirmation prompts"
    echo "  -d, --dry-run             Show what would be deleted without deleting"
    echo "  -v, --verbose             Enable verbose output"
    echo "  -h, --help                Display this help message"
    echo
    echo "Modes:"
    echo "  standard      - Normal cleanup of stack resources"
    echo "  deep          - Thorough cleanup including orphaned resources"
    echo "  nuclear       - Delete ALL LibreChat resources (use with caution!)"
    echo "  rollback-fix  - Fix stacks stuck in UPDATE_ROLLBACK_FAILED state"
    echo
    echo "Examples:"
    echo "  $0                                    # Standard cleanup of default stack"
    echo "  $0 -m deep -s MyStack                 # Deep cleanup of specific stack"
    echo "  $0 -m nuclear -a -f                   # Nuclear cleanup in all regions (dangerous!)"
    echo "  $0 -m rollback-fix -s FailedStack     # Fix rollback-failed stack"
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--mode)
            MODE="$2"
            shift 2
            ;;
        -s|--stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--regions)
            REGIONS="$2"
            shift 2
            ;;
        -a|--all-regions)
            ALL_REGIONS=true
            shift
            ;;
        -b|--bootstrap)
            CLEANUP_CDK_BOOTSTRAP=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Validate mode
if [[ ! "$MODE" =~ ^(standard|deep|nuclear|rollback-fix)$ ]]; then
    echo -e "${RED}Invalid mode: $MODE${NC}"
    usage
fi

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗ $1${NC}"
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}[$(date +'%Y-%m-%d %H:%M:%S')] → $1${NC}"
    fi
}

# Function to check if running in CloudShell
is_cloudshell() {
    [ -n "$AWS_EXECUTION_ENV" ] && [[ "$AWS_EXECUTION_ENV" == "CloudShell" ]]
}

# Function to get current region
get_current_region() {
    aws configure get region 2>/dev/null || echo "us-east-1"
}

# Function to get all regions
get_all_regions() {
    aws ec2 describe-regions --query 'Regions[].RegionName' --output text 2>/dev/null || echo "us-east-1"
}

# Function to check if resource exists
resource_exists() {
    local check_command="$1"
    eval "$check_command" >/dev/null 2>&1
}

# Function to execute or simulate command
execute_command() {
    local command="$1"
    local description="$2"
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${MAGENTA}[DRY-RUN] Would execute: $description${NC}"
        [ "$VERBOSE" = true ] && echo -e "${CYAN}Command: $command${NC}"
        return 0
    else
        log_verbose "Executing: $command"
        eval "$command" 2>&1 | while read line; do
            [ "$VERBOSE" = true ] && echo "  $line"
        done
        return ${PIPESTATUS[0]}
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local check_command="$1"
    local resource_name="$2"
    local max_attempts=30
    local attempt=0
    
    [ "$DRY_RUN" = true ] && return 0
    
    log_verbose "Waiting for $resource_name to be deleted..."
    while [ $attempt -lt $max_attempts ]; do
        if ! eval "$check_command" >/dev/null 2>&1; then
            log_success "$resource_name deleted"
            return 0
        fi
        echo -n "."
        sleep 10
        attempt=$((attempt + 1))
    done
    log_warning "$resource_name deletion timeout"
    return 1
}

# Function to handle UPDATE_ROLLBACK_FAILED state
fix_rollback_failed() {
    local stack_name="$1"
    
    log "Checking stack status..."
    local stack_status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$stack_status" != "UPDATE_ROLLBACK_FAILED" ]; then
        log "Stack is not in UPDATE_ROLLBACK_FAILED state (current: $stack_status)"
        return 0
    fi
    
    log_warning "Stack is in UPDATE_ROLLBACK_FAILED state. Attempting to fix..."
    
    # List failed resources
    log "Failed resources:"
    aws cloudformation list-stack-resources --stack-name "$stack_name" \
        --query 'StackResourceSummaries[?ResourceStatus==`UPDATE_FAILED`].[LogicalResourceId,ResourceType,ResourceStatusReason]' \
        --output table 2>/dev/null || true
    
    # Try to continue rollback
    execute_command "aws cloudformation continue-update-rollback --stack-name \"$stack_name\"" \
        "Continue rollback for $stack_name"
    
    # Wait for rollback
    if [ "$DRY_RUN" = false ]; then
        log "Waiting for rollback to complete..."
        aws cloudformation wait stack-rollback-complete --stack-name "$stack_name" 2>/dev/null || true
    fi
}

# Function to scale down ECS services
scale_down_ecs_services() {
    local cluster_arn="$1"
    
    [ -z "$cluster_arn" ] && return 0
    
    log "Scaling down ECS services..."
    local services=$(aws ecs list-services --cluster "$cluster_arn" --query 'serviceArns[]' --output text 2>/dev/null || echo "")
    
    for service in $services; do
        if [ ! -z "$service" ]; then
            execute_command "aws ecs update-service --cluster \"$cluster_arn\" --service \"$service\" --desired-count 0 >/dev/null" \
                "Scale down service: ${service##*/}"
            
            execute_command "aws ecs delete-service --cluster \"$cluster_arn\" --service \"$service\" --force >/dev/null" \
                "Delete service: ${service##*/}"
        fi
    done
}

# Function to empty S3 bucket
empty_s3_bucket() {
    local bucket="$1"
    
    [ -z "$bucket" ] && return 0
    
    log "Emptying S3 bucket: $bucket"
    
    # Delete all objects
    execute_command "aws s3 rm s3://$bucket --recursive >/dev/null" \
        "Delete all objects from $bucket"
    
    # Delete all versions
    if [ "$DRY_RUN" = false ]; then
        aws s3api list-object-versions --bucket "$bucket" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null | \
        while read key version; do
            if [ ! -z "$key" ] && [ "$key" != "None" ]; then
                execute_command "aws s3api delete-object --bucket \"$bucket\" --key \"$key\" --version-id \"$version\" >/dev/null" \
                    "Delete version: $key"
            fi
        done
        
        # Delete all delete markers
        aws s3api list-object-versions --bucket "$bucket" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null | \
        while read key version; do
            if [ ! -z "$key" ] && [ "$key" != "None" ]; then
                execute_command "aws s3api delete-object --bucket \"$bucket\" --key \"$key\" --version-id \"$version\" >/dev/null" \
                    "Delete marker: $key"
            fi
        done
    fi
}

# Function to delete VPC and its dependencies
delete_vpc_resources() {
    local vpc_id="$1"
    
    [ -z "$vpc_id" ] && return 0
    
    log "Cleaning up VPC resources for: $vpc_id"
    
    # Delete NAT Gateways
    local nat_gateways=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available" --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null || echo "")
    for nat in $nat_gateways; do
        execute_command "aws ec2 delete-nat-gateway --nat-gateway-id \"$nat\" >/dev/null" \
            "Delete NAT Gateway: $nat"
    done
    
    # Release Elastic IPs
    local eips=$(aws ec2 describe-addresses --filters "Name=tag:aws:cloudformation:stack-name,Values=$STACK_NAME" --query 'Addresses[].AllocationId' --output text 2>/dev/null || echo "")
    for eip in $eips; do
        execute_command "aws ec2 release-address --allocation-id \"$eip\" >/dev/null" \
            "Release Elastic IP: $eip"
    done
    
    # Delete VPC Endpoints
    local endpoints=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$vpc_id" --query 'VpcEndpoints[].VpcEndpointId' --output text 2>/dev/null || echo "")
    for endpoint in $endpoints; do
        execute_command "aws ec2 delete-vpc-endpoints --vpc-endpoint-ids \"$endpoint\" >/dev/null" \
            "Delete VPC Endpoint: $endpoint"
    done
    
    # Delete Internet Gateways
    local igws=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null || echo "")
    for igw in $igws; do
        execute_command "aws ec2 detach-internet-gateway --internet-gateway-id \"$igw\" --vpc-id \"$vpc_id\" >/dev/null" \
            "Detach IGW: $igw"
        execute_command "aws ec2 delete-internet-gateway --internet-gateway-id \"$igw\" >/dev/null" \
            "Delete IGW: $igw"
    done
    
    # Delete Subnets
    local subnets=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[].SubnetId' --output text 2>/dev/null || echo "")
    for subnet in $subnets; do
        execute_command "aws ec2 delete-subnet --subnet-id \"$subnet\" >/dev/null" \
            "Delete Subnet: $subnet"
    done
    
    # Delete Route Tables
    local route_tables=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text 2>/dev/null || echo "")
    for rt in $route_tables; do
        execute_command "aws ec2 delete-route-table --route-table-id \"$rt\" >/dev/null" \
            "Delete Route Table: $rt"
    done
    
    # Delete Security Groups
    local security_groups=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || echo "")
    for sg in $security_groups; do
        # Remove all rules first
        execute_command "aws ec2 revoke-security-group-ingress --group-id \"$sg\" --ip-permissions \"\$(aws ec2 describe-security-groups --group-ids \"$sg\" --query 'SecurityGroups[0].IpPermissions' 2>/dev/null || echo '[]')\" >/dev/null 2>&1" \
            "Revoke ingress rules for: $sg"
        execute_command "aws ec2 revoke-security-group-egress --group-id \"$sg\" --ip-permissions \"\$(aws ec2 describe-security-groups --group-ids \"$sg\" --query 'SecurityGroups[0].IpPermissionsEgress' 2>/dev/null || echo '[]')\" >/dev/null 2>&1" \
            "Revoke egress rules for: $sg"
        execute_command "aws ec2 delete-security-group --group-id \"$sg\" >/dev/null 2>&1" \
            "Delete Security Group: $sg"
    done
    
    # Finally, delete the VPC
    execute_command "aws ec2 delete-vpc --vpc-id \"$vpc_id\" >/dev/null" \
        "Delete VPC: $vpc_id"
}

# Function to delete IAM resources
delete_iam_resources() {
    local role_prefix="$1"
    
    log "Cleaning up IAM resources..."
    
    # Get all IAM roles
    local roles=$(aws iam list-roles --query "Roles[?contains(RoleName, '$role_prefix')].RoleName" --output text 2>/dev/null || echo "")
    
    for role in $roles; do
        if [ ! -z "$role" ]; then
            log_verbose "Processing IAM role: $role"
            
            # Detach managed policies
            local policies=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
            for policy in $policies; do
                if [ ! -z "$policy" ]; then
                    execute_command "aws iam detach-role-policy --role-name \"$role\" --policy-arn \"$policy\" >/dev/null" \
                        "Detach policy from $role"
                fi
            done
            
            # Delete inline policies
            local inline_policies=$(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
            for policy in $inline_policies; do
                if [ ! -z "$policy" ]; then
                    execute_command "aws iam delete-role-policy --role-name \"$role\" --policy-name \"$policy\" >/dev/null" \
                        "Delete inline policy from $role"
                fi
            done
            
            # Delete instance profiles
            local instance_profiles=$(aws iam list-instance-profiles-for-role --role-name "$role" --query 'InstanceProfiles[].InstanceProfileName' --output text 2>/dev/null || echo "")
            for profile in $instance_profiles; do
                if [ ! -z "$profile" ]; then
                    execute_command "aws iam remove-role-from-instance-profile --instance-profile-name \"$profile\" --role-name \"$role\" >/dev/null" \
                        "Remove role from instance profile"
                    execute_command "aws iam delete-instance-profile --instance-profile-name \"$profile\" >/dev/null" \
                        "Delete instance profile: $profile"
                fi
            done
            
            # Delete the role
            execute_command "aws iam delete-role --role-name \"$role\" >/dev/null" \
                "Delete IAM role: $role"
        fi
    done
}

# Main cleanup function
cleanup_region() {
    local region="$1"
    
    export AWS_DEFAULT_REGION="$region"
    log "========== Cleaning region: $region =========="
    
    # Check if stack exists
    local stack_exists=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" >/dev/null 2>&1 && echo "true" || echo "false")
    
    if [ "$stack_exists" = "true" ] || [ "$MODE" = "nuclear" ]; then
        
        # Handle rollback-fix mode
        if [ "$MODE" = "rollback-fix" ]; then
            fix_rollback_failed "$STACK_NAME"
            return
        fi
        
        # Get stack resources before deletion
        local stack_resources=""
        if [ "$stack_exists" = "true" ]; then
            stack_resources=$(aws cloudformation list-stack-resources --stack-name "$STACK_NAME" --query 'StackResourceSummaries[].[PhysicalResourceId,ResourceType]' --output text 2>/dev/null || echo "")
        fi
        
        # Phase 1: Scale down services
        log "Phase 1: Scaling down services..."
        
        # Scale down ECS services
        local ecs_clusters=$(aws ecs list-clusters --query "clusterArns[?contains(@, '$STACK_NAME')]" --output text 2>/dev/null || echo "")
        for cluster in $ecs_clusters; do
            scale_down_ecs_services "$cluster"
        done
        
        # Phase 2: Empty S3 buckets
        log "Phase 2: Emptying S3 buckets..."
        local bucket_prefix=$(echo "$STACK_NAME" | tr '[:upper:]' '[:lower:]')
        local buckets=$(aws s3api list-buckets --query "Buckets[?contains(Name, '$bucket_prefix')].Name" --output text 2>/dev/null || echo "")
        
        for bucket in $buckets; do
            empty_s3_bucket "$bucket"
        done
        
        # Phase 3: Delete Load Balancers and Target Groups
        log "Phase 3: Deleting load balancers..."
        local load_balancers=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, '$STACK_NAME')].LoadBalancerArn" --output text 2>/dev/null || echo "")
        
        for lb in $load_balancers; do
            execute_command "aws elbv2 delete-load-balancer --load-balancer-arn \"$lb\" >/dev/null" \
                "Delete load balancer: ${lb##*/}"
        done
        
        local target_groups=$(aws elbv2 describe-target-groups --query "TargetGroups[?contains(TargetGroupName, '$STACK_NAME')].TargetGroupArn" --output text 2>/dev/null || echo "")
        
        for tg in $target_groups; do
            execute_command "aws elbv2 delete-target-group --target-group-arn \"$tg\" >/dev/null" \
                "Delete target group: ${tg##*/}"
        done
        
        # Phase 4: Delete CloudFormation stack
        if [ "$stack_exists" = "true" ]; then
            log "Phase 4: Deleting CloudFormation stack..."
            execute_command "aws cloudformation delete-stack --stack-name \"$STACK_NAME\"" \
                "Delete stack: $STACK_NAME"
            
            if [ "$DRY_RUN" = false ]; then
                log "Waiting for stack deletion (this may take 10-20 minutes)..."
                local wait_time=0
                while [ $wait_time -lt 1200 ]; do
                    local status=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DELETED")
                    
                    case $status in
                        DELETE_IN_PROGRESS)
                            echo -n "."
                            sleep 30
                            wait_time=$((wait_time + 30))
                            ;;
                        DELETE_COMPLETE|DELETED)
                            log_success "Stack deleted successfully!"
                            break
                            ;;
                        DELETE_FAILED)
                            log_error "Stack deletion failed!"
                            break
                            ;;
                        *)
                            log_warning "Unexpected status: $status"
                            break
                            ;;
                    esac
                done
            fi
        fi
        
        # Phase 5: Clean up orphaned resources (for deep/nuclear modes)
        if [ "$MODE" = "deep" ] || [ "$MODE" = "nuclear" ]; then
            log "Phase 5: Cleaning up orphaned resources..."
            
            # Delete ECS clusters
            for cluster in $ecs_clusters; do
                execute_command "aws ecs delete-cluster --cluster \"$cluster\" >/dev/null" \
                    "Delete ECS cluster: ${cluster##*/}"
            done
            
            # Delete Lambda functions
            local lambda_functions=$(aws lambda list-functions --query "Functions[?contains(FunctionName, '$STACK_NAME')].FunctionName" --output text 2>/dev/null || echo "")
            for func in $lambda_functions; do
                execute_command "aws lambda delete-function --function-name \"$func\" >/dev/null" \
                    "Delete Lambda function: $func"
            done
            
            # Delete CloudWatch log groups
            local log_groups=$(aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/$STACK_NAME" --query 'logGroups[].logGroupName' --output text 2>/dev/null || echo "")
            log_groups="$log_groups $(aws logs describe-log-groups --log-group-name-prefix "/ecs/$STACK_NAME" --query 'logGroups[].logGroupName' --output text 2>/dev/null || echo "")"
            
            for lg in $log_groups; do
                if [ ! -z "$lg" ] && [ "$lg" != " " ]; then
                    execute_command "aws logs delete-log-group --log-group-name \"$lg\" >/dev/null" \
                        "Delete log group: $lg"
                fi
            done
            
            # Delete Secrets Manager secrets
            local secrets=$(aws secretsmanager list-secrets --query "SecretList[?contains(Name, '$STACK_NAME')].Name" --output text 2>/dev/null || echo "")
            for secret in $secrets; do
                execute_command "aws secretsmanager delete-secret --secret-id \"$secret\" --force-delete-without-recovery >/dev/null" \
                    "Delete secret: $secret"
            done
            
            # Delete S3 buckets
            for bucket in $buckets; do
                execute_command "aws s3api delete-bucket --bucket \"$bucket\" >/dev/null" \
                    "Delete S3 bucket: $bucket"
            done
            
            # Delete ECR repositories
            local ecr_repos=$(aws ecr describe-repositories --query "repositories[?contains(repositoryName, 'librechat')].repositoryName" --output text 2>/dev/null || echo "")
            for repo in $ecr_repos; do
                execute_command "aws ecr delete-repository --repository-name \"$repo\" --force >/dev/null" \
                    "Delete ECR repository: $repo"
            done
            
            # Delete VPC resources
            local vpcs=$(aws ec2 describe-vpcs --filters "Name=tag:aws:cloudformation:stack-name,Values=$STACK_NAME*" --query 'Vpcs[].VpcId' --output text 2>/dev/null || echo "")
            for vpc in $vpcs; do
                delete_vpc_resources "$vpc"
            done
            
            # Delete Network Interfaces
            local enis=$(aws ec2 describe-network-interfaces --filters "Name=tag:aws:cloudformation:stack-name,Values=$STACK_NAME" --query 'NetworkInterfaces[].NetworkInterfaceId' --output text 2>/dev/null || echo "")
            for eni in $enis; do
                execute_command "aws ec2 delete-network-interface --network-interface-id \"$eni\" >/dev/null" \
                    "Delete ENI: $eni"
            done
            
            # Delete IAM resources (last)
            delete_iam_resources "$STACK_NAME"
        fi
        
        # Phase 6: Nuclear mode - delete everything LibreChat related
        if [ "$MODE" = "nuclear" ]; then
            log "Phase 6: Nuclear cleanup - removing ALL LibreChat resources..."
            
            # Delete all LibreChat-related EC2 instances
            local instances=$(aws ec2 describe-instances --filters "Name=tag:Application,Values=LibreChat" "Name=instance-state-name,Values=running,stopped" --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || echo "")
            for instance in $instances; do
                execute_command "aws ec2 terminate-instances --instance-ids \"$instance\" >/dev/null" \
                    "Terminate EC2 instance: $instance"
            done
            
            # Delete all LibreChat-related RDS instances
            local rds_instances=$(aws rds describe-db-instances --query "DBInstances[?contains(DBInstanceIdentifier, 'librechat')].DBInstanceIdentifier" --output text 2>/dev/null || echo "")
            for db in $rds_instances; do
                execute_command "aws rds delete-db-instance --db-instance-identifier \"$db\" --skip-final-snapshot --delete-automated-backups >/dev/null" \
                    "Delete RDS instance: $db"
            done
            
            # Delete all LibreChat-related RDS clusters
            local rds_clusters=$(aws rds describe-db-clusters --query "DBClusters[?contains(DBClusterIdentifier, 'librechat')].DBClusterIdentifier" --output text 2>/dev/null || echo "")
            for cluster in $rds_clusters; do
                execute_command "aws rds delete-db-cluster --db-cluster-identifier \"$cluster\" --skip-final-snapshot >/dev/null" \
                    "Delete RDS cluster: $cluster"
            done
            
            # Delete all LibreChat-related DocumentDB clusters
            local docdb_clusters=$(aws docdb describe-db-clusters --query "DBClusters[?contains(DBClusterIdentifier, 'librechat')].DBClusterIdentifier" --output text 2>/dev/null || echo "")
            for cluster in $docdb_clusters; do
                execute_command "aws docdb delete-db-cluster --db-cluster-identifier \"$cluster\" --skip-final-snapshot >/dev/null" \
                    "Delete DocumentDB cluster: $cluster"
            done
            
            # Delete all LibreChat-related EFS file systems
            local efs_systems=$(aws efs describe-file-systems --query "FileSystems[?contains(Name, 'librechat') || contains(Name, 'LibreChat')].FileSystemId" --output text 2>/dev/null || echo "")
            for fs in $efs_systems; do
                # Delete mount targets first
                local mount_targets=$(aws efs describe-mount-targets --file-system-id "$fs" --query 'MountTargets[].MountTargetId' --output text 2>/dev/null || echo "")
                for mt in $mount_targets; do
                    execute_command "aws efs delete-mount-target --mount-target-id \"$mt\" >/dev/null" \
                        "Delete EFS mount target: $mt"
                done
                sleep 5
                execute_command "aws efs delete-file-system --file-system-id \"$fs\" >/dev/null" \
                    "Delete EFS file system: $fs"
            done
            
            # Clean up all LibreChat IAM resources
            delete_iam_resources "LibreChat"
            delete_iam_resources "librechat"
        fi
        
        # Clean up CDK bootstrap stacks if requested
        if [ "$CLEANUP_CDK_BOOTSTRAP" = true ]; then
            log "Cleaning up CDK bootstrap stacks..."
            local cdk_stacks=$(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query "StackSummaries[?contains(StackName, 'CDKToolkit')].StackName" --output text 2>/dev/null || echo "")
            for stack in $cdk_stacks; do
                # Empty CDK bootstrap bucket
                local cdk_bucket=$(aws cloudformation describe-stack-resources --stack-name "$stack" --query "StackResources[?ResourceType=='AWS::S3::Bucket'].PhysicalResourceId" --output text 2>/dev/null || echo "")
                if [ ! -z "$cdk_bucket" ]; then
                    empty_s3_bucket "$cdk_bucket"
                fi
                
                execute_command "aws cloudformation delete-stack --stack-name \"$stack\"" \
                    "Delete CDK bootstrap stack: $stack"
            done
        fi
        
        log_success "Cleanup completed for region: $region"
    else
        log "No resources found in region: $region"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}LibreChat CDK Cleanup Script v${VERSION}${NC}"
    echo -e "${CYAN}Mode: $MODE | Stack: $STACK_NAME | Environment: $ENVIRONMENT${NC}"
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${MAGENTA}DRY RUN MODE - No resources will be deleted${NC}"
    fi
    
    echo
    
    # Determine regions to clean
    local regions_to_clean=""
    if [ "$ALL_REGIONS" = true ]; then
        regions_to_clean=$(get_all_regions)
        log "Will clean ALL regions: $regions_to_clean"
    elif [ ! -z "$REGIONS" ]; then
        regions_to_clean=$(echo "$REGIONS" | tr ',' ' ')
        log "Will clean specified regions: $regions_to_clean"
    else
        regions_to_clean=$(get_current_region)
        log "Will clean current region: $regions_to_clean"
    fi
    
    # Show warning for destructive operations
    if [ "$MODE" = "nuclear" ] && [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
        echo -e "${RED}WARNING: Nuclear mode will delete ALL LibreChat resources!${NC}"
        echo -e "${RED}This includes databases, storage, and all data!${NC}"
        echo -n "Are you sure you want to continue? (yes/no): "
        read confirmation
        if [ "$confirmation" != "yes" ]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    elif [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
        echo -n "Are you sure you want to clean up $STACK_NAME? (y/n): "
        read confirmation
        if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Check if running in CloudShell
    if is_cloudshell; then
        log "Running in AWS CloudShell environment"
    fi
    
    # Save current region
    local original_region=$(get_current_region)
    
    # Clean each region
    for region in $regions_to_clean; do
        cleanup_region "$region"
    done
    
    # Restore original region
    export AWS_DEFAULT_REGION="$original_region"
    
    echo
    log_success "All cleanup operations completed!"
    
    # Final summary
    if [ "$DRY_RUN" = false ]; then
        echo
        log "To verify cleanup, run: ./scripts/check-resources.sh"
    fi
}

# Run main function
main