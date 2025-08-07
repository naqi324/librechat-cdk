# LibreChat CDK Deployment Guide

## Quick Start - Interactive Deployment

The easiest way to deploy LibreChat is using the interactive deployment wizard:

```bash
./deploy.sh
```

This interactive wizard will:
1. Ask you to choose between ECS or EC2 deployment mode
2. Only ask for a key pair if you choose EC2 mode
3. Guide you through all configuration options
4. Save your configuration for future deployments
5. Deploy your stack automatically

## Deployment Modes

### ECS Mode (Recommended)
- **No SSH key required** ✅
- Containerized deployment using AWS Fargate
- Auto-scaling enabled
- Best for production environments
- Higher availability and reliability

```bash
# Deploy with ECS (no key pair needed)
DEPLOYMENT_MODE=ECS ./deploy.sh
```

### EC2 Mode
- **Requires SSH key pair** ⚠️
- Single virtual machine deployment
- Direct server access via SSH
- Lower cost for small deployments
- Best for development or small teams

```bash
# Deploy with EC2 (key pair required)
DEPLOYMENT_MODE=EC2 KEY_PAIR_NAME=my-key ./deploy.sh
```

## Using Existing Configuration

If you've already configured your deployment, you can reuse the configuration:

```bash
# Use saved configuration from .env file
./deploy.sh --config .env

# Fast deployment mode (uses smaller resources)
./deploy.sh --config .env --fast

# Verbose mode (shows detailed progress)
./deploy.sh --config .env --verbose
```

## Manual Deployment (Advanced)

### ECS Deployment (No Key Pair Required)

```bash
# Set deployment mode
export DEPLOYMENT_MODE=ECS

# Deploy using minimal configuration
npm run synth -- -c configSource=minimal-dev
cdk deploy

# Or deploy with custom settings
cdk deploy \
  -c configSource=custom \
  -c deploymentMode=ECS \
  -c environment=development \
  -c alertEmail=alerts@example.com
```

### EC2 Deployment (Key Pair Required)

```bash
# Create a key pair first (if you don't have one)
aws ec2 create-key-pair --key-name librechat-key \
  --query 'KeyMaterial' --output text > librechat-key.pem
chmod 400 librechat-key.pem

# Set required variables
export DEPLOYMENT_MODE=EC2
export KEY_PAIR_NAME=librechat-key

# Deploy
npm run synth -- -c configSource=minimal-dev
cdk deploy
```

## Configuration Presets

| Preset | Deployment Mode | Key Pair Required | Use Case |
|--------|----------------|-------------------|----------|
| minimal-dev | Either | Only for EC2 | Quick testing, minimal resources |
| standard-dev | Either | Only for EC2 | Development with standard features |
| production-ec2 | EC2 | Yes | Production on single server |
| production-ecs | ECS | No | Production with containers |
| enterprise | ECS | No | Enterprise with all features |

## Environment Variables

### Required for EC2 Mode
- `DEPLOYMENT_MODE=EC2`
- `KEY_PAIR_NAME=your-key-name`

### Required for ECS Mode
- `DEPLOYMENT_MODE=ECS`

### Optional for Both Modes
- `DEPLOYMENT_ENV=development|staging|production`
- `ALERT_EMAIL=alerts@example.com`
- `ENABLE_RAG=true|false`
- `ENABLE_MEILISEARCH=true|false`
- `DOMAIN_NAME=chat.example.com`
- `CERTIFICATE_ARN=arn:aws:acm:...`

## Common Issues and Solutions

### Issue: "Key pair name is required for EC2 deployment"
**Solution**: Either:
1. Switch to ECS mode (no key pair needed): `DEPLOYMENT_MODE=ECS`
2. Create and provide a key pair: `KEY_PAIR_NAME=my-key`
3. Use the interactive wizard: `./deploy.sh`

### Issue: "Deployment mode is required"
**Solution**: Run `./deploy.sh` for interactive setup or set `DEPLOYMENT_MODE=ECS` or `DEPLOYMENT_MODE=EC2`

### Issue: EC2 instance not appearing
**Solution**: Ensure you have:
1. Set `DEPLOYMENT_MODE=EC2`
2. Provided a valid `KEY_PAIR_NAME`
3. The key pair exists in your AWS account

## Tips

1. **Use ECS mode unless you specifically need SSH access** - It's simpler and doesn't require managing SSH keys
2. **Use the interactive wizard** (`./deploy.sh`) for first-time setup
3. **Save your configuration** - The wizard creates a `.env` file you can reuse
4. **For production**, use either `production-ecs` (recommended) or `production-ec2` presets
5. **Check CloudFormation** console for deployment progress and any errors

## Cost Estimates

- **ECS Mode**: ~$150-450/month depending on configuration
- **EC2 Mode**: ~$100-350/month depending on instance size
- **Minimal Dev**: ~$40-50/month (good for testing)

## Next Steps

After deployment:
1. Check CloudFormation outputs for your application URL
2. Access LibreChat at the provided URL
3. For EC2: SSH using `ssh -i your-key.pem ec2-user@<instance-ip>`
4. Monitor logs in CloudWatch
5. Set up your AI provider API keys in the application