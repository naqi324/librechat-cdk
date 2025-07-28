# LibreChat AWS CDK Deployment 🚀

[![AWS CDK](https://img.shields.io/badge/AWS%20CDK-2.150.0-orange)](https://aws.amazon.com/cdk/)
[![Node.js](https://img.shields.io/badge/Node.js-18%2B-green)](https://nodejs.org/)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.3-blue)](https://www.typescriptlang.org/)

> Enterprise-grade deployment of LibreChat on AWS with support for both EC2 and ECS deployments, featuring AWS Bedrock integration, PostgreSQL with pgvector, DocumentDB, and comprehensive monitoring.

## ✨ Features

### Core Features

- **🎯 Dual Deployment Modes**: Choose between simple EC2 or scalable ECS Fargate
- **🤖 AWS Bedrock Integration**: Built-in support for Claude, Titan, and Llama models
- **🔍 RAG Support**: Retrieval Augmented Generation with pgvector
- **🔎 Search Engine**: Optional Meilisearch integration
- **📊 Monitoring**: CloudWatch dashboards and alarms
- **🔐 Security**: IAM roles, secrets management, and encryption
- **💰 Cost Optimized**: Right-sized resources for each environment

### Infrastructure Components

- **Networking**: VPC with public/private subnets across multiple AZs
- **Compute**: EC2 instances or ECS Fargate containers
- **Database**: RDS PostgreSQL (with pgvector) and optional DocumentDB
- **Storage**: S3 for documents and EFS for shared container storage
- **Load Balancing**: Application Load Balancer with auto-scaling
- **Security**: WAF, security groups, and KMS encryption

## 🏗️ Architecture

### EC2 Deployment Architecture

```md
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   CloudFront    │────▶│       ALB       │────▶│   EC2 Instance  │
│   (Optional)    │     │   (Public)      │     │   (Private)     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                         │
                        ┌─────────────────────────────────┤
                        │                                 │
                   ┌────▼─────┐                    ┌─────▼─────┐
                   │   RDS    │                    │    S3     │
                   │PostgreSQL│                    │  Bucket   │
                   └──────────┘                    └───────────┘
```

### ECS Deployment Architecture

```md
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   CloudFront    │────▶│       ALB       │────▶│  ECS Fargate    │
│   (Optional)    │     │   (Public)      │     │   (Private)     │
└─────────────────┘     └─────────────────┘     └─────┬───────────┘
                                                       │
                        ┌──────────────────────────────┼─────────────┐
                        │                              │             │
                   ┌────▼─────┐  ┌─────────────┐  ┌───▼────┐  ┌────▼────┐
                   │   RDS    │  │ DocumentDB  │  │  EFS   │  │   S3    │
                   │PostgreSQL│  │ (Optional)  │  │        │  │ Bucket  │
                   └──────────┘  └─────────────┘  └────────┘  └─────────┘
```

## 📋 Prerequisites

### Required

- ✅ AWS Account with appropriate permissions
- ✅ Node.js 18.x or later
- ✅ AWS CLI configured with credentials
- ✅ AWS Bedrock access enabled in your region

### Optional

- 🔑 EC2 Key Pair (required for EC2 deployment mode - see [Key Pair Setup](#key-pair-setup))
- 🌐 Domain name and SSL certificate (for HTTPS)
- 📧 Email address for monitoring alerts

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/your-org/librechat-cdk.git
cd librechat-cdk

# Run the setup script (handles everything from setup to deployment)
./setup.sh
```

The setup script will:
- ✅ Check prerequisites
- ✅ Install dependencies
- ✅ Configure your deployment
- ✅ Bootstrap AWS CDK
- ✅ Deploy your stack

For manual deployment or advanced configuration, see the [Deployment Guide](DEPLOYMENT_GUIDE.md).

### Deployment Commands

```bash
# Standard deployment (shows progress bar)
npm run deploy

# Verbose deployment (detailed descriptions of each step)
npm run deploy:verbose

# Deploy to specific environments
npm run deploy:dev
npm run deploy:staging
npm run deploy:prod
```

The verbose deployment mode provides:
- 🌐 Creating VPC and networking resources
- 🗄️ Setting up RDS PostgreSQL database
- ⚡ Deploying Lambda functions
- 🐳 Launching ECS containers or EC2 instances
- ⚖️ Configuring load balancers
- 📦 Creating storage buckets
- 📊 Setting up monitoring

### Fast Deployment

For quicker deployments (10 minutes instead of 15-20):

```bash
# Use minimal resources for fastest deployment
npm run deploy:fast

# Or set resource size manually
RESOURCE_SIZE=xs npm run deploy
```

See [Deployment Optimization Guide](docs/DEPLOYMENT_OPTIMIZATION.md) for details.

### 2. Access LibreChat

After deployment completes (15-20 minutes), you'll receive:

- 🌐 Application URL
- 📊 CloudWatch Dashboard URL
- 🔑 SSH instructions (for EC2 deployments)

## 🔑 Key Pair Setup

EC2 deployments require an AWS key pair for SSH access. ECS deployments do NOT require a key pair.

### Creating a Key Pair

#### Option 1: AWS Console
1. Go to EC2 > Key Pairs in AWS Console
2. Click "Create key pair"
3. Enter a name (e.g., `librechat-key`)
4. Choose key pair type (RSA recommended)
5. Choose file format (.pem for Linux/Mac, .ppk for Windows)
6. Save the private key file securely

#### Option 2: AWS CLI
```bash
aws ec2 create-key-pair \
  --key-name librechat-key \
  --query 'KeyMaterial' \
  --output text > librechat-key.pem

# Set proper permissions
chmod 400 librechat-key.pem
```

### Using the Key Pair

Once created, provide the key pair name during deployment:

```bash
# Method 1: Environment variable
export KEY_PAIR_NAME=librechat-key
npm run deploy

# Method 2: CDK context
npm run deploy -- -c keyPairName=librechat-key

# Method 3: .env file
echo "KEY_PAIR_NAME=librechat-key" >> .env
npm run deploy
```

### Avoiding Key Pair Requirement

To deploy without a key pair, use ECS deployment mode:

```bash
# Method 1: Environment variable
export DEPLOYMENT_MODE=ECS
npm run deploy

# Method 2: Use setup script and select ECS
./scripts/setup-deployment.sh
```

## 🎯 Deployment Options

### Option 1: Development Environment

```bash
# Minimal setup for testing
npm run deploy:dev -- \
  -c configSource=minimal-dev \
  -c keyPairName=my-dev-key
```


### Option 2: Production EC2

```bash
# Cost-optimized production (requires key pair)
npm run deploy:prod -- \
  -c configSource=production-ec2 \
  -c keyPairName=prod-key \
  -c alertEmail=ops@company.com \
  -c domainName=chat.company.com
```

### Option 3: Production ECS

```bash
# Scalable production deployment (no key pair required)
npm run deploy:prod -- \
  -c configSource=production-ecs \
  -c alertEmail=ops@company.com \
  -c domainName=chat.company.com \
  -c certificateArn=arn:aws:acm:...
```


### Option 4: Enterprise

```bash
# Full enterprise features
npm run deploy:prod -- \
  -c configSource=enterprise \
  -c alertEmail=ops@company.com \
  -c domainName=chat.company.com \
  -c enableSharePoint=true
```

## ⚙️ Configuration

### Environment Configuration

Create `.env.librechat` for environment-specific settings (optional - you can also use CDK context parameters):

```bash
# Deployment Settings
DEPLOYMENT_ENV=production
DEPLOYMENT_MODE=ECS
AWS_REGION=us-east-1

# Security
KEY_PAIR_NAME=prod-key
ALLOWED_IPS=10.0.0.0/8

# Monitoring
ALERT_EMAIL=ops@company.com

# Features
ENABLE_RAG=true
ENABLE_MEILISEARCH=true

# Domain Configuration
DOMAIN_NAME=chat.company.com
CERTIFICATE_ARN=arn:aws:acm:...
HOSTED_ZONE_ID=Z1234567890ABC
```

### Application Configuration

Edit `config/librechat.yaml` for LibreChat-specific settings:

```yaml
version: 1.1.5

endpoints:
  bedrock:
    titleModel: "anthropic.claude-sonnet-4-20250525-v1:0"
    models:
      default:
        - "anthropic.claude-sonnet-4-20250525-v1:0"
        - "anthropic.claude-opus-4-20250514-v1:0"
        - "anthropic.claude-3-5-sonnet-20241022-v2:0"
        - "amazon.titan-text-premier-v1:0"

fileConfig:
  endpoints:
    default:
      fileLimit: 50
      fileSizeLimit: 100
      supportedMimeTypes:
        - "application/pdf"
        - "text/plain"

registration:
  enabled: true
  allowedDomains:
    - "company.com"
```

### Advanced Configuration

For detailed configuration options, see the configuration files in this repository:

- `config/deployment-config.ts` - Deployment configurations
- `config/librechat.yaml` - LibreChat application settings
- `cdk.json` - CDK context and feature flags

## 🔧 Troubleshooting

### Common Issues

**Note**: Docker is NOT required for CDK deployment. The project uses pre-built Lambda layers.

**Issue**: Cannot access application after deployment

```bash
# Check ALB target health
aws elbv2 describe-target-health \
  --target-group-arn $(aws cloudformation describe-stacks \
    --stack-name LibreChatStack \
    --query 'Stacks[0].Outputs[?OutputKey==`TargetGroupArn`].OutputValue' \
    --output text)
```

**Issue**: High costs

```bash
# Generate cost report
npm run estimate-cost --compare
```

See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for comprehensive guide.

## 🔐 Security

### Security Features

- ✅ **Encryption**: At rest and in transit
- ✅ **IAM Roles**: Least privilege access
- ✅ **Secrets Manager**: No hardcoded credentials
- ✅ **VPC Isolation**: Private subnets for sensitive resources
- ✅ **WAF Integration**: Protection against common attacks
- ✅ **Security Groups**: Restrictive inbound rules
- ✅ **Audit Logging**: CloudTrail and VPC Flow Logs

### Best Practices

1. **Regular Updates**: Keep containers and dependencies updated
2. **Access Control**: Use MFA for AWS console access
3. **Monitoring**: Enable GuardDuty and Security Hub
4. **Backups**: Regular automated backups
5. **Incident Response**: Have a plan and test it

See [SECURITY.md](docs/SECURITY.md) for detailed security guide.

## 🙏 Acknowledgments

- [LibreChat](https://github.com/danny-avila/LibreChat) - The amazing open-source AI chat platform
- [AWS CDK](https://aws.amazon.com/cdk/) - Infrastructure as Code framework
- [Anthropic](https://www.anthropic.com/) - For Claude models via AWS Bedrock
