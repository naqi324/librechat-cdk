# LibreChat CDK Deployment

Enterprise-grade AWS CDK deployment for LibreChat with both EC2 and ECS options.

## Features

✅ **Deployment Options**
- EC2: Single instance with Docker Compose (cost-effective)
- ECS: Fargate containers with auto-scaling (production-grade)

✅ **Core Capabilities**
- **Amazon Bedrock Integration**: Claude Sonnet 4 as default model (with all available Bedrock models)
- **Optional RAG Pipeline**: PostgreSQL with pgvector when enabled
- **File Uploads**: Support for documents, images, and data files
- **Web Search**: Google and Bing search integration
- **Secure Storage**: S3 for files, Secrets Manager for credentials

## Quick Start

### Prerequisites
- AWS CLI configured with credentials
- Node.js 18+ and npm 9+
- AWS CDK CLI: `npm install -g aws-cdk`
- EC2 Key Pair (for EC2 deployments)

### 1. Clone and Install
```bash
git clone https://github.com/naqi324/librechat-cdk.git
cd librechat-cdk
npm install
```

### 2. Configure Environment
```bash
# For EC2 deployments
export KEY_PAIR_NAME=your-ec2-key

# Optional configurations
export ALERT_EMAIL=ops@company.com
export DOMAIN_NAME=chat.company.com
```

### 3. Deploy

```bash
# Quick development deployment (no confirmations, minimal cost)
./deploy.sh --dev --no-rag -y

# Standard development with RAG
./deploy.sh --dev --rag

# Staging environment
./deploy.sh --staging

# Production deployment
./deploy.sh --prod

# See all options
./deploy.sh --help
```

## Configuration Options

### Deployment Presets

| Preset | Mode | RAG | Cost/Month | Use Case |
|--------|------|-----|------------|----------|
| minimal-dev | EC2 | ❌ | ~$50 | Development, testing |
| standard-dev | EC2 | ✅ | ~$110 | Development with RAG |
| production-ec2 | EC2 | ✅ | ~$250 | Small production |
| production-ecs | ECS | ✅ | ~$450 | Scalable production |

### Custom Configuration
```bash
cdk deploy \
  -c configSource=custom \
  -c deploymentMode=EC2 \
  -c enableRag=false \
  -c enableMeilisearch=false
```

## Available Models (Bedrock)

**Default**: Claude Sonnet 4 (`anthropic.claude-sonnet-4-20250514-v1:0`)

**Additional Models**:
- Claude 3 Haiku: `anthropic.claude-3-haiku-20240307-v1:0`
- Claude Instant: `anthropic.claude-instant-v1`
- Llama 3.1: `meta.llama3-1-70b-instruct-v1:0`
- Mistral Large: `mistral.mistral-large-2407-v1:0`

## Architecture

### EC2 Deployment
- Single EC2 instance running Docker Compose
- MongoDB for chat storage
- Optional PostgreSQL for RAG (when enabled)
- Application Load Balancer
- Auto-recovery on instance failure

### ECS Deployment
- Fargate containers with auto-scaling
- Aurora Serverless PostgreSQL (when RAG enabled)
- MongoDB or DocumentDB
- Application Load Balancer
- Multi-AZ for high availability

## Web Search Setup

To enable web search, add API keys to AWS Secrets Manager:

```bash
aws secretsmanager update-secret \
  --secret-id librechat-app-secrets \
  --secret-string '{
    "google_search_api_key": "YOUR_API_KEY",
    "google_cse_id": "YOUR_CSE_ID",
    "bing_api_key": "YOUR_BING_KEY"
  }'
```

## File Upload Configuration

Files are automatically configured with:
- Maximum file size: 200MB per file
- Total size limit: 1GB
- Supported formats: PDF, Word, Excel, images, CSV, JSON, XML

## Cost Optimization

### Save on Development
```bash
# Minimal setup without RAG (~$50/month)
cdk deploy -c configSource=minimal-dev
```

### Save on Production
```bash
# EC2 instead of ECS (~$250 vs ~$450/month)
cdk deploy -c configSource=production-ec2
```

## Management Commands

### Check Status
```bash
aws cloudformation describe-stacks \
  --stack-name LibreChatStack-development
```

### View Logs
```bash
aws logs tail /aws/librechat --follow
```

### Update Deployment
```bash
cdk diff  # Preview changes
cdk deploy  # Apply updates
```

### Destroy Stack
```bash
cdk destroy
```

## Security Features

- 🔒 All data encrypted at rest (S3, RDS, Secrets Manager)
- 🔒 TLS/SSL for all connections
- 🔒 IAM roles with least privilege
- 🔒 Private subnets for databases
- 🔒 Security groups with minimal access
- 🔒 Secrets rotation support

## Troubleshooting

### Common Issues

**CDK Bootstrap Required**
```bash
cdk bootstrap aws://ACCOUNT-ID/REGION
```

**EC2 Key Pair Missing**
```bash
aws ec2 create-key-pair --key-name my-key \
  --query 'KeyMaterial' --output text > my-key.pem
```

**Check Container Logs (EC2)**
```bash
ssh -i my-key.pem ec2-user@<instance-ip>
sudo docker compose logs -f
```

## Support

- Issues: https://github.com/naqi324/librechat-cdk/issues
- LibreChat Docs: https://www.librechat.ai/docs

## License

MIT - See LICENSE file for details