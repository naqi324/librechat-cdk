# LibreChat AWS CDK Deployment 🚀

[![AWS CDK](https://img.shields.io/badge/AWS%20CDK-2.150.0-orange)](https://aws.amazon.com/cdk/)
[![Node.js](https://img.shields.io/badge/Node.js-18%2B-green)](https://nodejs.org/)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.3-blue)](https://www.typescriptlang.org/)

> Enterprise-grade deployment of LibreChat on AWS with support for both EC2 and ECS deployments, featuring AWS Bedrock integration, PostgreSQL with pgvector, DocumentDB, and comprehensive monitoring.

## 📋 Table of Contents

- [Features](#-features)
- [Architecture](#-architecture)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Deployment Options](#-deployment-options)
- [Configuration](#-configuration)
- [Cost Analysis](#-cost-analysis)
- [Migration Guide](#-migration-guide)
- [Troubleshooting](#-troubleshooting)
- [Security](#-security)
- [Contributing](#-contributing)
- [Support](#-support)

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

- 🔧 Docker Desktop (for local development)
- 🔑 EC2 Key Pair (for SSH access)
- 🌐 Domain name and SSL certificate (for HTTPS)
- 📧 Email address for monitoring alerts

## 🚀 Quick Start

### 1. Clone and Setup

```bash
# Clone the repository
git clone https://github.com/your-org/librechat-cdk.git
cd librechat-cdk

# Run the setup wizard
./scripts/setup-environment.sh
```

### 2. Deploy with Interactive Wizard

```bash
# Launch the deployment wizard
npm run wizard
```

### 3. Access LibreChat

After deployment completes (15-20 minutes), you'll receive:

- 🌐 Application URL
- 📊 CloudWatch Dashboard URL
- 🔑 SSH instructions (for EC2 deployments)

## 🎯 Deployment Options

### Option 1: Development Environment

```bash
# Minimal setup for testing
npm run deploy:dev -- \
  -c configSource=minimal-dev \
  -c keyPairName=my-dev-key
```

**Cost**: ~$150/month | **Features**: Basic LibreChat without RAG

### Option 2: Production EC2

```bash
# Cost-optimized production
npm run deploy:prod -- \
  -c configSource=production-ec2 \
  -c keyPairName=prod-key \
  -c alertEmail=ops@company.com \
  -c domainName=chat.company.com
```

**Cost**: ~$250/month | **Features**: Full features, single instance

### Option 3: Production ECS

```bash
# Scalable production deployment
npm run deploy:prod -- \
  -c configSource=production-ecs \
  -c alertEmail=ops@company.com \
  -c domainName=chat.company.com \
  -c certificateArn=arn:aws:acm:...
```

**Cost**: ~$400/month | **Features**: Auto-scaling, high availability

### Option 4: Enterprise

```bash
# Full enterprise features
npm run deploy:prod -- \
  -c configSource=enterprise \
  -c alertEmail=ops@company.com \
  -c domainName=chat.company.com \
  -c enableSharePoint=true
```

**Cost**: ~$800/month | **Features**: All features, multi-AZ, DocumentDB

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

## 💰 Cost Analysis

### Estimated Monthly Costs by Environment

| Component | Development | Production EC2 | Production ECS | Enterprise |
|-----------|-------------|----------------|----------------|------------|
| Compute | $80 | $120 | $200 | $400 |
| Database | $20 | $70 | $150 | $300 |
| Storage | $5 | $10 | $20 | $50 |
| Network | $15 | $30 | $50 | $100 |
| Other | $10 | $20 | $30 | $50 |
| **Total** | **~$130** | **~$250** | **~$450** | **~$900** |

### Cost Optimization Tips

1. **Use Savings Plans**: Save up to 30% on compute costs
2. **Right-size Resources**: Monitor and adjust instance types
3. **Enable Auto-scaling**: Scale down during off-hours
4. **S3 Lifecycle Policies**: Move old data to cheaper storage
5. **Reserved Instances**: For stable production workloads

Run cost estimation:

```bash
npm run estimate-cost production
```

## 🔄 Migration Guide

### From Original EC2 Deployment

If you're using the original LibreChat CDK deployment:

1. **Backup Current State**

   ```bash
   # Create backup manually
   aws rds create-db-snapshot --db-instance-identifier librechat-postgres --db-snapshot-identifier backup-$(date +%Y%m%d)
   ```

2. **Update Code**

   ```bash
   git pull origin main
   npm install
   ```

3. **Run Migration**

   ```bash
   # Run CDK deployment with the new version
   npm run deploy
   ```

For detailed migration instructions, please refer to the AWS CDK migration documentation.

## 🔧 Troubleshooting

### Common Issues

**Issue**: Deployment fails with "no space left on device"

```bash
# Solution: Clean up Docker
docker system prune -a
```

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

## 🤝 Contributing

We welcome contributions! Please follow standard open source contribution practices.

### Development Setup

```bash
# Clone repository
git clone https://github.com/your-org/librechat-cdk.git
cd librechat-cdk

# Install dependencies
npm install

# Run tests
npm test

# Run linter
npm run lint

# Local development
docker-compose -f docker-compose.local.yml up
```

### Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📞 Support

### Getting Help

- 📖 **Documentation**: Check `/docs` directory
- 💬 **Discord**: [Join our community](https://discord.librechat.ai)
- 🐛 **Issues**: [GitHub Issues](https://github.com/your-org/librechat-cdk/issues)
- 📧 **Email**: <support@librechat.ai>

### Useful Commands

```bash
# View all available commands
npm run

# Check deployment status
aws cloudformation describe-stacks --stack-name LibreChatStack

# View logs
aws logs tail /aws/librechat --follow

# SSH to EC2 instance (replace with your instance IP)
ssh -i your-key.pem ubuntu@INSTANCE-IP

# Get instance logs
aws ec2 get-console-output --instance-id INSTANCE-ID
```

## 🙏 Acknowledgments

- [LibreChat](https://github.com/danny-avila/LibreChat) - The amazing open-source AI chat platform
- [AWS CDK](https://aws.amazon.com/cdk/) - Infrastructure as Code framework
- [Anthropic](https://www.anthropic.com/) - For Claude models via AWS Bedrock
- Our amazing community of contributors
