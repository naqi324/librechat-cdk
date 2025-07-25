#!/bin/bash
# deploy-interactive.sh - Interactive LibreChat CDK deployment wizard

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           LibreChat CDK Deployment Wizard                 ║"
echo "║                                                           ║"
echo "║  Deploy LibreChat on AWS with enterprise features         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    local missing_deps=false
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        echo -e "${RED}✗ Node.js is not installed${NC}"
        missing_deps=true
    else
        echo -e "${GREEN}✓ Node.js $(node --version)${NC}"
    fi
    
    # Check npm
    if ! command -v npm &> /dev/null; then
        echo -e "${RED}✗ npm is not installed${NC}"
        missing_deps=true
    else
        echo -e "${GREEN}✓ npm $(npm --version)${NC}"
    fi
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}✗ AWS CLI is not installed${NC}"
        missing_deps=true
    else
        echo -e "${GREEN}✓ AWS CLI $(aws --version | cut -d' ' -f1)${NC}"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}✗ AWS credentials not configured${NC}"
        echo "  Run: aws configure"
        missing_deps=true
    else
        echo -e "${GREEN}✓ AWS credentials configured${NC}"
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        REGION=$(aws configure get region)
        echo "  Account: $ACCOUNT_ID"
        echo "  Region: $REGION"
    fi
    
    # Check CDK
    if ! command -v cdk &> /dev/null; then
        echo -e "${YELLOW}⚠ AWS CDK not installed globally${NC}"
        echo -e "${YELLOW}  Installing AWS CDK...${NC}"
        npm install -g aws-cdk
    else
        echo -e "${GREEN}✓ AWS CDK $(cdk --version)${NC}"
    fi
    
    if [ "$missing_deps" = true ]; then
        echo -e "\n${RED}Please install missing dependencies before continuing.${NC}"
        exit 1
    fi
    
    echo -e "\n${GREEN}All prerequisites satisfied!${NC}\n"
}

# Select deployment preset
select_preset() {
    echo -e "${BLUE}Select deployment configuration:${NC}"
    echo "1) Minimal Development - Basic LibreChat without RAG/Search (~$150/month)"
    echo "2) Standard Development - LibreChat with RAG (~$180/month)"
    echo "3) Full Development - All features enabled (~$220/month)"
    echo "4) Production EC2 - Cost-optimized production (~$250/month)"
    echo "5) Production ECS - Auto-scaling production (~$400/month)"
    echo "6) Enterprise - Full-featured with high availability (~$800/month)"
    echo "7) Custom Configuration - Build your own"
    
    read -p "Select option (1-7): " preset_choice
    
    case $preset_choice in
        1) CONFIG_SOURCE="minimal-dev" ;;
        2) CONFIG_SOURCE="standard-dev" ;;
        3) CONFIG_SOURCE="full-dev" ;;
        4) CONFIG_SOURCE="production-ec2" ;;
        5) CONFIG_SOURCE="production-ecs" ;;
        6) CONFIG_SOURCE="enterprise" ;;
        7) CONFIG_SOURCE="custom" ;;
        *) echo -e "${RED}Invalid selection${NC}"; exit 1 ;;
    esac
}

