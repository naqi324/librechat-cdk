#!/bin/bash
# setup-environment.sh - Set up and validate environment for LibreChat CDK deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Script version
VERSION="2.0.0"

# Default values
DEFAULT_REGION="us-east-1"
DEFAULT_ENVIRONMENT="development"
NODE_MIN_VERSION="18.0.0"
CDK_MIN_VERSION="2.150.0"

# Banner
show_banner() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║         LibreChat CDK Environment Setup v${VERSION}              ║"
    echo "║                                                                ║"
    echo "║  This script will help you set up your environment for        ║"
    echo "║  deploying LibreChat on AWS                                   ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Compare semantic versions
version_compare() {
    local version1=$1
    local version2=$2
    
    if [[ "$version1" == "$version2" ]]; then
        return 0
    fi
    
    local IFS=.
    local i ver1=($version1) ver2=($version2)
    
    # Fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2
        fi
    done
    
    return 0
}

# Install Node.js
install_nodejs() {
    echo -e "${YELLOW}Installing Node.js...${NC}"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command_exists brew; then
            brew install node@18
        else
            echo -e "${RED}Homebrew not found. Please install Homebrew first.${NC}"
            echo "Visit: https://brew.sh"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        sudo apt-get install -y nodejs
    else
        echo -e "${RED}Unsupported operating system: $OSTYPE${NC}"
        exit 1
    fi
}

# Install AWS CLI
install_aws_cli() {
    echo -e "${YELLOW}Installing AWS CLI...${NC}"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command_exists brew; then
            brew install awscli
        else
            curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
            sudo installer -pkg AWSCLIV2.pkg -target /
            rm AWSCLIV2.pkg
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        sudo ./aws/install
        rm -rf aws awscliv2.zip
    fi
}

# Check prerequisites
check_prerequisites() {
    echo -e "${BLUE}Checking prerequisites...${NC}\n"
    
    local missing_deps=false
    
    # Check Node.js
    if command_exists node; then
        NODE_VERSION=$(node --version | sed 's/v//')
        version_compare "$NODE_VERSION" "$NODE_MIN_VERSION"
        if [[ $? -eq 2 ]]; then
            echo -e "${YELLOW}⚠ Node.js version $NODE_VERSION is below minimum required version $NODE_MIN_VERSION${NC}"
            read -p "Would you like to install/update Node.js? (y/n): " install_node
            if [[ "$install_node" == "y" ]]; then
                install_nodejs
            else
                missing_deps=true
            fi
        else
            echo -e "${GREEN}✓ Node.js $NODE_VERSION${NC}"
        fi
    else
        echo -e "${RED}✗ Node.js not found${NC}"
        read -p "Would you like to install Node.js? (y/n): " install_node
        if [[ "$install_node" == "y" ]]; then
            install_nodejs
        else
            missing_deps=true
        fi
    fi
    
    # Check npm
    if command_exists npm; then
        NPM_VERSION=$(npm --version)
        echo -e "${GREEN}✓ npm $NPM_VERSION${NC}"
    else
        echo -e "${RED}✗ npm not found${NC}"
        missing_deps=true
    fi
    
    # Check AWS CLI
    if command_exists aws; then
        AWS_VERSION=$(aws --version | cut -d' ' -f1 | cut -d'/' -f2)
        echo -e "${GREEN}✓ AWS CLI $AWS_VERSION${NC}"
    else
        echo -e "${RED}✗ AWS CLI not found${NC}"
        read -p "Would you like to install AWS CLI? (y/n): " install_aws
        if [[ "$install_aws" == "y" ]]; then
            install_aws_cli
        else
            missing_deps=true
        fi
    fi
    
    # Check Docker
    if command_exists docker; then
        DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | sed 's/,//')
        echo -e "${GREEN}✓ Docker $DOCKER_VERSION${NC}"
        
        # Check if Docker is running
        if ! docker info >/dev/null 2>&1; then
            echo -e "${YELLOW}⚠ Docker is installed but not running${NC}"
            echo "  Please start Docker Desktop"
        fi
    else
        echo -e "${YELLOW}⚠ Docker not found (optional but recommended)${NC}"
    fi
    
    # Check CDK
    if command_exists cdk; then
        CDK_VERSION=$(cdk --version | cut -d' ' -f1)
        version_compare "$CDK_VERSION" "$CDK_MIN_VERSION"
        if [[ $? -eq 2 ]]; then
            echo -e "${YELLOW}⚠ AWS CDK version $CDK_VERSION is below minimum required version $CDK_MIN_VERSION${NC}"
            echo "  Run: npm install -g aws-cdk@latest"
        else
            echo -e "${GREEN}✓ AWS CDK $CDK_VERSION${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ AWS CDK not installed${NC}"
        echo "  Will be installed locally with npm install"
    fi
    
    if [ "$missing_deps" = true ]; then
        echo -e "\n${RED}Please install missing dependencies before continuing.${NC}"
        exit 1
    fi
    
    echo -e "\n${GREEN}All required prerequisites satisfied!${NC}"
}

