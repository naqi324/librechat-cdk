#!/bin/bash

# Script to create an EC2 instance for CDK deployments without token expiration
# This instance uses IAM roles instead of temporary credentials

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 EC2 CDK Deployment Instance Setup${NC}"
echo "====================================="
echo "This script will create an EC2 instance with IAM role for CDK deployments"
echo "No token expiration issues!"
echo

# Configuration
INSTANCE_NAME="LibreChat-CDK-Deployer"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.medium}"
KEY_NAME="${KEY_NAME:-}"
REGION="${AWS_REGION:-us-east-1}"
VPC_ID="${VPC_ID:-}"
SUBNET_ID="${SUBNET_ID:-}"

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI not found. Please install it first.${NC}"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ AWS credentials not configured or expired.${NC}"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✅ AWS Account: $ACCOUNT_ID${NC}"

# Get or create key pair
if [ -z "$KEY_NAME" ]; then
    echo -e "\n${YELLOW}No SSH key specified.${NC}"
    echo "Options:"
    echo "1) Create new key pair"
    echo "2) Use existing key pair"
    echo "3) Skip SSH access (use Session Manager)"
    read -p "Choose option (1-3): " key_option
    
    case $key_option in
        1)
            KEY_NAME="librechat-deployer-$(date +%s)"
            echo -e "${BLUE}Creating new key pair: $KEY_NAME${NC}"
            aws ec2 create-key-pair --key-name $KEY_NAME --query 'KeyMaterial' --output text > ${KEY_NAME}.pem
            chmod 400 ${KEY_NAME}.pem
            echo -e "${GREEN}✅ Key saved to ${KEY_NAME}.pem${NC}"
            ;;
        2)
            read -p "Enter existing key pair name: " KEY_NAME
            ;;
        3)
            echo -e "${YELLOW}Proceeding without SSH key (Session Manager only)${NC}"
            KEY_NAME=""
            ;;
    esac
fi

# Get VPC and Subnet
if [ -z "$VPC_ID" ]; then
    echo -e "\n${BLUE}Selecting VPC...${NC}"
    # Get default VPC
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
    
    if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
        # List available VPCs
        echo "Available VPCs:"
        aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0],CidrBlock]' --output table
        read -p "Enter VPC ID: " VPC_ID
    else
        echo -e "${GREEN}✅ Using default VPC: $VPC_ID${NC}"
    fi
fi

if [ -z "$SUBNET_ID" ]; then
    echo -e "\n${BLUE}Selecting subnet...${NC}"
    # Get first public subnet
    SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
        --query 'Subnets[0].SubnetId' --output text 2>/dev/null)
    
    if [ "$SUBNET_ID" = "None" ] || [ -z "$SUBNET_ID" ]; then
        # List available subnets
        echo "Available subnets in VPC $VPC_ID:"
        aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
            --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,MapPublicIpOnLaunch]' --output table
        read -p "Enter Subnet ID: " SUBNET_ID
    else
        echo -e "${GREEN}✅ Using subnet: $SUBNET_ID${NC}"
    fi
fi

# Create IAM role for EC2
echo -e "\n${BLUE}Creating IAM role for deployment instance...${NC}"

ROLE_NAME="LibreChatCDKDeploymentRole"
INSTANCE_PROFILE_NAME="LibreChatCDKDeploymentProfile"

# Create trust policy
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create role (ignore error if exists)
aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document file://trust-policy.json \
    --description "Role for LibreChat CDK deployment EC2 instance" 2>/dev/null || echo "Role already exists"

# Attach necessary policies
echo -e "${BLUE}Attaching IAM policies...${NC}"
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/PowerUserAccess 2>/dev/null || true

# Create instance profile (ignore error if exists)
aws iam create-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME 2>/dev/null || echo "Instance profile already exists"
aws iam add-role-to-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME --role-name $ROLE_NAME 2>/dev/null || true

# Clean up
rm -f trust-policy.json

echo -e "${GREEN}✅ IAM role configured${NC}"

# Create security group
echo -e "\n${BLUE}Creating security group...${NC}"
SG_NAME="librechat-cdk-deployer-sg"

# Check if security group exists
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)

