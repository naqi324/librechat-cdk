#!/bin/bash
# LibreChat CDK Deployment Script
# Unified deployment tool with multiple modes and options

set -e

# Enable AWS SDK to load config file (required for SSO and advanced auth)
export AWS_SDK_LOAD_CONFIG=1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
FAST_MODE=false
PERSISTENT_MODE=false
CONFIG_FILE=""
SKIP_WIZARD=false
SHOW_HELP=false
VERBOSE_MODE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--fast)
            FAST_MODE=true
            shift
            ;;
        -p|--persistent)
            PERSISTENT_MODE=true
            shift
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            SKIP_WIZARD=true
            shift 2
            ;;
        -v|--verbose)
            VERBOSE_MODE=true
            shift
            ;;
        -h|--help)
            SHOW_HELP=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            SHOW_HELP=true
            shift
            ;;
    esac
done

# Show help if requested
if [ "$SHOW_HELP" = true ]; then
    echo -e "${BLUE}LibreChat CDK Deployment Script${NC}"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -f, --fast          Fast deployment mode (smaller resources, hotswap updates)"
    echo "  -p, --persistent    Run in persistent session (screen/tmux) for CloudShell"
    echo "  -c, --config FILE   Use existing configuration file (skip wizard)"
    echo "  -v, --verbose       Show detailed deployment progress with descriptions"
    echo "  -h, --help          Show this help message"
    echo
    echo "Examples:"
    echo "  $0                  # Interactive setup wizard"
    echo "  $0 --fast           # Fast deployment mode"
    echo "  $0 --persistent     # Protected from disconnection"
    echo "  $0 --config .env    # Use existing configuration"
    echo
    exit 0
fi

# Handle persistent mode
if [ "$PERSISTENT_MODE" = true ]; then
    # Check if already in screen/tmux
    if [ -n "$STY" ]; then
        echo -e "${GREEN}✓ Already in screen session${NC}"
    elif [ -n "$TMUX" ]; then
        echo -e "${GREEN}✓ Already in tmux session${NC}"
    else
        echo -e "${YELLOW}⚠️  Starting persistent session...${NC}"
        echo "If disconnected, reconnect with: screen -r librechat-deploy"
        echo "Press Enter to continue..."
        read
        
        # Re-run this script inside screen with all original arguments
        ORIGINAL_ARGS="$@"
        exec screen -S librechat-deploy "$0" $ORIGINAL_ARGS
    fi
fi

# Banner
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════╗"
echo "║          LibreChat CDK Deployment             ║"
echo "║         Enterprise AWS Deployment             ║"
echo "╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

# Show mode indicators
if [ "$FAST_MODE" = true ]; then
    echo -e "${CYAN}🚀 Fast Mode Enabled${NC}"
fi
if [ "$PERSISTENT_MODE" = true ]; then
    echo -e "${CYAN}🔒 Persistent Session Active${NC}"
fi
if [ "$SKIP_WIZARD" = true ] && [ -n "$CONFIG_FILE" ]; then
    echo -e "${CYAN}📋 Using configuration: $CONFIG_FILE${NC}"
fi
echo

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Function to prompt with default
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    if [ -z "$default" ]; then
        read -p "$prompt: " value
    else
        read -p "$prompt [$default]: " value
        value="${value:-$default}"
    fi
    eval "$var_name='$value'"
}

# Quick validation checks
echo -e "\n${BLUE}🔍 Running Pre-deployment Checks${NC}"
echo "================================="

# Check for failed stacks
FAILED_STACKS=$(aws cloudformation list-stacks \
    --query "StackSummaries[?contains(StackName, 'LibreChat') && (contains(StackStatus, 'FAILED') || contains(StackStatus, 'ROLLBACK'))].{Name:StackName,Status:StackStatus}" \
    --output text 2>/dev/null || echo "")

if [ ! -z "$FAILED_STACKS" ]; then
    print_warning "Found stacks in failed state:"
    echo "$FAILED_STACKS" | while read line; do
        echo "  - $line"
    done
    echo
    echo "To clean up failed stacks, run: ./scripts/cleanup.sh -m rollback-fix"
    echo
    read -p "Continue anyway? (y/n) [n]: " continue_deploy
    if [ "$continue_deploy" != "y" ]; then
        exit 1
    fi
