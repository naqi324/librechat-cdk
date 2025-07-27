#!/bin/bash
# deploy-verbose.sh - Deploy CDK stack with descriptive output

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting LibreChat CDK Deployment${NC}"
echo "=================================="

# Load environment variables
if [ -f .env ]; then
    source .env
    echo -e "${GREEN}✓ Loaded environment configuration${NC}"
fi

# Build TypeScript
echo -e "\n${BLUE}📦 Building TypeScript code...${NC}"
npm run build
echo -e "${GREEN}✓ Build completed${NC}"

# Synthesize CloudFormation template
echo -e "\n${BLUE}🔨 Synthesizing CloudFormation template...${NC}"
npx cdk synth --quiet

# Get list of stacks
STACKS=$(npx cdk list 2>/dev/null | grep -v "^$")
echo -e "\n${BLUE}📋 Stacks to deploy:${NC}"
echo "$STACKS"

# Deploy with progress
echo -e "\n${BLUE}🚀 Deploying stacks with detailed progress...${NC}"
echo -e "${YELLOW}This process will:${NC}"
echo "  1. Create/update VPC and networking resources"
echo "  2. Set up RDS PostgreSQL database with pgvector"
echo "  3. Create Lambda functions for database initialization"
echo "  4. Deploy EC2/ECS compute resources"
echo "  5. Configure Application Load Balancer"
echo "  6. Set up S3 buckets for file storage"
echo "  7. Create CloudWatch monitoring and alarms"
echo "  8. Configure IAM roles and security groups"
echo ""
echo -e "${YELLOW}⏱️  Estimated time: 15-20 minutes for first deployment${NC}"
echo ""

# Deploy with verbose output
npx cdk deploy \
    --all \
    --require-approval never \
    --progress events \
    --outputs-file deployment-outputs.json \
    2>&1 | while IFS= read -r line; do
        # Parse and enhance CDK output
        if [[ "$line" == *"CREATE_IN_PROGRESS"* ]]; then
            if [[ "$line" == *"AWS::EC2::VPC"* ]]; then
                echo -e "${BLUE}🌐 Creating Virtual Private Cloud (VPC)...${NC}"
            elif [[ "$line" == *"AWS::RDS::DBInstance"* ]]; then
                echo -e "${BLUE}🗄️  Creating RDS PostgreSQL database (this takes 5-10 minutes)...${NC}"
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
            elif [[ "$line" == *"AWS::CloudWatch::Alarm"* ]]; then
                echo -e "${BLUE}📊 Setting up CloudWatch monitoring...${NC}"
            elif [[ "$line" == *"AWS::IAM::Role"* ]]; then
                echo -e "${BLUE}🔐 Configuring IAM permissions...${NC}"
            elif [[ "$line" == *"AWS::EC2::SecurityGroup"* ]]; then
                echo -e "${BLUE}🛡️  Setting up security groups...${NC}"
            elif [[ "$line" == *"AWS::SecretsManager::Secret"* ]]; then
                echo -e "${BLUE}🔑 Creating database secrets...${NC}"
            elif [[ "$line" == *"AWS::CloudFormation::CustomResource"* ]] && [[ "$line" == *"InitPostgres"* ]]; then
                echo -e "${BLUE}🔧 Initializing PostgreSQL with pgvector extension...${NC}"
            fi
        elif [[ "$line" == *"CREATE_COMPLETE"* ]]; then
            if [[ "$line" == *"AWS::RDS::DBInstance"* ]]; then
                echo -e "${GREEN}✅ Database ready!${NC}"
            elif [[ "$line" == *"AWS::CloudFormation::Stack"* ]]; then
                echo -e "${GREEN}✅ Stack deployment complete!${NC}"
            fi
        elif [[ "$line" == *"UPDATE_IN_PROGRESS"* ]]; then
            echo -e "${YELLOW}♻️  Updating existing resources...${NC}"
        elif [[ "$line" == *"Outputs:"* ]]; then
            echo -e "\n${GREEN}📋 Deployment Outputs:${NC}"
        fi
        
        # Still show the original line for full transparency
        echo "$line"
    done

echo -e "\n${GREEN}✅ Deployment completed successfully!${NC}"
echo -e "\n${BLUE}📄 Next steps:${NC}"
echo "  1. Check deployment-outputs.json for endpoints and credentials"
echo "  2. Access the application URL shown in the outputs"
echo "  3. Monitor CloudWatch logs for any issues"
echo ""
echo -e "${YELLOW}💡 Tip: Run 'npm run check-deployment' to verify all resources${NC}"