# Get deployment parameters
get_parameters() {
    echo -e "\n${BLUE}Deployment Parameters:${NC}"
    
    # Key pair for EC2 deployments
    if [[ "$CONFIG_SOURCE" != "production-ecs" && "$CONFIG_SOURCE" != "enterprise" ]] || [[ "$CONFIG_SOURCE" == "custom" ]]; then
        # List available key pairs
        echo -e "\n${YELLOW}Available EC2 Key Pairs:${NC}"
        aws ec2 describe-key-pairs --query 'KeyPairs[*].KeyName' --output table
        
        read -p "Enter EC2 key pair name (required for SSH access): " KEY_PAIR_NAME
        if [ -z "$KEY_PAIR_NAME" ]; then
            echo -e "${RED}Key pair name is required for EC2 deployments${NC}"
            exit 1
        fi
        CDK_CONTEXT="$CDK_CONTEXT -c keyPairName=$KEY_PAIR_NAME"
    fi
    
    # Alert email
    read -p "Enter email for CloudWatch alerts (optional): " ALERT_EMAIL
    if [ -n "$ALERT_EMAIL" ]; then
        CDK_CONTEXT="$CDK_CONTEXT -c alertEmail=$ALERT_EMAIL"
    fi
    
    # SSH access
    if [[ "$CONFIG_SOURCE" == *"ec2"* ]] || [[ "$CONFIG_SOURCE" == "custom" ]]; then
        echo -e "\n${YELLOW}Configure SSH access:${NC}"
        echo "1) Allow from my current IP only"
        echo "2) Allow from specific IP/CIDR"
        echo "3) Allow from anywhere (0.0.0.0/0) - NOT RECOMMENDED"
        
        read -p "Select option (1-3): " ssh_choice
        
        case $ssh_choice in
            1)
                MY_IP=$(curl -s https://checkip.amazonaws.com)
                CDK_CONTEXT="$CDK_CONTEXT -c allowedIps=${MY_IP}/32"
                echo "  Allowing SSH from: ${MY_IP}/32"
                ;;
            2)
                read -p "Enter IP/CIDR (e.g., 192.168.1.0/24): " ALLOWED_IP
                CDK_CONTEXT="$CDK_CONTEXT -c allowedIps=$ALLOWED_IP"
                ;;
            3)
                echo -e "${YELLOW}  ⚠ WARNING: Allowing SSH from anywhere is a security risk${NC}"
                CDK_CONTEXT="$CDK_CONTEXT -c allowedIps=0.0.0.0/0"
                ;;
        esac
    fi
    
    # Domain configuration
    echo -e "\n${YELLOW}Configure domain (optional):${NC}"
    read -p "Do you have a domain name? (y/n): " has_domain
    
    if [[ "$has_domain" == "y" ]]; then
        read -p "Enter domain name (e.g., librechat.example.com): " DOMAIN_NAME
        CDK_CONTEXT="$CDK_CONTEXT -c domainName=$DOMAIN_NAME"
        
        # Check for existing certificates
        echo -e "\n${YELLOW}Checking for SSL certificates...${NC}"
        aws acm list-certificates --query 'CertificateSummaryList[?Status==`ISSUED`].[DomainName,CertificateArn]' --output table
        
        read -p "Enter certificate ARN (or press Enter to skip HTTPS): " CERT_ARN
        if [ -n "$CERT_ARN" ]; then
            CDK_CONTEXT="$CDK_CONTEXT -c certificateArn=$CERT_ARN"
            
            # Check for Route53 hosted zones
            echo -e "\n${YELLOW}Checking for Route53 hosted zones...${NC}"
            aws route53 list-hosted-zones --query 'HostedZones[*].[Name,Id]' --output table
            
            read -p "Enter hosted zone ID (or press Enter for manual DNS): " ZONE_ID
            if [ -n "$ZONE_ID" ]; then
                CDK_CONTEXT="$CDK_CONTEXT -c hostedZoneId=$ZONE_ID"
            fi
        fi
    fi
}