# Configure AWS credentials
configure_aws() {
    echo -e "\n${BLUE}Configuring AWS credentials...${NC}"
    
    # Check if credentials are already configured
    if aws sts get-caller-identity >/dev/null 2>&1; then
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        CURRENT_REGION=$(aws configure get region)
        PROFILE=$(aws configure get profile 2>/dev/null || echo "default")
        
        echo -e "${GREEN}✓ AWS credentials already configured${NC}"
        echo "  Account: $ACCOUNT_ID"
        echo "  Region: $CURRENT_REGION"
        echo "  Profile: $PROFILE"
        
        read -p "Would you like to reconfigure? (y/n): " reconfigure
        if [[ "$reconfigure" != "y" ]]; then
            return
        fi
    fi
    
    # Configure AWS
    echo -e "\n${YELLOW}Please enter your AWS credentials:${NC}"
    aws configure
}

# Check AWS services
check_aws_services() {
    echo -e "\n${BLUE}Checking AWS service availability...${NC}"
    
    REGION=$(aws configure get region || echo $DEFAULT_REGION)
    
    # Check Bedrock access
    echo -n "Checking Bedrock access... "
    if aws bedrock list-foundation-models --region "$REGION" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        
        # Check for Claude models
        CLAUDE_MODELS=$(aws bedrock list-foundation-models --region "$REGION" --query 'modelSummaries[?contains(modelId, `claude`)].modelId' --output text 2>/dev/null)
        if [ -n "$CLAUDE_MODELS" ]; then
            echo -e "  ${GREEN}✓ Claude models available${NC}"
        else
            echo -e "  ${YELLOW}⚠ Claude models not found. Please request access in AWS Console${NC}"
            echo "    Visit: https://console.aws.amazon.com/bedrock/"
        fi
    else
        echo -e "${YELLOW}⚠${NC}"
        echo "  Bedrock might not be enabled or available in region $REGION"
        echo "  Visit: https://console.aws.amazon.com/bedrock/"
    fi
    
    # Check for existing key pairs
    echo -n "Checking EC2 key pairs... "
    KEY_PAIRS=$(aws ec2 describe-key-pairs --query 'KeyPairs[*].KeyName' --output text 2>/dev/null)
    if [ -n "$KEY_PAIRS" ]; then
        echo -e "${GREEN}✓${NC}"
        echo "  Available key pairs: $(echo $KEY_PAIRS | tr '\t' ', ')"
    else
        echo -e "${YELLOW}⚠${NC}"
        echo "  No key pairs found. You'll need to create one for EC2 deployments"
        read -p "  Would you like to create a key pair now? (y/n): " create_key
        if [[ "$create_key" == "y" ]]; then
            read -p "  Enter key pair name: " key_name
            aws ec2 create-key-pair --key-name "$key_name" --query 'KeyMaterial' --output text > "${key_name}.pem"
            chmod 400 "${key_name}.pem"
            echo -e "  ${GREEN}✓ Created key pair: $key_name${NC}"
            echo "  Private key saved to: ${key_name}.pem"
        fi
    fi
    
    # Check VPC quota
    echo -n "Checking VPC quota... "
    VPC_COUNT=$(aws ec2 describe-vpcs --query 'length(Vpcs)' --output text 2>/dev/null)
    VPC_QUOTA=$(aws service-quotas get-service-quota --service-code vpc --quota-code L-F678F1CE --query 'Quota.Value' --output text 2>/dev/null || echo "5")
    if [ "$VPC_COUNT" -lt "$VPC_QUOTA" ]; then
        echo -e "${GREEN}✓${NC} ($VPC_COUNT/$VPC_QUOTA used)"
    else
        echo -e "${YELLOW}⚠${NC} ($VPC_COUNT/$VPC_QUOTA used)"
        echo "  You might need to delete unused VPCs or request a quota increase"
    fi
}