fi

# Check CDK bootstrap
BOOTSTRAP_STATUS=$(aws cloudformation describe-stacks --stack-name CDKToolkit --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$BOOTSTRAP_STATUS" == "NOT_FOUND" ]; then
    print_warning "CDK not bootstrapped. Will bootstrap during deployment."
elif [[ "$BOOTSTRAP_STATUS" != "CREATE_COMPLETE" && "$BOOTSTRAP_STATUS" != "UPDATE_COMPLETE" ]]; then
    print_error "CDK bootstrap stack in bad state: $BOOTSTRAP_STATUS"
    echo "Run: ./scripts/manage-bootstrap.sh fix"
    exit 1
fi

# Check prerequisites
echo -e "\n${BLUE}📋 Checking Prerequisites${NC}"
echo "=========================="

# Check Node.js
if ! command -v node &> /dev/null; then
    print_error "Node.js is not installed"
    echo "Please install Node.js 18+ from https://nodejs.org/"
    exit 1
else
    NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 18 ]; then
        print_error "Node.js version must be 18 or higher (found: $(node -v))"
        exit 1
    fi
    print_status "Node.js $(node -v) found"
fi

# Check npm
if ! command -v npm &> /dev/null; then
    print_error "npm is not installed"
    exit 1
else
    print_status "npm $(npm -v) found"
fi

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    print_warning "AWS CLI not found - some features may be limited"
    echo "  Install from: https://aws.amazon.com/cli/"
    HAS_AWS_CLI=false
else
    print_status "AWS CLI found"
    HAS_AWS_CLI=true
    
    # Check AWS credentials
    print_status "Checking AWS credentials..."
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured or expired"
        
        # Check if using SSO
        if [ -n "$AWS_PROFILE" ] && grep -q "sso_start_url" ~/.aws/config 2>/dev/null; then
            print_warning "SSO session appears to be expired"
            echo "Please run: aws sso login --profile $AWS_PROFILE"
        else
            echo "Please configure AWS credentials using one of these methods:"
            echo "  1. AWS SSO: aws configure sso"
            echo "  2. IAM User: aws configure"
            echo "  3. Environment variables: export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=..."
        fi
        exit 1
    else
        AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
        AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
        AWS_PROFILE_NAME=${AWS_PROFILE:-"default"}
        print_status "AWS authenticated successfully"
        print_status "Account: $AWS_ACCOUNT | Region: $AWS_REGION | Profile: $AWS_PROFILE_NAME"
    fi
fi

# Install dependencies
echo -e "\n${BLUE}📦 Installing Dependencies${NC}"
echo "=========================="
npm install
print_status "Dependencies installed"

# Check/Install CDK CLI
if ! command -v cdk &> /dev/null; then
    print_info "Installing AWS CDK CLI globally..."
    npm install -g aws-cdk
    print_status "AWS CDK CLI installed"
else
    print_status "AWS CDK CLI found"
fi

# Acknowledge CDK notices to reduce output noise
npx cdk acknowledge 34892 2>/dev/null || true  # CDK telemetry
npx cdk acknowledge 32775 2>/dev/null || true  # CLI version divergence

