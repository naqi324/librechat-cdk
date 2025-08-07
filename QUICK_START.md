# LibreChat CDK Quick Start Guide

## 🚀 5-Minute Setup

### Prerequisites

```bash
# Install required tools
npm install -g aws-cdk@latest
aws configure  # Set up AWS credentials
```

### Quick Deploy

```bash
# Clone and setup
git clone <repository>
cd librechat-cdk
npm install

# Deploy with wizard (easiest)
./deploy.sh

# Or direct deploy
export DEPLOYMENT_MODE=EC2
export KEY_PAIR_NAME=my-key  # EC2 only
npm run deploy:dev
```

## 📋 Command Cheat Sheet

### Essential Commands

| Task | Command |
|------|---------|
| **Deploy dev environment** | `npm run deploy:dev` |
| **Deploy production** | `npm run deploy:prod` |
| **Quick EC2 deploy** | `npm run deploy:quick` |
| **Check costs** | `npm run estimate-cost production` |
| **View changes** | `cdk diff` |
| **Destroy stack** | `cdk destroy` |
| **Run tests** | `npm test` |
| **Build TypeScript** | `npm run build` |

### CDK Context Parameters

```bash
# EC2 Deployment
cdk deploy \
  -c configSource=minimal-dev \
  -c deploymentMode=EC2 \
  -c keyPairName=my-key

# ECS Deployment  
cdk deploy \
  -c configSource=production-ecs \
  -c deploymentMode=ECS \
  -c alertEmail=ops@company.com

# Custom Configuration
cdk deploy \
  -c configSource=custom \
  -c environment=production \
  -c deploymentMode=ECS \
  -c enableRag=true \
  -c enableMeilisearch=true \
  -c domainName=chat.company.com \
  -c certificateArn=arn:aws:acm:...
```

## 🔧 Configuration Presets

### Minimal Development (`minimal-dev`)
```bash
# Cheapest option for testing
cdk deploy -c configSource=minimal-dev -c deploymentMode=EC2 -c keyPairName=dev-key
# Cost: ~$150/month
# Resources: t3.medium EC2, 20GB RDS, no NAT
```

### Standard Development (`standard-dev`)
```bash
# Better performance for team development
cdk deploy -c configSource=standard-dev -c deploymentMode=EC2 -c keyPairName=dev-key
# Cost: ~$250/month
# Resources: t3.large EC2, 50GB RDS, 1 NAT gateway
```

### Production EC2 (`production-ec2`)
```bash
# Production-ready single instance
cdk deploy -c configSource=production-ec2 -c keyPairName=prod-key
# Cost: ~$400/month
# Resources: t3.xlarge EC2, 100GB RDS, backups enabled
```

### Production ECS (`production-ecs`)
```bash
# Scalable container deployment
cdk deploy -c configSource=production-ecs -c alertEmail=ops@company.com
# Cost: ~$600/month
# Resources: 2 Fargate tasks, Aurora, auto-scaling
```

### Enterprise (`enterprise`)
```bash
# Full enterprise features
cdk deploy -c configSource=enterprise -c alertEmail=ops@company.com
# Cost: ~$1200/month
# Resources: 4+ Fargate tasks, Aurora cluster, DocumentDB, full monitoring
```

## 🔑 Environment Variables

### Required
```bash
export DEPLOYMENT_MODE=EC2|ECS
export KEY_PAIR_NAME=my-key       # EC2 mode only
```

### Optional
```bash
export DEPLOYMENT_ENV=development|staging|production
export AWS_REGION=us-east-1
export ALERT_EMAIL=ops@company.com
export DOMAIN_NAME=chat.company.com
export CERTIFICATE_ARN=arn:aws:acm:...
export ALLOWED_IPS=10.0.0.1/32,192.168.1.0/24
```

## 🏗️ Common Scenarios

### Scenario 1: Development Environment
```bash
# Create SSH key
aws ec2 create-key-pair --key-name dev-key --query 'KeyMaterial' --output text > dev-key.pem
chmod 400 dev-key.pem

# Deploy
cdk deploy -c configSource=minimal-dev -c deploymentMode=EC2 -c keyPairName=dev-key

# SSH to instance
aws ec2 describe-instances --filters "Name=tag:Name,Values=LibreChat*" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
ssh -i dev-key.pem ec2-user@<ip-address>
```

### Scenario 2: Production with Custom Domain
```bash
# Request certificate in ACM
aws acm request-certificate --domain-name chat.company.com

# Deploy with domain
cdk deploy \
  -c configSource=production-ecs \
  -c deploymentMode=ECS \
  -c domainName=chat.company.com \
  -c certificateArn=arn:aws:acm:region:account:certificate/id \
  -c hostedZoneId=Z1234567890ABC
```

### Scenario 3: Enable RAG Pipeline
```bash
# Deploy with RAG enabled
cdk deploy \
  -c configSource=production-ec2 \
  -c deploymentMode=EC2 \
  -c keyPairName=prod-key \
  -c enableRag=true
```

## 🔍 Troubleshooting

### Issue: EC2 Instance Not Created
```bash
# Check key pair exists
aws ec2 describe-key-pairs --key-names your-key

# Verify deployment mode
echo $DEPLOYMENT_MODE  # Should be "EC2"

# Check CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name LibreChatStack-development \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

### Issue: Cannot Access Application
```bash
# Get load balancer URL
aws cloudformation describe-stacks \
  --stack-name LibreChatStack-development \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
  --output text

# Check security groups
aws ec2 describe-security-groups \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=LibreChatStack*"
```

### Issue: High Costs
```bash
# Estimate costs before deployment
npm run estimate-cost production

# Use development presets
cdk deploy -c configSource=minimal-dev

# Destroy unused stacks
cdk destroy LibreChatStack-old
```

## 📊 Monitoring

### Get Dashboard URL
```bash
aws cloudformation describe-stacks \
  --stack-name LibreChatStack-production \
  --query 'Stacks[0].Outputs[?OutputKey==`DashboardURL`].OutputValue' \
  --output text
```

### View Logs
```bash
# Application logs
aws logs tail /aws/librechat/application --follow

# EC2 user data logs
aws logs tail /var/log/cloud-init-output --follow

# ECS task logs
aws logs tail /ecs/librechat --follow
```

## 🗑️ Cleanup

### Destroy Single Stack
```bash
cdk destroy LibreChatStack-development
```

### Destroy All Stacks
```bash
cdk destroy --all
```

### Clean Build Artifacts
```bash
npm run clean
rm -rf cdk.out/
```

## 📚 Additional Resources

- [Full Documentation](PROJECT_INDEX.md)
- [API Reference](API_REFERENCE.md)
- [Architecture Guide](PROJECT_STRUCTURE.md)
- [Cost Optimization](scripts/estimate-cost.ts)

## 💡 Tips

1. **Start with `minimal-dev`** for testing
2. **Use the wizard** (`./deploy.sh`) for first-time setup
3. **Always estimate costs** before production deployment
4. **Enable monitoring** for production environments
5. **Use tags** for cost allocation and organization
6. **Backup your SSH keys** for EC2 deployments
7. **Use ECS mode** for production scalability

---

*Quick Start Guide v2.0.0 - Get LibreChat running in minutes!*