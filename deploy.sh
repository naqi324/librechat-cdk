#!/bin/bash
# LibreChat CDK Deployment Script
# Comprehensive deployment tool with multiple modes and options

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
CONFIG="minimal-dev"
ENVIRONMENT="development"
MODE="EC2"
ENABLE_RAG="false"
ENABLE_MEILISEARCH="false"
AUTO_APPROVE=""
SKIP_BUILD=""
VERBOSE=""

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print error and exit
error_exit() {
    print_color "$RED" "❌ Error: $1"
    exit 1
}

# Function to check command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error_exit "$1 is not installed. Please install it first."
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --prod|--production)
            CONFIG="production-ecs"
            ENVIRONMENT="production"
            MODE="ECS"
            ENABLE_RAG="true"
            shift
            ;;
        --staging)
            CONFIG="standard-dev"
            ENVIRONMENT="staging"
            ENABLE_RAG="true"
            shift
            ;;
        --dev|--development)
            CONFIG="minimal-dev"
            ENVIRONMENT="development"
            MODE="EC2"
            shift
            ;;
        --ec2)
            MODE="EC2"
            shift
            ;;
        --ecs)
            MODE="ECS"
            if [ "$CONFIG" = "minimal-dev" ]; then
                CONFIG="production-ecs"
            fi
            shift
            ;;
        --rag)
            ENABLE_RAG="true"
            if [ "$CONFIG" = "minimal-dev" ]; then
                CONFIG="standard-dev"
            fi
            shift
            ;;
        --no-rag)
            ENABLE_RAG="false"
            shift
            ;;
        --meilisearch)
            ENABLE_MEILISEARCH="true"
            shift
            ;;
        --no-meilisearch)
            ENABLE_MEILISEARCH="false"
            shift
            ;;
        --auto-approve|-y)
            AUTO_APPROVE="--require-approval never"
            shift
            ;;
        --skip-build)
            SKIP_BUILD="true"
            shift
            ;;
        --verbose|-v)
            VERBOSE="--verbose"
            shift
            ;;
        --key-pair)
            if [ -z "$2" ] || [[ "$2" == --* ]]; then
                error_exit "--key-pair requires a value"
            fi
            KEY_PAIR_NAME="$2"
            shift 2
            ;;
        --allowed-ips)
            if [ -z "$2" ] || [[ "$2" == --* ]]; then
                error_exit "--allowed-ips requires a value"
            fi
            ALLOWED_IPS="$2"
            shift 2
            ;;
        --domain)
            if [ -z "$2" ] || [[ "$2" == --* ]]; then
                error_exit "--domain requires a value"
            fi
            DOMAIN_NAME="$2"
            shift 2
            ;;
        --certificate-arn)
            if [ -z "$2" ] || [[ "$2" == --* ]]; then
                error_exit "--certificate-arn requires a value"
            fi
            CERTIFICATE_ARN="$2"
            shift 2
            ;;
        --vpc-id)
            if [ -z "$2" ] || [[ "$2" == --* ]]; then
                error_exit "--vpc-id requires a value"
            fi
            EXISTING_VPC_ID="$2"
            shift 2
            ;;
        --alert-email)
            if [ -z "$2" ] || [[ "$2" == --* ]]; then
                error_exit "--alert-email requires a value"
            fi
            ALERT_EMAIL="$2"
            shift 2
            ;;
        --help|-h)
            cat << EOF
LibreChat CDK Deployment Script

Usage: ./deploy.sh [options]

Environment Options:
  --dev, --development  Deploy development environment (default)
  --staging            Deploy staging environment with RAG
  --prod, --production Deploy production environment (ECS + RAG)

Deployment Mode:
  --ec2                Use EC2 deployment mode (default for dev)
  --ecs                Use ECS Fargate deployment mode

Feature Flags:
  --rag                Enable RAG features (PostgreSQL + pgvector)
  --no-rag             Disable RAG features (default for dev)
  --meilisearch        Enable Meilisearch for full-text search
  --no-meilisearch     Disable Meilisearch (default)

Configuration:
  --key-pair NAME      EC2 SSH key pair name (required for EC2 mode)
  --allowed-ips IPS    Comma-separated IPs for SSH access (e.g., 1.2.3.4/32)
  --domain NAME        Custom domain name (e.g., chat.example.com)
  --certificate-arn    ACM certificate ARN for HTTPS
  --vpc-id ID          Use existing VPC instead of creating new one
  --alert-email EMAIL  Email for CloudWatch alerts

