# LibreChat CDK Deployment Guide

## Quick Start

The easiest way to get started is to run the setup wizard:

```bash
./scripts/setup-deployment.sh
```

This will guide you through configuration and create a `.env` file with your settings.

## Key Pair Requirements

### EC2 Deployment (Default)
EC2 deployments **require** an AWS key pair for SSH access. You must create one before deployment:

```bash
# Create a key pair using AWS CLI
aws ec2 create-key-pair --key-name librechat-key --query 'KeyMaterial' --output text > librechat-key.pem
chmod 400 librechat-key.pem
```

### ECS Deployment
ECS deployments do **NOT** require a key pair. To use ECS mode:

```bash
export DEPLOYMENT_MODE=ECS
npm run deploy
```

## Configuration Methods

### Method 1: Environment Variables (.env file)
Create a `.env` file in the root directory:

```bash
# For EC2 deployment
DEPLOYMENT_MODE=EC2
KEY_PAIR_NAME=your-key-pair-name
DEPLOYMENT_ENV=development
ALERT_EMAIL=alerts@example.com

# For ECS deployment
DEPLOYMENT_MODE=ECS
DEPLOYMENT_ENV=development
ALERT_EMAIL=alerts@example.com
```

### Method 2: CDK Context
Pass configuration via command line:

```bash
npm run deploy -- \
  -c keyPairName=your-key-pair-name \
  -c alertEmail=alerts@example.com
```

### Method 3: Environment Variables
Export variables before deployment:

```bash
export KEY_PAIR_NAME=your-key-pair-name
export DEPLOYMENT_MODE=EC2
npm run deploy
```

## Common Deployment Scenarios

### Development with EC2
```bash
# Requires key pair
npm run deploy:dev -- -c keyPairName=my-dev-key
```

### Development with ECS
```bash
# No key pair required
export DEPLOYMENT_MODE=ECS
npm run deploy:dev
```

### Production EC2
```bash
# Cost-optimized, requires key pair
npm run deploy:prod -- \
  -c configSource=production-ec2 \
  -c keyPairName=prod-key \
  -c alertEmail=ops@company.com
```

### Production ECS
```bash
# Scalable, no key pair required
npm run deploy:prod -- \
  -c configSource=production-ecs \
  -c alertEmail=ops@company.com
```

## Troubleshooting

### "Key pair name is required" Error
This error occurs when deploying in EC2 mode without specifying a key pair.

**Solutions:**
1. Create a key pair and provide its name
2. Switch to ECS deployment mode
3. Run the setup wizard: `./scripts/setup-deployment.sh`

### Pre-deployment Checks
The deployment will automatically run configuration checks. To run them manually:

```bash
node scripts/check-deployment-config.js
```

## Configuration Files

- `.env.example` - Basic example configuration
- `config/development.env.example` - Development EC2 example
- `config/ecs-deployment.env.example` - ECS deployment example
- `config/deployment-config.ts` - Full configuration options

## Features Configuration

Enable or disable features in your `.env` file:

```bash
ENABLE_RAG=true
ENABLE_MEILISEARCH=false
ENABLE_SHAREPOINT=false
```

## Cost Considerations

- **EC2**: Lower cost for consistent workloads
- **ECS**: Better for variable workloads with auto-scaling
- **Development**: Use minimal configurations to reduce costs
- **Production**: Enable monitoring and backups

For detailed cost analysis, see the main README.md file.