# Handle configuration
if [ "$SKIP_WIZARD" = true ] && [ -n "$CONFIG_FILE" ]; then
    # Use specified config file
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    print_status "Loading configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"
    
    # Validate EC2 key pair if needed
    if [ "$DEPLOYMENT_MODE" = "EC2" ] && [ ! -z "$KEY_PAIR_NAME" ] && [ "$HAS_AWS_CLI" = true ]; then
        if ! aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" &>/dev/null; then
            print_error "Key pair not found: $KEY_PAIR_NAME"
            echo "Create it with: aws ec2 create-key-pair --key-name $KEY_PAIR_NAME --query 'KeyMaterial' --output text > $KEY_PAIR_NAME.pem"
            exit 1
        fi
    fi
    
    # Jump directly to deployment
    echo -e "\n${BLUE}📦 Building Project${NC}"
    npm run build
    
    echo -e "\n${BLUE}🔧 Bootstrapping CDK${NC}"
    ./scripts/manage-bootstrap.sh fix || {
        echo -e "${RED}Bootstrap failed. Run: ./scripts/manage-bootstrap.sh clean${NC}"
        exit 1
    }
    
    echo -e "\n${BLUE}🚀 Deploying Stack${NC}"
    if [ "$FAST_MODE" = true ]; then
        # Check if stack exists for hotswap
        STACK_EXISTS=$(aws cloudformation describe-stacks --stack-name "LibreChatStack-${DEPLOYMENT_ENV:-development}" 2>/dev/null || echo "")
        
        if [ ! -z "$STACK_EXISTS" ]; then
            echo -e "${CYAN}Using CDK hotswap for faster updates...${NC}"
            npx cdk deploy --hotswap --all
        else
            echo -e "${CYAN}Using fast deployment settings...${NC}"
            FAST_DEPLOY=true npx cdk deploy --all --concurrency 10 --require-approval never -c fastDeploy=true
        fi
    elif [ "$VERBOSE_MODE" = true ]; then
        echo -e "${CYAN}Deploying with verbose output...${NC}"
        echo -e "${YELLOW}This process will:${NC}"
        echo "  1. Create/update VPC and networking resources"
        echo "  2. Set up RDS PostgreSQL database with pgvector (5-10 min)"
        echo "  3. Deploy Lambda functions for initialization"
        echo "  4. Launch compute resources (EC2/ECS)"
        echo "  5. Configure load balancer and monitoring"
        echo
        
        npx cdk deploy --all --require-approval never --progress events 2>&1 | while IFS= read -r line; do
            # Parse and enhance CDK output
            if [[ "$line" == *"CREATE_IN_PROGRESS"* ]]; then
                if [[ "$line" == *"AWS::EC2::VPC"* ]]; then
                    echo -e "${BLUE}🌐 Creating Virtual Private Cloud (VPC)...${NC}"
                elif [[ "$line" == *"AWS::RDS::DBInstance"* ]] || [[ "$line" == *"AWS::RDS::DBCluster"* ]]; then
                    echo -e "${BLUE}🗄️  Creating PostgreSQL database (this takes 5-10 minutes)...${NC}"
                elif [[ "$line" == *"AWS::Lambda::Function"* ]]; then
                    echo -e "${BLUE}⚡ Creating Lambda functions...${NC}"
                elif [[ "$line" == *"AWS::ECS::Cluster"* ]]; then
                    echo -e "${BLUE}🐳 Creating ECS cluster...${NC}"
                elif [[ "$line" == *"AWS::EC2::Instance"* ]]; then
                    echo -e "${BLUE}💻 Launching EC2 instance...${NC}"
                elif [[ "$line" == *"AWS::ElasticLoadBalancingV2::LoadBalancer"* ]]; then
                    echo -e "${BLUE}⚖️  Creating Application Load Balancer...${NC}"
                elif [[ "$line" == *"AWS::S3::Bucket"* ]]; then
                    echo -e "${BLUE}📦 Creating S3 storage bucket...${NC}"
                fi
            elif [[ "$line" == *"CREATE_COMPLETE"* ]] && [[ "$line" == *"AWS::CloudFormation::Stack"* ]]; then
                echo -e "${GREEN}✅ Stack deployment completed!${NC}"
            elif [[ "$line" == *"UPDATE_COMPLETE"* ]] && [[ "$line" == *"AWS::CloudFormation::Stack"* ]]; then
                echo -e "${GREEN}✅ Stack update completed!${NC}"
            elif [[ "$line" == *"failed"* ]] || [[ "$line" == *"FAILED"* ]]; then
                echo -e "${RED}$line${NC}"
            else
                echo "$line"
            fi
        done
    else
        npx cdk deploy --all
    fi
    
    print_status "Deployment complete!"
    exit 0
