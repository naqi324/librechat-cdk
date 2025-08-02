#!/bin/bash

# Script to set up CDK deployment on an EXISTING EC2 instance
# This is useful if you already have an EC2 instance with appropriate IAM role

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Setting Up CDK Deployment on Existing EC2${NC}"
echo "============================================"
echo "Run this script ON your EC2 instance"
echo

# Check if running on EC2
if ! curl -s http://169.254.169.254/latest/meta-data/instance-id &>/dev/null; then
    echo -e "${YELLOW}⚠️  This doesn't appear to be an EC2 instance.${NC}"
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Install Node.js if not present
if ! command -v node &> /dev/null; then
    echo -e "${BLUE}Installing Node.js...${NC}"
    curl -sL https://rpm.nodesource.com/setup_18.x | sudo bash -
    sudo dnf install -y nodejs || sudo yum install -y nodejs || sudo apt-get install -y nodejs
fi

# Install CDK if not present
if ! command -v cdk &> /dev/null; then
    echo -e "${BLUE}Installing AWS CDK...${NC}"
    sudo npm install -g aws-cdk
fi

# Install Git if not present
if ! command -v git &> /dev/null; then
    echo -e "${BLUE}Installing Git...${NC}"
    sudo dnf install -y git || sudo yum install -y git || sudo apt-get install -y git
fi

# Install useful tools
echo -e "${BLUE}Installing useful tools...${NC}"
sudo dnf install -y jq tmux htop 2>/dev/null || \
sudo yum install -y jq tmux htop 2>/dev/null || \
sudo apt-get install -y jq tmux htop 2>/dev/null || true

# Clone repository
echo -e "\n${BLUE}Repository Setup${NC}"
echo "================"

if [ ! -d "$HOME/librechat-cdk" ]; then
    read -p "Enter your LibreChat CDK repository URL: " REPO_URL
    if [ -n "$REPO_URL" ]; then
        cd $HOME
        git clone $REPO_URL librechat-cdk
        cd librechat-cdk
        npm install
        echo -e "${GREEN}✅ Repository cloned and dependencies installed${NC}"
    fi
else
    echo -e "${GREEN}✅ Repository already exists at ~/librechat-cdk${NC}"
    cd $HOME/librechat-cdk
    git pull
    npm install
fi

# Create quick deployment script
cat > $HOME/deploy-librechat-quick.sh <<'EOF'
#!/bin/bash

cd ~/librechat-cdk

echo "🚀 Quick LibreChat Deployment"
echo "============================"

# Show current config
if [ -f .env ]; then
    echo "Current configuration:"
    grep -E "DEPLOYMENT_MODE|RESOURCE_SIZE" .env
fi

echo ""
echo "Deployment options:"
echo "1) Ultra-minimal (60-80 min) - Recommended"
echo "2) Current .env configuration"
echo "3) Standard development"
echo "4) Exit"

read -p "Select option (1-4) [1]: " option
option=${option:-1}

case $option in
    1)
        echo "Deploying ultra-minimal configuration..."
        npm run build && cdk deploy -c configSource=ultra-minimal-dev --all --require-approval never
        ;;
    2)
        echo "Deploying with current .env configuration..."
        npm run build && cdk deploy --all --require-approval never
        ;;
    3)
        echo "Deploying standard development..."
        npm run build && cdk deploy -c configSource=standard-dev --all --require-approval never
        ;;
    4)
        echo "Exiting..."
        exit 0
        ;;
    *)
        echo "Invalid option. Exiting..."
        exit 1
        ;;
esac
EOF

chmod +x $HOME/deploy-librechat-quick.sh

# Create tmux deployment script
cat > $HOME/deploy-in-tmux.sh <<'EOF'
#!/bin/bash

# Deploy in tmux session to prevent disconnection issues
SESSION_NAME="librechat-deploy"

# Check if session exists
if tmux has-session -t $SESSION_NAME 2>/dev/null; then
    echo "Deployment session already exists. Attaching..."
    tmux attach-session -t $SESSION_NAME
else
    echo "Creating new deployment session..."
    tmux new-session -d -s $SESSION_NAME
    tmux send-keys -t $SESSION_NAME "cd ~/librechat-cdk" C-m
    tmux send-keys -t $SESSION_NAME "./deploy-librechat-quick.sh" C-m
    tmux attach-session -t $SESSION_NAME
fi
EOF

chmod +x $HOME/deploy-in-tmux.sh

# Check IAM role
echo -e "\n${BLUE}Checking IAM permissions...${NC}"
if aws sts get-caller-identity &>/dev/null; then
    ROLE_ARN=$(aws sts get-caller-identity --query Arn --output text)
    echo -e "${GREEN}✅ IAM role detected: $ROLE_ARN${NC}"
    
    # Check if PowerUserAccess or AdministratorAccess
    if aws iam list-attached-role-policies --role-name $(echo $ROLE_ARN | cut -d'/' -f2) 2>/dev/null | grep -E "PowerUserAccess|AdministratorAccess" &>/dev/null; then
        echo -e "${GREEN}✅ Sufficient permissions for CDK deployment${NC}"
    else
        echo -e "${YELLOW}⚠️  Make sure your IAM role has sufficient permissions for CDK${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  No IAM role detected. You'll need to configure AWS credentials.${NC}"
fi

echo -e "\n${GREEN}✅ Setup Complete!${NC}"
echo "=================="
echo
echo "Quick deployment commands:"
echo "  ${BLUE}./deploy-librechat-quick.sh${NC}  - Interactive deployment"
echo "  ${BLUE}./deploy-in-tmux.sh${NC}         - Deploy in tmux (survives disconnection)"
echo
echo "Manual deployment:"
echo "  ${BLUE}cd ~/librechat-cdk${NC}"
echo "  ${BLUE}npm run build${NC}"
echo "  ${BLUE}cdk deploy -c configSource=ultra-minimal-dev --all${NC}"
echo
echo "💡 This instance uses IAM roles - no token expiration!"