Options:
  --auto-approve, -y   Skip confirmation prompts
  --skip-build         Skip TypeScript build (use if already built)
  --verbose, -v        Show detailed CDK output
  --help, -h           Show this help message

Examples:
  # Quick development deployment (minimal cost, no RAG)
  ./deploy.sh --dev --no-rag -y

  # Development with RAG enabled
  ./deploy.sh --dev --rag --key-pair my-key

  # Staging environment
  ./deploy.sh --staging --alert-email ops@example.com

  # Production with custom domain
  ./deploy.sh --prod --domain chat.example.com --certificate-arn arn:aws:acm:...

  # Use existing VPC
  ./deploy.sh --vpc-id vpc-12345 --key-pair my-key

Cost Estimates:
  Dev (no RAG):    ~\$50/month  (t3.medium EC2, no PostgreSQL)
  Dev (with RAG):  ~\$110/month (t3.medium EC2 + RDS PostgreSQL)
  Staging:         ~\$250/month (t3.large EC2 + RDS)
  Production:      ~\$450/month (ECS Fargate + Aurora Serverless)

EOF
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1\nUse --help for usage information"
            ;;
    esac
done

# Header
print_color "$GREEN" "🚀 LibreChat CDK Deployment Script"
echo "======================================"

# Check required commands
check_command "node"
check_command "npm"
check_command "aws"
check_command "jq"

# Check Node.js version
NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    error_exit "Node.js 18+ is required. Current version: $(node -v)"
fi

# Check TypeScript is installed locally
if [ ! -f "node_modules/.bin/tsc" ]; then
    print_color "$YELLOW" "TypeScript not found. Installing dependencies..."
    npm install
fi

# Check AWS CDK is installed
if ! npm list aws-cdk 2>/dev/null | grep -q aws-cdk; then
    print_color "$YELLOW" "AWS CDK not found. Installing..."
    npm install
fi

# Check AWS credentials
print_color "$CYAN" "Checking AWS credentials..."
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    error_exit "AWS credentials not configured. Please run: aws configure"
fi

# Get AWS account information
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=${AWS_REGION:-$(aws configure get region)}

if [ -z "$REGION" ]; then
    error_exit "AWS region not set. Please set AWS_REGION or configure default region"
fi

print_color "$CYAN" "AWS Account: $ACCOUNT_ID"
print_color "$CYAN" "AWS Region:  $REGION"

# Validate production requirements
if [ "$ENVIRONMENT" = "production" ]; then
    if [ "$MODE" = "EC2" ] && [ -z "$ALLOWED_IPS" ]; then
        error_exit "Production EC2 deployments require --allowed-ips to be set for security"
    fi
    if [ -z "$ALERT_EMAIL" ]; then
        print_color "$YELLOW" "⚠️  Warning: No alert email configured for production. Consider setting --alert-email"
    fi
fi

