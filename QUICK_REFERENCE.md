# LibreChat CDK Quick Reference

## 🚀 Deployment Commands

```bash
# Interactive wizard (recommended)
npm run wizard

# Quick deployments
npm run deploy:dev                    # Development
npm run deploy:staging                # Staging  
npm run deploy:prod                   # Production

# With specific configurations
cdk deploy -c configSource=minimal-dev
cdk deploy -c configSource=production-ec2 -c keyPairName=my-key
cdk deploy -c configSource=production-ecs
cdk deploy -c configSource=enterprise
```

## 🔧 Essential Commands

```bash
# Setup
npm install                           # Install dependencies
npm run build                         # Build TypeScript
npm test                             # Run tests
npm run synth                        # Synthesize CloudFormation

# Operations
npm run estimate-cost production     # Estimate costs
aws logs tail /aws/librechat --follow # View logs
./scripts/cleanup.sh                 # Remove all resources
./scripts/check-resources.sh         # Check remaining resources

# Development
npm run lint                         # Lint code
npm run format                       # Format code
docker-compose up                    # Local testing
```

## 📝 Configuration Files

### `.env.librechat`
```bash
DEPLOYMENT_MODE=ECS              # EC2 or ECS
DEPLOYMENT_ENV=production        # development, staging, production
KEY_PAIR_NAME=my-key            # EC2 SSH key
ALERT_EMAIL=ops@company.com     # Monitoring alerts
DOMAIN_NAME=chat.company.com    # Custom domain
CERTIFICATE_ARN=arn:aws:acm:... # SSL certificate
```

### CDK Context Parameters
```bash
-c configSource=production-ecs   # Deployment preset
-c environment=production        # Environment
-c deploymentMode=ECS           # EC2 or ECS
-c keyPairName=my-key           # EC2 key pair
-c alertEmail=ops@company.com   # Alert email
-c enableRag=true               # Enable RAG
-c enableMeilisearch=true       # Enable search
```

## 🏗️ Architecture Summary

### EC2 Mode
- Single EC2 instance with Docker
- Direct SSH access
- Cost: ~$250/month
- Best for: Small teams, development

### ECS Mode  
- Fargate containers
- Auto-scaling
- No SSH access
- Cost: ~$450/month
- Best for: Production, high availability

## 🚨 Troubleshooting

### Common Issues
```bash
# Stack stuck in rollback
./scripts/cleanup.sh -m rollback-fix -s StackName

# Check deployment status
aws cloudformation describe-stack-events --stack-name LibreChatStack

# View EC2 user data logs
aws ssm start-session --target i-1234567890abcdef0
sudo tail -f /var/log/cloud-init-output.log

# Check ECS task logs
aws logs tail /ecs/librechat --follow
```

### Key Pair Issues
```bash
# Create key pair
aws ec2 create-key-pair --key-name my-key --query 'KeyMaterial' --output text > my-key.pem
chmod 400 my-key.pem

# Import existing key
aws ec2 import-key-pair --key-name my-key --public-key-material fileb://~/.ssh/id_rsa.pub
```

## 📊 Cost Optimization

| Action | Savings |
|--------|---------|
| Use EC2 instead of ECS | ~45% |
| Disable NAT Gateway (dev) | ~$45/month |
| Use t3.medium vs t3.large | ~$30/month |
| Schedule dev shutdown | ~60% |
| Use Spot instances | ~70% |

## 🔗 Important Links

- [Full Documentation](docs/README.md)
- [Security Guide](docs/SECURITY.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Local Testing](docs/LOCAL_TESTING_GUIDE.md)

## 🎯 Feature Flags

| Flag | Default | Description |
|------|---------|-------------|
| `enableRag` | false | PostgreSQL pgvector for RAG |
| `enableMeilisearch` | false | Full-text search |
| `enableDocumentDB` | false | MongoDB compatibility |
| `enableCloudFront` | false | CDN distribution |
| `enableWAF` | false | Web Application Firewall |

## 🛡️ Security Checklist

- [ ] Enable MFA on AWS account
- [ ] Use least-privilege IAM policies
- [ ] Rotate database passwords
- [ ] Enable CloudTrail logging
- [ ] Configure VPC Flow Logs
- [ ] Set up CloudWatch alarms
- [ ] Enable encryption at rest
- [ ] Configure backup retention

## 💡 Tips

1. **Always use the wizard for first deployment**: `npm run wizard`
2. **Test in development first**: `npm run deploy:dev`
3. **Monitor costs**: Check AWS Cost Explorer weekly
4. **Enable alerts**: Set billing and CloudWatch alarms
5. **Regular updates**: Pull latest changes monthly
6. **Clean up unused stacks**: Prevent unexpected charges