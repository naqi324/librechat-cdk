#!/bin/bash
# deploy.sh - Helper script for LibreChat CDK deployment

set -e

echo "🚀 LibreChat CDK Deployment Helper"
echo "=================================="

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."

    if ! command -v node &> /dev/null; then
        echo "❌ Node.js is not installed. Please install Node.js 16+ first."
        exit 1
    fi

    if ! command -v aws &> /dev/null; then
        echo "❌ AWS CLI is not installed. Please install AWS CLI first."
        exit 1
    fi

    if ! command -v cdk &> /dev/null; then
        echo "⚠️  CDK is not installed. Installing now..."
        npm install -g aws-cdk
    fi

    echo "✅ Prerequisites check passed"
}

# Install dependencies
install_dependencies() {
    echo "Installing dependencies..."
    npm install
    echo "✅ Dependencies installed"
}

# Build the project
build_project() {
    echo "Building project..."
    npm run build
    echo "✅ Project built"
}

# Generate CloudFormation template
generate_template() {
    echo "Generating CloudFormation template..."
    cdk synth --no-staging > librechat-cloudformation.yaml

    # Also generate a parameters file
    cat > librechat-parameters.json << 'EOF'
[
  {
    "ParameterKey": "AlertEmail",
    "ParameterValue": "your-email@domain.com"
  },
  {
    "ParameterKey": "KeyName",
    "ParameterValue": "your-ec2-key-pair"
  },
  {
    "ParameterKey": "AllowedSSHIP",
    "ParameterValue": "0.0.0.0/0"
  }
]
EOF

    echo "✅ CloudFormation template generated: librechat-cloudformation.yaml"
    echo "✅ Parameters file generated: librechat-parameters.json"
}

# Deploy via CDK
deploy_cdk() {
    echo "Deploying via CDK..."

    # Get parameters
    read -p "Enter alert email address: " ALERT_EMAIL
    read -p "Enter EC2 key pair name: " KEY_NAME
    read -p "Enter allowed SSH IP (your IP/32): " SSH_IP

    # Deploy
    cdk deploy \
        --parameters AlertEmail="$ALERT_EMAIL" \
        --parameters KeyName="$KEY_NAME" \
        --parameters AllowedSSHIP="$SSH_IP" \
        --require-approval never
}

# Deploy via CloudFormation CLI
deploy_cloudformation() {
    echo "Deploying via CloudFormation CLI..."

    # Check if template exists
    if [ ! -f "librechat-cloudformation.yaml" ]; then
        generate_template
    fi

    # Get parameters
    read -p "Enter stack name [LibreChat-Production]: " STACK_NAME
    STACK_NAME=${STACK_NAME:-LibreChat-Production}

    read -p "Enter alert email address: " ALERT_EMAIL
    read -p "Enter EC2 key pair name: " KEY_NAME
    read -p "Enter allowed SSH IP (your IP/32): " SSH_IP

    # Create stack
    aws cloudformation create-stack \
        --stack-name "$STACK_NAME" \
        --template-body file://librechat-cloudformation.yaml \
        --parameters \
            ParameterKey=AlertEmail,ParameterValue="$ALERT_EMAIL" \
            ParameterKey=KeyName,ParameterValue="$KEY_NAME" \
            ParameterKey=AllowedSSHIP,ParameterValue="$SSH_IP" \
        --capabilities CAPABILITY_IAM \
        --on-failure ROLLBACK

    echo "✅ Stack creation initiated. Monitor progress in AWS Console."
    echo "   Run: aws cloudformation describe-stacks --stack-name $STACK_NAME"
}

# Main menu
main_menu() {
    echo ""
    echo "Choose deployment method:"
    echo "1) Generate CloudFormation template for AWS Console"
    echo "2) Deploy directly via CDK"
    echo "3) Deploy via CloudFormation CLI"
    echo "4) Exit"

    read -p "Enter choice [1-4]: " choice

    case $choice in
        1)
            generate_template
            echo ""
            echo "📋 Next steps:"
            echo "1. Go to AWS CloudFormation Console"
            echo "2. Click 'Create stack' > 'With new resources'"
            echo "3. Upload librechat-cloudformation.yaml"
            echo "4. Fill in the parameters"
            echo "5. Create the stack"
            ;;
        2)
            deploy_cdk
            ;;
        3)
            deploy_cloudformation
            ;;
        4)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid choice"
            main_menu
            ;;
    esac
}

# Run the script
check_prerequisites
install_dependencies
build_project
main_menu