# Handle EC2-specific requirements
if [ "$MODE" = "EC2" ]; then
    # Check or create EC2 key pair
    if [ -z "$KEY_PAIR_NAME" ]; then
        print_color "$YELLOW" "No EC2 key pair specified. Checking for existing keys..."
        
        # List available key pairs
        EXISTING_KEYS=$(aws ec2 describe-key-pairs --query 'KeyPairs[*].KeyName' --output json 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")
        
        if [ -n "$EXISTING_KEYS" ]; then
            print_color "$CYAN" "Found existing key pairs:"
            echo "$EXISTING_KEYS" | head -5 | while read -r key; do
                echo "  - $key"
            done
            
            if [ -z "$AUTO_APPROVE" ]; then
                read -p "Enter key name to use (or press Enter to create new): " KEY_PAIR_NAME
            fi
        fi
        
        # Create new key pair if still not set
        if [ -z "$KEY_PAIR_NAME" ]; then
            KEY_PAIR_NAME="librechat-${ENVIRONMENT}-$(date +%s)"
            print_color "$YELLOW" "Creating new EC2 key pair: $KEY_PAIR_NAME"
            
            aws ec2 create-key-pair \
                --key-name "$KEY_PAIR_NAME" \
                --query 'KeyMaterial' \
                --output text > "${KEY_PAIR_NAME}.pem"
            
            chmod 400 "${KEY_PAIR_NAME}.pem"
            print_color "$GREEN" "✅ Key pair created and saved to: ${KEY_PAIR_NAME}.pem"
            print_color "$YELLOW" "⚠️  Keep this file safe! It's required for SSH access."
        fi
    else
        # Verify key pair exists
        if ! aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" &> /dev/null; then
            error_exit "Key pair '$KEY_PAIR_NAME' not found in region $REGION"
        fi
    fi
    
    export KEY_PAIR_NAME
fi

# Handle SSH access IPs
if [ "$MODE" = "EC2" ] && [ -z "$ALLOWED_IPS" ]; then
    if [ "$ENVIRONMENT" != "production" ]; then
        print_color "$CYAN" "Detecting your public IP for SSH access..."
        MY_IP=$(curl -s https://checkip.amazonaws.com 2>/dev/null || curl -s https://ipinfo.io/ip 2>/dev/null || echo "")
        
        if [ -n "$MY_IP" ]; then
            ALLOWED_IPS="$MY_IP/32"
            print_color "$GREEN" "✅ Your IP ($MY_IP) will be allowed for SSH access"
        else
            print_color "$YELLOW" "⚠️  Could not detect public IP. Using private IP ranges only."
            ALLOWED_IPS="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
        fi
    fi
fi

# Export environment variables for CDK
[ -n "$ALLOWED_IPS" ] && export ALLOWED_IPS
[ -n "$ALERT_EMAIL" ] && export ALERT_EMAIL
[ -n "$DOMAIN_NAME" ] && export DOMAIN_NAME
[ -n "$CERTIFICATE_ARN" ] && export CERTIFICATE_ARN
[ -n "$EXISTING_VPC_ID" ] && export EXISTING_VPC_ID

# Check if CDK is bootstrapped
print_color "$CYAN" "Checking CDK bootstrap status..."
if ! aws cloudformation describe-stacks \
    --stack-name CDKToolkit \
    --region "$REGION" &> /dev/null; then
    
    print_color "$YELLOW" "CDK not bootstrapped. Bootstrapping now..."
    npx cdk bootstrap "aws://$ACCOUNT_ID/$REGION" $VERBOSE
    print_color "$GREEN" "✅ CDK bootstrap complete"
fi

# Display deployment configuration
echo ""
print_color "$BLUE" "Deployment Configuration:"
print_color "$CYAN" "  Environment:     $ENVIRONMENT"
print_color "$CYAN" "  Mode:           $MODE"
print_color "$CYAN" "  Config Preset:  $CONFIG"
print_color "$CYAN" "  RAG Enabled:    $ENABLE_RAG"
print_color "$CYAN" "  Meilisearch:    $ENABLE_MEILISEARCH"

if [ "$MODE" = "EC2" ]; then
    print_color "$CYAN" "  EC2 Key Pair:   $KEY_PAIR_NAME"
    print_color "$CYAN" "  SSH Access:     ${ALLOWED_IPS:-Not configured}"
fi

if [ -n "$DOMAIN_NAME" ]; then
    print_color "$CYAN" "  Domain:         $DOMAIN_NAME"
fi

if [ -n "$EXISTING_VPC_ID" ]; then
    print_color "$CYAN" "  VPC:            $EXISTING_VPC_ID (existing)"
fi

# Estimate costs
echo ""
print_color "$BLUE" "Estimated Monthly Costs:"
if [ "$MODE" = "EC2" ]; then
    if [ "$ENABLE_RAG" = "true" ]; then
        print_color "$YELLOW" "  ~\$110-250 (EC2 + RDS PostgreSQL)"
    else
        print_color "$YELLOW" "  ~\$50-100 (EC2 only)"
    fi
else
    print_color "$YELLOW" "  ~\$450-600 (ECS Fargate + Aurora)"
fi

# Confirm deployment
if [ -z "$AUTO_APPROVE" ]; then
    echo ""
    read -p "$(print_color "$YELLOW" "Deploy with these settings? (y/n): ")" -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_color "$RED" "Deployment cancelled"
        exit 0
    fi
fi

# Build TypeScript if not skipped
if [ -z "$SKIP_BUILD" ]; then
    echo ""
    print_color "$YELLOW" "Building TypeScript..."
    npm run build
    print_color "$GREEN" "✅ Build complete"
else
    print_color "$CYAN" "Skipping build (--skip-build flag set)"
fi

# Prepare CDK context parameters
CDK_CONTEXT=""
CDK_CONTEXT="$CDK_CONTEXT -c configSource=$CONFIG"
CDK_CONTEXT="$CDK_CONTEXT -c environment=$ENVIRONMENT"
CDK_CONTEXT="$CDK_CONTEXT -c deploymentMode=$MODE"
CDK_CONTEXT="$CDK_CONTEXT -c enableRag=$ENABLE_RAG"
CDK_CONTEXT="$CDK_CONTEXT -c enableMeilisearch=$ENABLE_MEILISEARCH"

[ -n "$KEY_PAIR_NAME" ] && CDK_CONTEXT="$CDK_CONTEXT -c keyPairName=$KEY_PAIR_NAME"
[ -n "$ALLOWED_IPS" ] && CDK_CONTEXT="$CDK_CONTEXT -c allowedIps=$ALLOWED_IPS"
[ -n "$ALERT_EMAIL" ] && CDK_CONTEXT="$CDK_CONTEXT -c alertEmail=$ALERT_EMAIL"
[ -n "$DOMAIN_NAME" ] && CDK_CONTEXT="$CDK_CONTEXT -c domainName=$DOMAIN_NAME"
[ -n "$CERTIFICATE_ARN" ] && CDK_CONTEXT="$CDK_CONTEXT -c certificateArn=$CERTIFICATE_ARN"
[ -n "$EXISTING_VPC_ID" ] && CDK_CONTEXT="$CDK_CONTEXT -c existingVpcId=$EXISTING_VPC_ID"

# Run CDK diff if not auto-approved
if [ -z "$AUTO_APPROVE" ] && [ -z "$SKIP_BUILD" ]; then
    print_color "$CYAN" "Checking what will be deployed..."
    npx cdk diff $CDK_CONTEXT 2>&1 | head -50
    echo "..."
    echo ""
fi

# Deploy with CDK
echo ""
print_color "$YELLOW" "Starting deployment..."
print_color "$CYAN" "This may take 15-30 minutes for initial deployment..."

# Run CDK deploy with proper error handling
if npx cdk deploy $CDK_CONTEXT $AUTO_APPROVE $VERBOSE; then
    DEPLOYMENT_SUCCESS=true
else
    DEPLOYMENT_SUCCESS=false
    print_color "$RED" "❌ Deployment failed"
    exit 1
fi

# Get stack outputs
if [ "$DEPLOYMENT_SUCCESS" = true ]; then
    STACK_NAME="LibreChatStack-${ENVIRONMENT}"
    
    echo ""
    print_color "$GREEN" "✅ Deployment Complete!"
    echo ""
    
    # Get and display the application URL
    APP_URL=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerUrl'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$APP_URL" ]; then
        print_color "$GREEN" "🌐 Application URL: $APP_URL"
        echo ""
    fi
    
    # For EC2 deployments, show SSH instructions
    if [ "$MODE" = "EC2" ]; then
        INSTANCE_ID=$(aws cloudformation describe-stack-resources \
            --stack-name "$STACK_NAME" \
            --query "StackResources[?ResourceType=='AWS::EC2::Instance'].PhysicalResourceId" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$INSTANCE_ID" ]; then
            INSTANCE_IP=$(aws ec2 describe-instances \
                --instance-ids "$INSTANCE_ID" \
                --query "Reservations[0].Instances[0].PublicIpAddress" \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$INSTANCE_IP" ]; then
                print_color "$BLUE" "SSH Access:"
                print_color "$CYAN" "  ssh -i ${KEY_PAIR_NAME}.pem ec2-user@${INSTANCE_IP}"
                echo ""
                
                print_color "$BLUE" "View Logs:"
                print_color "$CYAN" "  ssh -i ${KEY_PAIR_NAME}.pem ec2-user@${INSTANCE_IP} 'sudo docker compose logs -f'"
                echo ""
            fi
        fi
    fi
    
    # Show monitoring commands
    print_color "$BLUE" "Useful Commands:"
    print_color "$CYAN" "  Monitor CloudWatch logs:"
    print_color "$WHITE" "    aws logs tail /aws/librechat --follow"
    print_color "$CYAN" "  Update deployment:"
    print_color "$WHITE" "    ./deploy.sh ${*}"
    print_color "$CYAN" "  Show stack outputs:"
    print_color "$WHITE" "    aws cloudformation describe-stacks --stack-name $STACK_NAME"
    print_color "$CYAN" "  Destroy stack:"
    print_color "$WHITE" "    cdk destroy $CDK_CONTEXT"
    echo ""
    
    # Show post-deployment setup reminders
    if [ "$ENABLE_RAG" = "true" ]; then
        print_color "$YELLOW" "📝 RAG is enabled. The PostgreSQL database will initialize on first run."
    fi
    
    print_color "$YELLOW" "⏱️  Note: It may take 5-10 minutes for the application to be fully ready."
    print_color "$YELLOW" "    Check $APP_URL/health for status."
fi