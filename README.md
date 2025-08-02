# LibreChat AWS CDK Deployment 🚀

[![AWS CDK](https://img.shields.io/badge/AWS%20CDK-2.150.0-orange)](https://aws.amazon.com/cdk/)
[![Node.js](https://img.shields.io/badge/Node.js-18%2B-green)](https://nodejs.org/)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.3-blue)](https://www.typescriptlang.org/)

Deploy [LibreChat](https://github.com/danny-avila/LibreChat) on AWS with enterprise features, AWS Bedrock integration, and production-ready infrastructure.

## ✨ Features

- **🎯 Flexible Deployment**: Choose EC2 (simple) or ECS Fargate (scalable)
- **🤖 AWS Bedrock**: Claude, Titan, and Llama models built-in
- **🔍 RAG Support**: Vector search with PostgreSQL pgvector
- **🔐 Enterprise Security**: IAM, KMS encryption, VPC isolation
- **📊 Full Monitoring**: CloudWatch dashboards and alarms
- **💰 Cost Optimized**: Right-sized resources per environment

## 🚀 Quick Start

### Fastest Deployment (5 minutes)

```bash
# Clone and deploy with interactive wizard
git clone https://github.com/your-org/librechat-cdk.git
cd librechat-cdk
npm install
npm run wizard
```

The wizard will guide you through:
- ✅ AWS credentials check
- ✅ Deployment mode selection (EC2/ECS)
- ✅ Environment configuration
- ✅ Cost estimation
- ✅ Automated deployment

### One-Command Deployment

```bash
# Development environment
npm run deploy:dev

# Production with EC2 (cost-effective)
npm run deploy:prod -- -c configSource=production-ec2 -c keyPairName=prod-key

# Production with ECS (scalable)
npm run deploy:prod -- -c configSource=production-ecs
```

## 📋 Prerequisites

- AWS Account with [appropriate permissions](docs/README.md#deployment-guides)
- Node.js 18+ and npm
- AWS CLI [configured](docs/AWS_AUTHENTICATION.md)
- AWS Bedrock access in your region
- EC2 Key Pair (for EC2 mode only)

## 🏗️ Architecture

<details>
<summary>View Architecture Diagrams</summary>

### EC2 Mode
```
Internet → ALB → EC2 Instance → RDS PostgreSQL
                       ↓
                  S3 Storage
```

### ECS Mode
```
Internet → ALB → ECS Fargate → RDS PostgreSQL
                      ↓         DocumentDB
                 EFS + S3       (optional)
```
</details>

## ⚙️ Configuration Options

### Deployment Presets

| Preset | Description | Monthly Cost* | Best For |
|--------|-------------|--------------|----------|
| `minimal-dev` | Basic development | ~$50 | Testing |
| `standard-dev` | Full dev features | ~$100 | Development |
| `production-ec2` | EC2 production | ~$250 | Small teams |
| `production-ecs` | ECS production | ~$450 | Scale/HA |
| `enterprise` | All features | ~$900 | Enterprise |

*Estimated costs for us-east-1

### Key Configuration

Create `.env.librechat` (optional):

```bash
DEPLOYMENT_MODE=ECS              # EC2 or ECS
DEPLOYMENT_ENV=production        # development, staging, production
KEY_PAIR_NAME=my-key            # Required for EC2 mode
ALERT_EMAIL=ops@company.com     # CloudWatch alerts
DOMAIN_NAME=chat.company.com    # Optional custom domain
```

## 📚 Documentation

- **[Quick Reference](QUICK_REFERENCE.md)** - Commands and tips cheatsheet
- **[Documentation Index](docs/README.md)** - All guides organized by topic
- **[Project Structure](PROJECT_STRUCTURE.md)** - Repository organization
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues
- **[Security Guide](docs/SECURITY.md)** - Best practices
- **[Local Testing](docs/LOCAL_TESTING_GUIDE.md)** - Development setup

## 🛠️ Common Operations

### Update LibreChat
```bash
# Redeploy with latest LibreChat version
npm run deploy
```

### View Logs
```bash
# Stream application logs
aws logs tail /aws/librechat --follow
```

### Check Status
```bash
# View stack outputs
aws cloudformation describe-stacks --stack-name LibreChatStack --query 'Stacks[0].Outputs'
```

### Clean Up
```bash
# Remove all resources
./scripts/cleanup.sh
```

## 💰 Cost Estimation

```bash
# Estimate monthly costs
npm run estimate-cost production

# Compare configurations
npm run estimate-cost -- --compare
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `npm test`
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License.

## 🆘 Support

- 📖 Check [documentation](docs/README.md)
- 🐛 Report [issues](https://github.com/your-org/librechat-cdk/issues)
- 💬 Join discussions

---

Built with ❤️ using AWS CDK and TypeScript