if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
    # Create new security group
    SG_ID=$(aws ec2 create-security-group \
        --group-name $SG_NAME \
        --description "Security group for LibreChat CDK deployment instance" \
        --vpc-id $VPC_ID \
        --query 'GroupId' --output text)
    
    # Add SSH rule if using key
    if [ -n "$KEY_NAME" ]; then
        # Get current IP
        MY_IP=$(curl -s https://checkip.amazonaws.com)
        echo -e "${BLUE}Adding SSH access from your IP: $MY_IP${NC}"
        aws ec2 authorize-security-group-ingress \
            --group-id $SG_ID \
            --protocol tcp \
            --port 22 \
            --cidr ${MY_IP}/32 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✅ Security group created: $SG_ID${NC}"
else
    echo -e "${GREEN}✅ Using existing security group: $SG_ID${NC}"
fi

# Get latest Amazon Linux 2023 AMI
echo -e "\n${BLUE}Finding latest Amazon Linux 2023 AMI...${NC}"
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters \
        "Name=name,Values=al2023-ami-*-x86_64" \
        "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text)

echo -e "${GREEN}✅ Using AMI: $AMI_ID${NC}"

# Create user data script
echo -e "\n${BLUE}Creating user data script...${NC}"
cat > user-data.sh <<'EOF'
#!/bin/bash
# User data script for CDK deployment instance

# Update system
dnf update -y

# Install dependencies
dnf install -y git

# Install Node.js 18
curl -sL https://rpm.nodesource.com/setup_18.x | bash -
dnf install -y nodejs

# Install AWS CDK
npm install -g aws-cdk

# Install Docker (for CDK assets)
dnf install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install useful tools
dnf install -y jq tmux htop

# Create setup script for ec2-user
cat > /home/ec2-user/setup-librechat-deployment.sh <<'SCRIPT'
#!/bin/bash
echo "🚀 LibreChat CDK Deployment Setup"
echo "================================"

# Clone repository
if [ ! -d "librechat-cdk" ]; then
    echo "Please provide your Git repository URL:"
    read -p "Git URL (or press Enter to skip): " GIT_URL
    
    if [ -n "$GIT_URL" ]; then
        git clone $GIT_URL librechat-cdk
        cd librechat-cdk
        npm install
        echo "✅ Repository cloned and dependencies installed"
    else
        echo "ℹ️  Skipping repository clone. Clone manually with:"
        echo "   git clone <your-repo-url> librechat-cdk"
    fi
fi

echo ""
echo "📝 Next steps:"
echo "1. cd librechat-cdk"
echo "2. npm install (if not done)"
echo "3. Configure your deployment settings"
echo "4. Run: cdk deploy --all"
echo ""
echo "💡 No token expiration! This instance uses IAM roles."
SCRIPT

chmod +x /home/ec2-user/setup-librechat-deployment.sh
chown ec2-user:ec2-user /home/ec2-user/setup-librechat-deployment.sh

# Create deployment helper script
cat > /home/ec2-user/deploy-librechat.sh <<'DEPLOY'
#!/bin/bash
# Quick deployment script

cd ~/librechat-cdk

echo "🚀 LibreChat CDK Deployment"
echo "=========================="
echo "Current configuration:"
echo ""

if [ -f .env ]; then
    cat .env | grep -E "DEPLOYMENT_|RESOURCE_"
else
    echo "No .env file found. Using defaults."
fi

echo ""
echo "Choose deployment option:"
echo "1) Ultra-minimal (fastest, 60-80 min)"
echo "2) Standard development"
echo "3) Production EC2"
echo "4) Production ECS"
echo "5) Custom configuration"

read -p "Select option (1-5): " option

case $option in
    1) CONFIG="ultra-minimal-dev" ;;
    2) CONFIG="standard-dev" ;;
    3) CONFIG="production-ec2" ;;
    4) CONFIG="production-ecs" ;;
    5) CONFIG="" ;;
    *) CONFIG="ultra-minimal-dev" ;;
esac

# Build
echo "Building project..."
npm run build

# Deploy
if [ -n "$CONFIG" ]; then
    echo "Deploying with configuration: $CONFIG"
    cdk deploy --all -c configSource=$CONFIG --require-approval never
else
    echo "Deploying with current configuration..."
    cdk deploy --all --require-approval never
fi
DEPLOY

chmod +x /home/ec2-user/deploy-librechat.sh
chown ec2-user:ec2-user /home/ec2-user/deploy-librechat.sh