# Custom configuration
configure_custom() {
    echo -e "\n${BLUE}Custom Configuration:${NC}"
    
    # Environment
    echo "Select environment:"
    echo "1) Development"
    echo "2) Staging"  
    echo "3) Production"
    read -p "Select (1-3): " env_choice
    
    case $env_choice in
        1) ENVIRONMENT="development" ;;
        2) ENVIRONMENT="staging" ;;
        3) ENVIRONMENT="production" ;;
        *) ENVIRONMENT="development" ;;
    esac
    CDK_CONTEXT="$CDK_CONTEXT -c environment=$ENVIRONMENT"
    
    # Deployment mode
    echo -e "\nSelect deployment mode:"
    echo "1) EC2 - Simple, cost-effective"
    echo "2) ECS - Scalable, containerized"
    read -p "Select (1-2): " mode_choice
    
    case $mode_choice in
        1) DEPLOYMENT_MODE="EC2" ;;
        2) DEPLOYMENT_MODE="ECS" ;;
        *) DEPLOYMENT_MODE="EC2" ;;
    esac
    CDK_CONTEXT="$CDK_CONTEXT -c deploymentMode=$DEPLOYMENT_MODE"
    
    # Features
    echo -e "\nEnable features:"
    read -p "Enable RAG (Retrieval Augmented Generation)? (y/n): " enable_rag
    [[ "$enable_rag" == "y" ]] && CDK_CONTEXT="$CDK_CONTEXT -c enableRag=true"
    
    read -p "Enable Meilisearch? (y/n): " enable_search
    [[ "$enable_search" == "y" ]] && CDK_CONTEXT="$CDK_CONTEXT -c enableMeilisearch=true"
    
    if [[ "$ENVIRONMENT" == "production" ]]; then
        read -p "Enable SharePoint integration? (y/n): " enable_sp
        [[ "$enable_sp" == "y" ]] && CDK_CONTEXT="$CDK_CONTEXT -c enableSharePoint=true"
    fi
    
    # VPC configuration
    echo -e "\nVPC configuration:"
    read -p "Use existing VPC? (y/n): " use_existing_vpc
    
    if [[ "$use_existing_vpc" == "y" ]]; then
        aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0],CidrBlock]' --output table
        read -p "Enter VPC ID: " VPC_ID
        CDK_CONTEXT="$CDK_CONTEXT -c existingVpcId=$VPC_ID"
    fi
}

# Deploy the stack
deploy_stack() {
    echo -e "\n${BLUE}Deployment Summary:${NC}"
    echo "Configuration: $CONFIG_SOURCE"
    echo "Region: $REGION"
    echo "Account: $ACCOUNT_ID"
    echo "Context parameters: $CDK_CONTEXT"
    
    echo -e "\n${YELLOW}This will create AWS resources and incur costs.${NC}"
    read -p "Continue with deployment? (y/n): " confirm
    
    if [[ "$confirm" != "y" ]]; then
        echo "Deployment cancelled."
        exit 0
    fi
    
    # Install dependencies
    echo -e "\n${BLUE}Installing dependencies...${NC}"
    npm install
    
    # Build the project
    echo -e "\n${BLUE}Building project...${NC}"
    npm run build
    
    # Bootstrap CDK if needed
    if ! aws cloudformation describe-stacks --stack-name CDKToolkit &> /dev/null; then
        echo -e "\n${BLUE}Bootstrapping CDK...${NC}"
        cdk bootstrap
    fi
    
    # Deploy
    echo -e "\n${BLUE}Deploying LibreChat...${NC}"
    cdk deploy -c configSource=$CONFIG_SOURCE $CDK_CONTEXT --require-approval never
    
    # Get outputs
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║                 Deployment Successful! 🎉                 ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
        
        STACK_NAME="LibreChatStack-$ENVIRONMENT"
        echo -e "\n${BLUE}Stack Outputs:${NC}"
        aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' --output table
        
        # Get load balancer URL
        LB_URL=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' --output text)
        
        echo -e "\n${GREEN}Access LibreChat at: $LB_URL${NC}"
        echo -e "${YELLOW}Note: It may take 15-20 minutes for the application to be fully ready.${NC}"
        
        # Save deployment info
        cat > deployment-info.json << EOF
{
  "stackName": "$STACK_NAME",
  "region": "$REGION",
  "account": "$ACCOUNT_ID",
  "url": "$LB_URL",
  "deployedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "configuration": "$CONFIG_SOURCE"
}
EOF
        echo -e "\n${GREEN}Deployment information saved to deployment-info.json${NC}"
    else
        echo -e "\n${RED}Deployment failed. Check the error messages above.${NC}"
        exit 1
    fi
}

# Main execution
main() {
    # Change to script directory
    cd "$(dirname "$0")/.."
    
    check_prerequisites
    select_preset
    
    if [[ "$CONFIG_SOURCE" == "custom" ]]; then
        configure_custom
    fi
    
    get_parameters
    deploy_stack
}

# Run main function
main
