#!/bin/bash
# LibreChat CDK Complete Setup and Deployment Script
# This script handles everything from initial setup to deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════╗"
echo "║       LibreChat CDK Setup & Deployment        ║"
echo "║         One-Click Enterprise Setup            ║"
echo "╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

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
    if ! aws sts get-caller-identity &> /dev/null; then
        print_warning "AWS credentials not configured"
        echo "  Run: aws configure"
    else
        AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
        AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
        print_status "AWS Account: $AWS_ACCOUNT, Region: $AWS_REGION"
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

# Check for existing configuration
if [ -f .env ]; then
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
            npm run bootstrap
            
            echo -e "\n${BLUE}🚀 Deploying Stack${NC}"
            npm run deploy
            
            print_status "Deployment complete!"
        else
            echo -e "\n${GREEN}Setup complete! To deploy later, run:${NC}"
            echo "  npm run deploy"
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
# Run 'npm run deploy' to deploy this configuration

# Deployment Settings
DEPLOYMENT_ENV=$DEPLOYMENT_ENV
DEPLOYMENT_MODE=$DEPLOYMENT_MODE
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
    npm run bootstrap
    print_status "CDK bootstrap complete"
    
    # Deploy
    echo -e "\n${BLUE}🚀 Deploying Stack${NC}"
    echo "=================="
    npm run deploy
    
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
    echo "  npm run deploy"
    echo
    echo "To modify configuration:"
    echo "  - Edit .env file"
    echo "  - Run ./setup.sh again"
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
echo
print_info "For troubleshooting, see DEPLOYMENT_GUIDE.md"