# Set up message of the day
cat > /etc/motd <<'MOTD'
=======================================================
       LibreChat CDK Deployment Instance
=======================================================
  No token expiration! This instance uses IAM roles.

  Quick start:
    ./setup-librechat-deployment.sh  - Initial setup
    ./deploy-librechat.sh           - Deploy LibreChat

  Manual deployment:
    cd librechat-cdk
    cdk deploy --all

=======================================================
MOTD

echo "✅ Deployment instance setup complete!"
EOF

# Launch instance
echo -e "\n${BLUE}Launching EC2 instance...${NC}"

# Build launch command
LAUNCH_CMD="aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type $INSTANCE_TYPE \
    --subnet-id $SUBNET_ID \
    --security-group-ids $SG_ID \
    --iam-instance-profile Name=$INSTANCE_PROFILE_NAME \
    --user-data file://user-data.sh \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value='$INSTANCE_NAME'}]' \
    --metadata-options 'HttpTokens=optional,HttpPutResponseHopLimit=2'"

# Add key name if provided
if [ -n "$KEY_NAME" ]; then
    LAUNCH_CMD="$LAUNCH_CMD --key-name $KEY_NAME"
fi

# Launch the instance
INSTANCE_ID=$(eval $LAUNCH_CMD --query 'Instances[0].InstanceId' --output text)

echo -e "${GREEN}✅ Instance launched: $INSTANCE_ID${NC}"

# Clean up
rm -f user-data.sh

# Wait for instance to be running
echo -e "\n${BLUE}Waiting for instance to be ready...${NC}"
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# Get instance details
INSTANCE_INFO=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0]')
PUBLIC_IP=$(echo $INSTANCE_INFO | jq -r '.PublicIpAddress // "N/A"')
PRIVATE_IP=$(echo $INSTANCE_INFO | jq -r '.PrivateIpAddress')

echo -e "\n${GREEN}✅ Deployment Instance Ready!${NC}"
echo "============================="
echo "Instance ID: $INSTANCE_ID"
echo "Instance Type: $INSTANCE_TYPE"
echo "Private IP: $PRIVATE_IP"
echo "Public IP: $PUBLIC_IP"
echo

# Connection instructions
echo -e "${BLUE}Connection Instructions:${NC}"
echo "------------------------"

if [ -n "$KEY_NAME" ]; then
    echo "SSH Access:"
    if [ "$PUBLIC_IP" != "N/A" ]; then
        echo "  ssh -i ${KEY_NAME}.pem ec2-user@$PUBLIC_IP"
    else
        echo "  ssh -i ${KEY_NAME}.pem ec2-user@$PRIVATE_IP"
    fi
    echo
fi

echo "Session Manager Access (no SSH key needed):"
echo "  aws ssm start-session --target $INSTANCE_ID"
echo
echo "  Or use the AWS Console:"
echo "  1. Go to EC2 > Instances"
echo "  2. Select instance: $INSTANCE_NAME"
echo "  3. Click 'Connect' > 'Session Manager'"
echo

echo -e "${YELLOW}⏱️  Wait 2-3 minutes for user data script to complete${NC}"
echo

echo -e "${BLUE}First Time Setup:${NC}"
echo "1. Connect to the instance"
echo "2. Run: ./setup-librechat-deployment.sh"
echo "3. Run: ./deploy-librechat.sh"
echo

echo -e "${GREEN}✨ No more token expiration issues!${NC}"
echo "The instance uses IAM roles for AWS access."
echo

# Save instance details
cat > deployment-instance-info.txt <<INFO
LibreChat CDK Deployment Instance
=================================
Instance ID: $INSTANCE_ID
Instance Type: $INSTANCE_TYPE
Region: $REGION
Private IP: $PRIVATE_IP
Public IP: $PUBLIC_IP
Security Group: $SG_ID
IAM Role: $ROLE_NAME

Connection:
- SSH: ssh -i ${KEY_NAME}.pem ec2-user@${PUBLIC_IP:-$PRIVATE_IP}
- Session Manager: aws ssm start-session --target $INSTANCE_ID

To terminate:
aws ec2 terminate-instances --instance-ids $INSTANCE_ID
INFO

echo -e "${GREEN}Instance details saved to: deployment-instance-info.txt${NC}"