# Create environment file
create_env_file() {
    echo -e "\n${BLUE}Creating environment configuration...${NC}"
    
    ENV_FILE=".env.librechat"
    
    # Gather information
    read -p "Environment name (development/staging/production) [$DEFAULT_ENVIRONMENT]: " ENVIRONMENT
    ENVIRONMENT=${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}
    
    read -p "AWS Region [$DEFAULT_REGION]: " REGION
    REGION=${REGION:-$DEFAULT_REGION}
    
    read -p "Deployment mode (EC2/ECS) [EC2]: " DEPLOYMENT_MODE
    DEPLOYMENT_MODE=${DEPLOYMENT_MODE:-EC2}
    
    if [[ "$DEPLOYMENT_MODE" == "EC2" ]]; then
        read -p "EC2 key pair name: " KEY_PAIR_NAME
        if [ -z "$KEY_PAIR_NAME" ]; then
            echo -e "${RED}Key pair name is required for EC2 deployments${NC}"
            return 1
        fi
    fi
    
    read -p "Alert email (optional): " ALERT_EMAIL
    
    # Advanced options
    read -p "Configure advanced options? (y/n) [n]: " advanced
    if [[ "$advanced" == "y" ]]; then
        read -p "Enable RAG (y/n) [y]: " enable_rag
        ENABLE_RAG=${enable_rag:-y}
        
        read -p "Enable Meilisearch (y/n) [n]: " enable_meilisearch
        ENABLE_MEILISEARCH=${enable_meilisearch:-n}
        
        read -p "Custom VPC CIDR (leave empty for default): " VPC_CIDR
        
        read -p "Use existing VPC? (y/n) [n]: " use_existing_vpc
        if [[ "$use_existing_vpc" == "y" ]]; then
            read -p "Existing VPC ID: " EXISTING_VPC_ID
        fi
    else
        ENABLE_RAG="y"
        ENABLE_MEILISEARCH="n"
    fi
    
    # Create .env file
    cat > "$ENV_FILE" << EOF
# LibreChat CDK Environment Configuration
# Generated on $(date)

# Deployment Settings
DEPLOYMENT_ENV=$ENVIRONMENT
DEPLOYMENT_MODE=$DEPLOYMENT_MODE
AWS_REGION=$REGION

# Security
KEY_PAIR_NAME=$KEY_PAIR_NAME
ALLOWED_IPS=$(curl -s https://checkip.amazonaws.com)/32

# Monitoring
ALERT_EMAIL=$ALERT_EMAIL

# Features
ENABLE_RAG=$ENABLE_RAG
ENABLE_MEILISEARCH=$ENABLE_MEILISEARCH

# Network Configuration
${VPC_CIDR:+VPC_CIDR=$VPC_CIDR}
${EXISTING_VPC_ID:+EXISTING_VPC_ID=$EXISTING_VPC_ID}

# Container Images (defaults)
LIBRECHAT_IMAGE=ghcr.io/danny-avila/librechat:latest
RAG_API_IMAGE=ghcr.io/danny-avila/librechat-rag-api-dev:latest
MEILISEARCH_IMAGE=getmeili/meilisearch:v1.6

# Domain Configuration (optional)
# DOMAIN_NAME=librechat.example.com
# CERTIFICATE_ARN=arn:aws:acm:region:account:certificate/id
# HOSTED_ZONE_ID=Z1234567890ABC
EOF
    
    echo -e "\n${GREEN}✓ Environment configuration saved to $ENV_FILE${NC}"
    echo -e "${YELLOW}Note: You can edit this file to customize your deployment${NC}"
}

# Install project dependencies
install_dependencies() {
    echo -e "\n${BLUE}Installing project dependencies...${NC}"
    
    if [ -f "package.json" ]; then
        npm install
        echo -e "${GREEN}✓ Dependencies installed${NC}"
    else
        echo -e "${RED}package.json not found. Are you in the project directory?${NC}"
        exit 1
    fi
}

# Bootstrap CDK
bootstrap_cdk() {
    echo -e "\n${BLUE}Checking CDK bootstrap status...${NC}"
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region || echo $DEFAULT_REGION)
    
    # Check if already bootstrapped
    if aws cloudformation describe-stacks --stack-name CDKToolkit --region "$REGION" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ CDK already bootstrapped${NC}"
    else
        echo -e "${YELLOW}CDK needs to be bootstrapped${NC}"
        read -p "Bootstrap CDK now? (y/n): " bootstrap
        if [[ "$bootstrap" == "y" ]]; then
            npx cdk bootstrap "aws://$ACCOUNT_ID/$REGION"
            echo -e "${GREEN}✓ CDK bootstrapped successfully${NC}"
        fi
    fi
}