elif [ -f .env ] && [ "$SKIP_WIZARD" = false ]; then
    # Existing .env found, ask user
    echo -e "\n${YELLOW}⚠️  Existing Configuration Found${NC}"
    echo "================================"
    echo "An .env file already exists with the following configuration:"
    echo
    grep -E "^(DEPLOYMENT_MODE|KEY_PAIR_NAME|DEPLOYMENT_ENV)" .env || true
    echo
    read -p "Do you want to keep this configuration? (y/n) [y]: " keep_config
    keep_config="${keep_config:-y}"
    
    if [ "$keep_config" = "y" ]; then
        print_status "Using existing configuration"
        
        # Load existing config
        source .env
        
        # Skip to deployment
        echo -e "\n${BLUE}🚀 Ready to Deploy${NC}"
        echo "=================="
        read -p "Would you like to deploy now? (y/n) [y]: " deploy_now
        deploy_now="${deploy_now:-y}"
        
        if [ "$deploy_now" = "y" ]; then
            echo -e "\n${BLUE}📦 Building Project${NC}"
            npm run build
            
            echo -e "\n${BLUE}🔧 Bootstrapping CDK${NC}"
            ./scripts/manage-bootstrap.sh fix || {
                echo -e "${RED}Bootstrap failed. Run: ./scripts/manage-bootstrap.sh clean${NC}"
                exit 1
            }
            
            echo -e "\n${BLUE}🚀 Deploying Stack${NC}"
            if [ "$FAST_MODE" = true ]; then
                # Check if stack exists for hotswap
                STACK_EXISTS=$(aws cloudformation describe-stacks --stack-name "LibreChatStack-${DEPLOYMENT_ENV:-development}" 2>/dev/null || echo "")
                
                if [ ! -z "$STACK_EXISTS" ]; then
                    echo -e "${CYAN}Using CDK hotswap for faster updates...${NC}"
                    npx cdk deploy --hotswap --all
                else
                    echo -e "${CYAN}Using fast deployment settings...${NC}"
                    FAST_DEPLOY=true npx cdk deploy --all --concurrency 10 --require-approval never -c fastDeploy=true
                fi
            elif [ "$VERBOSE_MODE" = true ]; then
                echo -e "${CYAN}Deploying with verbose output...${NC}"
                npx cdk deploy --all --require-approval never --progress events 2>&1 | while IFS= read -r line; do
                    if [[ "$line" == *"CREATE_IN_PROGRESS"* ]] || [[ "$line" == *"UPDATE_IN_PROGRESS"* ]]; then
                        echo -e "${BLUE}⏳ $line${NC}"
                    elif [[ "$line" == *"COMPLETE"* ]]; then
                        echo -e "${GREEN}✅ $line${NC}"
                    elif [[ "$line" == *"FAILED"* ]]; then
                        echo -e "${RED}❌ $line${NC}"
                    else
                        echo "$line"
                    fi
                done
            else
                npx cdk deploy --all
            fi
            
            print_status "Deployment complete!"
        else
            echo -e "\n${GREEN}Setup complete! To deploy later, run:${NC}"
            echo "  ./deploy.sh --config .env"
        fi
        exit 0
    else
        mv .env .env.backup.$(date +%Y%m%d_%H%M%S)
        print_info "Existing configuration backed up"
    fi
fi

# Configuration wizard
echo -e "\n${BLUE}🔧 Configuration Wizard${NC}"
echo "======================="

# Deployment mode selection
echo -e "\n${BLUE}Select Deployment Mode:${NC}"
echo "1) ECS - Containerized deployment (Recommended)"
echo "   ✅ No SSH key required"
echo "   ✅ Auto-scaling enabled"
echo "   ✅ Best for production"
echo
echo "2) EC2 - Virtual machine deployment"
echo "   ⚠️  Requires SSH key pair"
echo "   ✅ Direct server access"
echo "   ✅ Lower cost for small deployments"
echo
prompt_with_default "Enter choice (1 or 2)" "1" mode_choice

