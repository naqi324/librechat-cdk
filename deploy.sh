#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
CONFIG="minimal-dev"
ENVIRONMENT="development"
MODE="EC2"
ENABLE_RAG="false"
AUTO_APPROVE=""

# Parse arguments
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
      shift
      ;;
    --ecs)
      MODE="ECS"
      CONFIG="production-ecs"
      shift
      ;;
    --rag)
      ENABLE_RAG="true"
      CONFIG="standard-dev"
      shift
      ;;
    --no-rag)
      ENABLE_RAG="false"
      shift
      ;;
    --auto-approve|-y)
      AUTO_APPROVE="--require-approval never"
      shift
      ;;
    --key-pair)
      KEY_PAIR_NAME="$2"
      shift 2
      ;;
    --allowed-ips)
      ALLOWED_IPS="$2"
      shift 2
      ;;
    --help|-h)
      echo "LibreChat CDK Deployment"
      echo ""
      echo "Usage: ./deploy.sh [options]"
      echo ""
      echo "Options:"
      echo "  --dev, --development  Deploy development environment (default)"
      echo "  --staging            Deploy staging environment"
      echo "  --prod, --production Deploy production environment"
      echo "  --ecs                Use ECS deployment mode"
      echo "  --rag                Enable RAG features"
      echo "  --no-rag             Disable RAG features (default)"
      echo "  --auto-approve, -y   Skip confirmation prompts"
      echo "  --key-pair NAME      EC2 key pair name"
      echo "  --allowed-ips IPS    Comma-separated IPs for SSH access"
      echo "  --help, -h           Show this help message"
      echo ""
      echo "Examples:"
      echo "  ./deploy.sh                    # Quick dev deployment"
      echo "  ./deploy.sh --prod             # Production deployment"
      echo "  ./deploy.sh --rag --staging    # Staging with RAG"
      echo "  ./deploy.sh -y --key-pair mykey  # Auto-approve with specific key"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

echo -e "${GREEN}🚀 LibreChat CDK Deployment${NC}"
echo "======================================"

# Check AWS credentials
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo -e "${RED}❌ AWS credentials not configured${NC}"
    echo "Please configure AWS CLI: aws configure"
    exit 1
fi

# Get AWS account info
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=${AWS_REGION:-$(aws configure get region)}

echo -e "Account: ${YELLOW}$ACCOUNT_ID${NC}"
echo -e "Region:  ${YELLOW}$REGION${NC}"

# Handle EC2 key pair for EC2 deployments
if [ "$MODE" = "EC2" ]; then
    if [ -z "$KEY_PAIR_NAME" ]; then
        # Check if any key pairs exist
        EXISTING_KEYS=$(aws ec2 describe-key-pairs --query 'KeyPairs[0].KeyName' --output text 2>/dev/null || echo "")
        
        if [ -n "$EXISTING_KEYS" ] && [ "$EXISTING_KEYS" != "None" ]; then
            echo -e "${YELLOW}Found existing key pair: $EXISTING_KEYS${NC}"
            read -p "Use this key? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                KEY_PAIR_NAME="$EXISTING_KEYS"
            fi
        fi
        
        # Create new key if still not set
        if [ -z "$KEY_PAIR_NAME" ]; then
            KEY_PAIR_NAME="librechat-$(date +%s)"
            echo -e "${YELLOW}Creating new key pair: $KEY_PAIR_NAME${NC}"
            aws ec2 create-key-pair --key-name "$KEY_PAIR_NAME" --query 'KeyMaterial' --output text > "$KEY_PAIR_NAME.pem"
            chmod 400 "$KEY_PAIR_NAME.pem"
            echo -e "${GREEN}✅ Key saved to: $KEY_PAIR_NAME.pem${NC}"
        fi
    fi
    export KEY_PAIR_NAME
fi

# Handle SSH access IPs
if [ -z "$ALLOWED_IPS" ] && [ "$MODE" = "EC2" ]; then
    if [ "$ENVIRONMENT" = "production" ]; then
        echo -e "${RED}Production requires explicit ALLOWED_IPS${NC}"
        echo "Use --allowed-ips YOUR_IP/32"
        exit 1
    else
        # Dev/staging: try to detect current IP
        MY_IP=$(curl -s https://checkip.amazonaws.com 2>/dev/null || echo "")
        if [ -n "$MY_IP" ]; then
            ALLOWED_IPS="$MY_IP/32"
            echo -e "${GREEN}✅ Your IP ($MY_IP) will be allowed for SSH${NC}"
        fi
    fi
fi
[ -n "$ALLOWED_IPS" ] && export ALLOWED_IPS

# Bootstrap CDK if needed
if ! aws cloudformation describe-stacks --stack-name CDKToolkit --region "$REGION" > /dev/null 2>&1; then
    echo -e "${YELLOW}Bootstrapping CDK...${NC}"
    npx cdk bootstrap "aws://$ACCOUNT_ID/$REGION"
fi

# Display deployment configuration
echo ""
echo "Configuration:"
echo -e "  Environment: ${YELLOW}$ENVIRONMENT${NC}"
echo -e "  Mode:        ${YELLOW}$MODE${NC}"
echo -e "  Config:      ${YELLOW}$CONFIG${NC}"
echo -e "  RAG:         ${YELLOW}$ENABLE_RAG${NC}"
[ "$MODE" = "EC2" ] && echo -e "  Key Pair:    ${YELLOW}$KEY_PAIR_NAME${NC}"
[ -n "$ALLOWED_IPS" ] && echo -e "  SSH Access:  ${YELLOW}$ALLOWED_IPS${NC}"

# Confirm deployment
if [ -z "$AUTO_APPROVE" ]; then
    echo ""
    read -p "Deploy with these settings? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled"
        exit 0
    fi
fi

# Build TypeScript
echo ""
echo -e "${YELLOW}Building...${NC}"
npm run build

# Deploy
echo -e "${YELLOW}Deploying...${NC}"
npx cdk deploy \
    -c configSource="$CONFIG" \
    -c environment="$ENVIRONMENT" \
    -c deploymentMode="$MODE" \
    -c enableRag="$ENABLE_RAG" \
    ${KEY_PAIR_NAME:+-c keyPairName="$KEY_PAIR_NAME"} \
    $AUTO_APPROVE

# Get outputs
STACK_NAME="LibreChatStack-$ENVIRONMENT"
echo ""
echo -e "${GREEN}✅ Deployment Complete!${NC}"
echo ""

# Show URL
URL=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerUrl'].OutputValue" \
    --output text 2>/dev/null || echo "")

if [ -n "$URL" ]; then
    echo -e "🌐 URL: ${GREEN}$URL${NC}"
fi

# Show SSH instructions for EC2
if [ "$MODE" = "EC2" ] && [ -n "$KEY_PAIR_NAME" ]; then
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
            echo -e "🔐 SSH: ${GREEN}ssh -i $KEY_PAIR_NAME.pem ec2-user@$INSTANCE_IP${NC}"
        fi
    fi
fi

echo ""
echo "Next steps:"
echo "  - Monitor: aws logs tail /aws/librechat --follow"
echo "  - Update:  ./deploy.sh [same options]"
echo "  - Destroy: cdk destroy"