# Generate deployment script
generate_deployment_script() {
    echo -e "\n${BLUE}Generating deployment script...${NC}"
    
    if [ -f ".env.librechat" ]; then
        # Source the environment file
        source .env.librechat
        
        DEPLOY_SCRIPT="deploy-librechat.sh"
        
        cat > "$DEPLOY_SCRIPT" << 'EOF'
#!/bin/bash
# Auto-generated deployment script for LibreChat

set -e

# Load environment
if [ -f .env.librechat ]; then
    source .env.librechat
else
    echo "Environment file not found. Run setup-environment.sh first."
    exit 1
fi

# Export AWS region
export AWS_DEFAULT_REGION=$AWS_REGION

# Build project
echo "Building project..."
npm run build

# Deploy
echo "Deploying LibreChat..."
EOF
        
        # Add deployment command based on mode
        if [[ "$DEPLOYMENT_MODE" == "EC2" ]]; then
            cat >> "$DEPLOY_SCRIPT" << EOF
npx cdk deploy \\
    -c configSource=custom \\
    -c environment=\$DEPLOYMENT_ENV \\
    -c deploymentMode=\$DEPLOYMENT_MODE \\
    -c keyPairName=\$KEY_PAIR_NAME \\
    -c alertEmail=\$ALERT_EMAIL \\
    -c allowedIps=\$ALLOWED_IPS \\
    -c enableRag=\$([ "\$ENABLE_RAG" == "y" ] && echo "true" || echo "false") \\
    -c enableMeilisearch=\$([ "\$ENABLE_MEILISEARCH" == "y" ] && echo "true" || echo "false") \\
    --require-approval never
EOF
        else
            cat >> "$DEPLOY_SCRIPT" << EOF
npx cdk deploy \\
    -c configSource=custom \\
    -c environment=\$DEPLOYMENT_ENV \\
    -c deploymentMode=\$DEPLOYMENT_MODE \\
    -c alertEmail=\$ALERT_EMAIL \\
    -c enableRag=\$([ "\$ENABLE_RAG" == "y" ] && echo "true" || echo "false") \\
    -c enableMeilisearch=\$([ "\$ENABLE_MEILISEARCH" == "y" ] && echo "true" || echo "false") \\
    --require-approval never
EOF
        fi
        
        chmod +x "$DEPLOY_SCRIPT"
        echo -e "${GREEN}✓ Deployment script generated: $DEPLOY_SCRIPT${NC}"
    fi
}

# Summary
show_summary() {
    echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    Setup Complete! 🎉                          ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "\n${BLUE}Next Steps:${NC}"
    echo "1. Review and edit .env.librechat if needed"
    echo "2. Run the deployment:"
    echo "   - Interactive: ${PURPLE}npm run wizard${NC}"
    echo "   - Direct: ${PURPLE}./deploy-librechat.sh${NC}"
    echo "   - Manual: ${PURPLE}npm run deploy${NC}"
    
    echo -e "\n${BLUE}Useful Commands:${NC}"
    echo "- Check what will be deployed: ${PURPLE}npm run diff${NC}"
    echo "- Estimate costs: ${PURPLE}npm run estimate-cost${NC}"
    echo "- View all stacks: ${PURPLE}npx cdk list${NC}"
    echo "- Destroy resources: ${PURPLE}npm run destroy${NC}"
    
    echo -e "\n${BLUE}Documentation:${NC}"
    echo "- README.md - General information"
    echo "- docs/deployment-guide.md - Detailed deployment instructions"
    echo "- docs/configuration.md - Configuration options"
    echo "- docs/troubleshooting.md - Common issues and solutions"
    
    echo -e "\n${YELLOW}Remember:${NC}"
    echo "- AWS resources will incur costs"
    echo "- Review security groups and access permissions"
    echo "- Set up monitoring and alerts"
    echo "- Regular backups are recommended"
}

# Main execution
main() {
    show_banner
    
    # Check if we're in the right directory
    if [ ! -f "package.json" ] || [ ! -d "lib" ]; then
        echo -e "${RED}Error: This script must be run from the LibreChat CDK project root${NC}"
        exit 1
    fi
    
    check_prerequisites
    configure_aws
    check_aws_services
    create_env_file
    install_dependencies
    bootstrap_cdk
    generate_deployment_script
    show_summary
}

# Run main function
main "$@"