if [ "$mode_choice" = "2" ]; then
    DEPLOYMENT_MODE="EC2"
    echo -e "\n${BLUE}EC2 Key Pair Configuration${NC}"
    
    # List existing key pairs if AWS CLI available
    if [ "$HAS_AWS_CLI" = true ]; then
        echo -e "\nExisting key pairs in your AWS account:"
        aws ec2 describe-key-pairs --query 'KeyPairs[*].KeyName' --output text 2>/dev/null | tr '\t' '\n' | sed 's/^/  - /' || echo "  Unable to list key pairs"
        echo
    fi
    
    echo "Options:"
    echo "1) Use existing key pair"
    echo "2) Create new key pair"
    echo "3) I'll create one manually later"
    prompt_with_default "Enter choice (1-3)" "1" key_choice
    
    case $key_choice in
        1)
            prompt_with_default "Enter key pair name" "" KEY_PAIR_NAME
            if [ -z "$KEY_PAIR_NAME" ]; then
                print_error "Key pair name is required for EC2 deployment"
                exit 1
            fi
            # Validate the key pair exists
            if [ "$HAS_AWS_CLI" = true ]; then
                if ! aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" &>/dev/null; then
                    print_error "Key pair '$KEY_PAIR_NAME' not found in AWS"
                    echo "Please create it first or choose option 2 to create a new one"
                    exit 1
                fi
                print_status "Key pair validated: $KEY_PAIR_NAME"
            fi
            ;;
        2)
            prompt_with_default "Enter name for new key pair" "librechat-key" KEY_PAIR_NAME
            if [ "$HAS_AWS_CLI" = true ]; then
                echo "Creating key pair..."
                aws ec2 create-key-pair --key-name "$KEY_PAIR_NAME" --query 'KeyMaterial' --output text > "${KEY_PAIR_NAME}.pem"
                chmod 400 "${KEY_PAIR_NAME}.pem"
                print_status "Key pair created and saved to ${KEY_PAIR_NAME}.pem"
                print_warning "Keep this file safe - you'll need it to SSH to your instance"
            else
                print_error "AWS CLI required to create key pair"
                echo "Please create the key pair manually in AWS Console"
                exit 1
            fi
            ;;
        3)
            print_warning "Remember to create a key pair before deployment"
            print_info "You can create one in AWS Console > EC2 > Key Pairs"
            prompt_with_default "Enter the key pair name you'll create" "my-key" KEY_PAIR_NAME
            ;;
    esac
else
    DEPLOYMENT_MODE="ECS"
    print_status "ECS deployment selected - no SSH key required"
fi

# Deployment Speed Choice
echo -e "\n${BLUE}Deployment Speed Configuration${NC}"
echo "==============================="
echo
echo "How would you like to optimize your deployment?"
echo
echo "1) Fast Deployment (Recommended for first-time users)"
echo "   • Uses minimal resources for quickest setup (~10 minutes)"
echo "   • Perfect for testing and development"
echo "   • Easy to scale up later"
echo "   • ~$40/month"
echo
echo "2) Custom Resource Size"
echo "   • Choose specific resource sizes"
echo "   • Better for production use"
echo "   • Takes 15-20 minutes"
echo
prompt_with_default "Enter choice (1 or 2)" "1" speed_choice

if [ "$speed_choice" = "1" ]; then
    RESOURCE_SIZE="xs"
    FAST_DEPLOY="true"
    print_status "Fast deployment mode selected"
    print_info "You can scale up resources later with: RESOURCE_SIZE=medium npm run deploy"
