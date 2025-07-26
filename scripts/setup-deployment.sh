#!/bin/bash
# LibreChat CDK Deployment Setup Script

set -e

echo "🚀 LibreChat CDK Deployment Setup"
echo "================================="
echo

# Function to prompt for input with default
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    read -p "$prompt [$default]: " value
    value="${value:-$default}"
    eval "$var_name='$value'"
}

# Check if .env exists
if [ -f .env ]; then
    echo "⚠️  .env file already exists. Backing up to .env.backup"
    cp .env .env.backup
fi

# Deployment mode selection
echo "Select deployment mode:"
echo "1) EC2 (requires key pair)"
echo "2) ECS (container-based, no key pair required)"
read -p "Enter choice (1 or 2) [1]: " deployment_choice
deployment_choice="${deployment_choice:-1}"

if [ "$deployment_choice" = "2" ]; then
    DEPLOYMENT_MODE="ECS"
    echo
    echo "✅ Selected ECS deployment mode (no key pair required)"
else
    DEPLOYMENT_MODE="EC2"
    echo
    echo "✅ Selected EC2 deployment mode"
    
    # Check for existing key pairs
    echo
    echo "Checking for existing EC2 key pairs..."
    if command -v aws &> /dev/null; then
        echo "Available key pairs:"
        aws ec2 describe-key-pairs --query 'KeyPairs[*].KeyName' --output text 2>/dev/null | tr '\t' '\n' | sed 's/^/  - /' || echo "  Unable to list key pairs"
    fi
    
    echo
    prompt_with_default "Enter your EC2 key pair name" "" KEY_PAIR_NAME
    
    if [ -z "$KEY_PAIR_NAME" ]; then
        echo "❌ Error: Key pair name is required for EC2 deployment"
        echo
        echo "To create a key pair:"
        echo "1. Go to AWS Console > EC2 > Key Pairs"
        echo "2. Click 'Create key pair'"
        echo "3. Save the private key file securely"
        echo
        echo "Or run: aws ec2 create-key-pair --key-name my-librechat-key --query 'KeyMaterial' --output text > my-librechat-key.pem"
        exit 1
    fi
fi

# Environment selection
echo
prompt_with_default "Enter environment (development/staging/production)" "development" DEPLOYMENT_ENV

# Alert email
echo
prompt_with_default "Enter alert email for monitoring" "alerts@example.com" ALERT_EMAIL

# Domain configuration
echo
read -p "Do you want to configure a custom domain? (y/n) [n]: " configure_domain
configure_domain="${configure_domain:-n}"

if [ "$configure_domain" = "y" ]; then
    prompt_with_default "Enter domain name" "chat.example.com" DOMAIN_NAME
    prompt_with_default "Enter ACM certificate ARN (or press enter to skip)" "" CERTIFICATE_ARN
    prompt_with_default "Enter Route53 hosted zone ID (or press enter to skip)" "" HOSTED_ZONE_ID
fi

# Feature selection
echo
echo "Feature Configuration:"
prompt_with_default "Enable RAG (Retrieval Augmented Generation)? (true/false)" "true" ENABLE_RAG
prompt_with_default "Enable Meilisearch? (true/false)" "false" ENABLE_MEILISEARCH
prompt_with_default "Enable SharePoint integration? (true/false)" "false" ENABLE_SHAREPOINT

# VPC configuration
echo
read -p "Do you want to use an existing VPC? (y/n) [n]: " use_existing_vpc
use_existing_vpc="${use_existing_vpc:-n}"

if [ "$use_existing_vpc" = "y" ]; then
    prompt_with_default "Enter existing VPC ID" "" EXISTING_VPC_ID
fi

# IP allowlist for EC2
if [ "$DEPLOYMENT_MODE" = "EC2" ]; then
    echo
    prompt_with_default "Enter allowed IP ranges (comma-separated)" "0.0.0.0/0" ALLOWED_IPS
fi

# Write .env file
echo
echo "Writing configuration to .env file..."

cat > .env << EOF
# LibreChat CDK Deployment Configuration
# Generated on $(date)

# Deployment settings
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

# Domain configuration
DOMAIN_NAME=$DOMAIN_NAME
EOF
    [ -n "$CERTIFICATE_ARN" ] && echo "CERTIFICATE_ARN=$CERTIFICATE_ARN" >> .env
    [ -n "$HOSTED_ZONE_ID" ] && echo "HOSTED_ZONE_ID=$HOSTED_ZONE_ID" >> .env
fi

if [ "$use_existing_vpc" = "y" ]; then
    cat >> .env << EOF

# VPC configuration
EXISTING_VPC_ID=$EXISTING_VPC_ID
EOF
fi

echo
echo "✅ Configuration saved to .env"
echo
echo "Next steps:"
echo "1. Review and edit .env if needed"
echo "2. Run: npm run deploy"
echo
echo "To use a different configuration, you can also run:"
echo "  npm run deploy:dev -- -c configSource=minimal-dev -c keyPairName=$KEY_PAIR_NAME"
echo

# Make the script executable
chmod +x scripts/setup-deployment.sh 2>/dev/null || true