else
    # Resource Size Selection
    echo -e "\n${BLUE}Resource Size Configuration${NC}"
    echo "========================="
    echo
    echo "Select the resource size for your deployment:"
    echo
    echo "1) Extra Small (XS) - Testing only (1-5 users)"
    echo "   • EC2: t3.micro, ECS: 256 CPU/512 MB"
    echo "   • RDS: db.t3.micro, 20 GB storage"
    echo "   • ~$50/month"
    echo
    echo "2) Small - Light workloads (5-20 users)"
    echo "   • EC2: t3.small, ECS: 512 CPU/1 GB" 
    echo "   • RDS: db.t3.small, 50 GB storage"
    echo "   • ~$120/month"
    echo
    echo "3) Medium - Standard workloads (20-100 users) [Recommended]"
    echo "   • EC2: t3.large, ECS: 1024 CPU/2 GB"
    echo "   • RDS: db.t3.medium, 100 GB storage"
    echo "   • ~$300/month"
    echo
    echo "4) Large - Heavy workloads (100-500 users)"
    echo "   • EC2: t3.xlarge, ECS: 2048 CPU/4 GB"
    echo "   • RDS: db.r6g.large, 200 GB storage"
    echo "   • ~$800/month"
    echo
    echo "5) Extra Large (XL) - Enterprise (500+ users)"
    echo "   • EC2: t3.2xlarge, ECS: 4096 CPU/8 GB"
    echo "   • RDS: db.r6g.xlarge, 500 GB storage"
    echo "   • ~$2000/month"
    echo
    prompt_with_default "Enter choice (1-5)" "3" size_choice

    case "$size_choice" in
        1) RESOURCE_SIZE="xs" ;;
        2) RESOURCE_SIZE="small" ;;
        3) RESOURCE_SIZE="medium" ;;
        4) RESOURCE_SIZE="large" ;;
        5) RESOURCE_SIZE="xl" ;;
        *) RESOURCE_SIZE="medium" ;;
    esac
    
    FAST_DEPLOY="false"
    print_status "Resource size: $RESOURCE_SIZE"
fi

# Environment selection
echo -e "\n${BLUE}Environment Configuration${NC}"
prompt_with_default "Environment (development/staging/production)" "development" DEPLOYMENT_ENV

# Alert email
echo -e "\n${BLUE}Monitoring Configuration${NC}"
prompt_with_default "Alert email for monitoring notifications" "alerts@example.com" ALERT_EMAIL

# Domain configuration
echo -e "\n${BLUE}Domain Configuration${NC}"
read -p "Configure a custom domain? (y/n) [n]: " configure_domain
configure_domain="${configure_domain:-n}"

if [ "$configure_domain" = "y" ]; then
    prompt_with_default "Domain name" "chat.example.com" DOMAIN_NAME
    
    if [ "$HAS_AWS_CLI" = true ]; then
        echo -e "\nChecking for ACM certificates..."
        aws acm list-certificates --query 'CertificateSummaryList[*].[DomainName,CertificateArn]' --output table 2>/dev/null || true
    fi
    
    prompt_with_default "ACM certificate ARN (leave empty to skip HTTPS)" "" CERTIFICATE_ARN
    
    if [ -n "$CERTIFICATE_ARN" ]; then
        prompt_with_default "Route53 hosted zone ID (leave empty for manual DNS)" "" HOSTED_ZONE_ID
    fi
fi

# Feature configuration
echo -e "\n${BLUE}Feature Configuration${NC}"
echo "Select which features to enable:"
echo

read -p "Enable RAG (Retrieval Augmented Generation)? (y/n) [y]: " enable_rag
enable_rag="${enable_rag:-y}"
ENABLE_RAG=$([ "$enable_rag" = "y" ] && echo "true" || echo "false")

read -p "Enable Meilisearch (fast search engine)? (y/n) [n]: " enable_meilisearch
enable_meilisearch="${enable_meilisearch:-n}"
ENABLE_MEILISEARCH=$([ "$enable_meilisearch" = "y" ] && echo "true" || echo "false")

if [ "$DEPLOYMENT_ENV" = "production" ]; then
    read -p "Enable SharePoint integration? (y/n) [n]: " enable_sharepoint
    enable_sharepoint="${enable_sharepoint:-n}"
    ENABLE_SHAREPOINT=$([ "$enable_sharepoint" = "y" ] && echo "true" || echo "false")
else
    ENABLE_SHAREPOINT="false"
fi

# VPC configuration
echo -e "\n${BLUE}Network Configuration${NC}"
read -p "Use existing VPC? (y/n) [n]: " use_existing_vpc
use_existing_vpc="${use_existing_vpc:-n}"

if [ "$use_existing_vpc" = "y" ]; then
    if [ "$HAS_AWS_CLI" = true ]; then
        echo -e "\nAvailable VPCs:"
        aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0],CidrBlock]' --output table 2>/dev/null || true
    fi
    prompt_with_default "VPC ID" "" EXISTING_VPC_ID
fi

# IP allowlist for EC2
if [ "$DEPLOYMENT_MODE" = "EC2" ]; then
    echo -e "\n${BLUE}Security Configuration${NC}"
    echo "Configure IP addresses allowed to access the instance (for SSH and web access)"
    echo "Examples:"
    echo "  - 0.0.0.0/0 (allow all - not recommended for production)"
    echo "  - 192.168.1.0/24 (allow subnet)"
    echo "  - 203.0.113.45/32 (allow single IP)"
    prompt_with_default "Allowed IP ranges (comma-separated)" "0.0.0.0/0" ALLOWED_IPS
fi

# Write configuration
echo -e "\n${BLUE}💾 Saving Configuration${NC}"
echo "======================="

cat > .env << EOF
# LibreChat CDK Configuration
# Generated on $(date)
# Run './deploy.sh --config .env' to deploy this configuration

# Deployment Settings
DEPLOYMENT_ENV=$DEPLOYMENT_ENV
DEPLOYMENT_MODE=$DEPLOYMENT_MODE
RESOURCE_SIZE=$RESOURCE_SIZE
FAST_DEPLOY=$FAST_DEPLOY
EOF

if [ "$DEPLOYMENT_MODE" = "EC2" ]; then
    echo "KEY_PAIR_NAME=$KEY_PAIR_NAME" >> .env
    echo "ALLOWED_IPS=$ALLOWED_IPS" >> .env
fi

cat >> .env << EOF

# Monitoring
ALERT_EMAIL=$ALERT_EMAIL

# Features
ENABLE_RAG=$ENABLE_RAG
ENABLE_MEILISEARCH=$ENABLE_MEILISEARCH
ENABLE_SHAREPOINT=$ENABLE_SHAREPOINT
EOF

if [ "$configure_domain" = "y" ]; then
    cat >> .env << EOF

# Domain Configuration
DOMAIN_NAME=$DOMAIN_NAME
EOF
    [ -n "$CERTIFICATE_ARN" ] && echo "CERTIFICATE_ARN=$CERTIFICATE_ARN" >> .env
    [ -n "$HOSTED_ZONE_ID" ] && echo "HOSTED_ZONE_ID=$HOSTED_ZONE_ID" >> .env
fi

if [ "$use_existing_vpc" = "y" ]; then
    cat >> .env << EOF

# VPC Configuration
EXISTING_VPC_ID=$EXISTING_VPC_ID
EOF
fi

print_status "Configuration saved to .env"

# Display configuration summary
echo -e "\n${BLUE}📋 Configuration Summary${NC}"
echo "========================"
echo "Deployment Mode: $DEPLOYMENT_MODE"
echo "Environment: $DEPLOYMENT_ENV"
[ "$DEPLOYMENT_MODE" = "EC2" ] && echo "Key Pair: $KEY_PAIR_NAME"
echo "Alert Email: $ALERT_EMAIL"
echo "Features:"
echo "  - RAG: $ENABLE_RAG"
echo "  - Meilisearch: $ENABLE_MEILISEARCH"
echo "  - SharePoint: $ENABLE_SHAREPOINT"
[ -n "$DOMAIN_NAME" ] && echo "Domain: $DOMAIN_NAME"

# Deployment
echo -e "\n${BLUE}🚀 Ready to Deploy${NC}"
echo "=================="
echo "Your configuration is complete. The deployment will:"
echo "1. Build the TypeScript code"
echo "2. Bootstrap CDK (prepare AWS account)"
echo "3. Deploy the LibreChat stack"
echo
echo "This process takes approximately 15-20 minutes."
echo
read -p "Deploy now? (y/n) [y]: " deploy_now
deploy_now="${deploy_now:-y}"

if [ "$deploy_now" = "y" ]; then
    # Build
    echo -e "\n${BLUE}📦 Building Project${NC}"
    echo "==================="
    npm run build
    print_status "Build complete"
    
    # Bootstrap
    echo -e "\n${BLUE}🔧 Bootstrapping CDK${NC}"
    echo "===================="
    echo "This prepares your AWS account for CDK deployments..."
    
    # Check bootstrap status first
    if ./scripts/manage-bootstrap.sh status &>/dev/null; then
        echo -e "${GREEN}✅ CDK bootstrap already configured${NC}"
    else
        echo "Running CDK bootstrap..."
        ./scripts/manage-bootstrap.sh fix || {
            echo -e "${RED}Bootstrap failed. You may need to run:${NC}"
            echo "  ./scripts/manage-bootstrap.sh clean"
            exit 1
        }
    fi
    print_status "CDK bootstrap complete"
    
    # Deploy
    echo -e "\n${BLUE}🚀 Deploying Stack${NC}"
    echo "=================="
    
    if [ "$FAST_MODE" = true ]; then
        echo -e "${CYAN}Using fast deployment mode...${NC}"
        # Check if stack exists for hotswap
        STACK_EXISTS=$(aws cloudformation describe-stacks --stack-name "LibreChatStack-${DEPLOYMENT_ENV:-development}" 2>/dev/null || echo "")
        
        if [ ! -z "$STACK_EXISTS" ]; then
            echo "Detected existing stack - using CDK hotswap for faster updates"
            echo "This will take approximately 5-10 minutes..."
            npx cdk deploy --hotswap --all
        else
            echo "New deployment - using optimized settings"
            echo "This will take approximately 10-15 minutes..."
            FAST_DEPLOY=true npx cdk deploy --all --concurrency 10 --require-approval never -c fastDeploy=true
        fi
    else
        echo "This will take approximately 15-20 minutes..."
        if [ "$VERBOSE_MODE" = true ]; then
            npx cdk deploy --all --require-approval never --progress events 2>&1 | while IFS= read -r line; do
                if [[ "$line" == *"CREATE_IN_PROGRESS"* ]] || [[ "$line" == *"UPDATE_IN_PROGRESS"* ]]; then
                    echo -e "${BLUE}⏳ $line${NC}"
                elif [[ "$line" == *"COMPLETE"* ]]; then
                    echo -e "${GREEN}✅ $line${NC}"
                elif [[ "$line" == *"FAILED"* ]]; then
                    echo -e "${RED}❌ $line${NC}"
                else
                    echo "$line"
                fi
            done
        else
            npx cdk deploy --all
        fi
    fi
    
    echo -e "\n${GREEN}✨ Deployment Complete!${NC}"
    echo "======================="
    echo
    echo "Your LibreChat instance is being set up. Check the AWS CloudFormation"
    echo "console for detailed progress and outputs."
    echo
    echo "Once complete, you'll find:"
    echo "  - Application URL"
    echo "  - CloudWatch Dashboard"
    [ "$DEPLOYMENT_MODE" = "EC2" ] && echo "  - SSH connection instructions"
    echo
    echo "Thank you for using LibreChat CDK!"
else
    echo -e "\n${GREEN}✅ Setup Complete!${NC}"
    echo "=================="
    echo
    echo "Your configuration has been saved. To deploy later:"
    echo
    echo "  ./deploy.sh --config .env"
    echo
    echo "With options:"
    echo "  ./deploy.sh --config .env --fast       # Fast deployment"
    echo "  ./deploy.sh --config .env --persistent  # CloudShell safe"
    echo
    echo "To modify configuration:"
    echo "  - Edit .env file"
    echo "  - Run ./deploy.sh again"
    echo
    echo "For advanced options, see README.md"
fi

# Cleanup message
echo -e "\n${BLUE}📚 Next Steps${NC}"
echo "============="
echo "- Monitor deployment: AWS CloudFormation console"
echo "- View logs: AWS CloudWatch"
echo "- Access application: Check stack outputs for URL"
[ "$DEPLOYMENT_MODE" = "EC2" ] && echo "- SSH access: ssh -i ${KEY_PAIR_NAME}.pem ec2-user@<instance-ip>"
echo "- Clean up resources: ./scripts/cleanup.sh"
echo
print_info "For troubleshooting, see docs/TROUBLESHOOTING.md"