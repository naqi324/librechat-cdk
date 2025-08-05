# LibreChat CDK - Quick Deployment Guide

## 🚀 Quick Start (5 Minutes)

```bash
# 1. Clone and setup
git clone <repository-url>
cd librechat-cdk
npm install

# 2. Configure environment
cp .env.example .env.librechat
# Edit .env.librechat:
#   DEPLOYMENT_MODE=EC2
#   KEY_PAIR_NAME=your-key
#   ENABLE_RAG=true

# 3. Create secrets
aws secretsmanager create-secret \
  --name librechat-app-secrets \
  --secret-string '{"jwt_secret":"'$(openssl rand -hex 32)'"}'

# 4. Deploy
npm run wizard  # Follow prompts
```

## 📊 Deployment Options Summary

| Mode | Cost/Month | Setup Time | Best For |
|------|------------|------------|----------|
| Minimal Dev | ~$50 | 10 min | Testing |
| Standard Dev | ~$150 | 15 min | Development |
| Production EC2 | ~$250 | 20 min | Small teams |
| Production ECS | ~$450 | 25 min | Scalability |
| Enterprise | ~$900 | 30 min | Full features |

## ✅ Features Enabled by Default

- ✅ **AWS Bedrock** with Claude Sonnet 4.0 as default
- ✅ **Document Upload** (PDF, Office, Images, Text)
- ✅ **RAG Pipeline** with pgvector
- ✅ **Internet Search** (configure API keys)
- ✅ **Health Monitoring** with CloudWatch
- ✅ **Auto-scaling** (ECS mode)
- ✅ **SSL/HTTPS** (with domain configuration)

## 🔑 Key Commands

```bash
# Deploy environments
npm run deploy:dev      # Development
npm run deploy:staging  # Staging  
npm run deploy:prod     # Production

# Get application URL
aws cloudformation describe-stacks \
  --stack-name LibreChatStack \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerUrl`].OutputValue' \
  --output text

# Check status
cdk diff                # Preview changes
aws logs tail /ecs/librechat --follow  # View logs

# Clean up
cdk destroy --force     # Remove everything
```

## 🎯 Models Available

**Default**: Claude Sonnet 4.0 (Latest)

**All Models**:
- `anthropic.claude-sonnet-4-20250514-v1:0` (Default - Claude Sonnet 4.0)
- `anthropic.claude-opus-4-20250514-v1:0` (Claude Opus 4.0)
- `anthropic.claude-3-5-sonnet-20241022-v2:0` (Claude 3.5 Sonnet)
- `anthropic.claude-3-5-sonnet-20240620-v1:0`
- `anthropic.claude-3-5-haiku-20241022-v1:0`
- `anthropic.claude-3-haiku-20240307-v1:0`
- `anthropic.claude-3-opus-20240229-v1:0`
- `amazon.titan-text-premier-v1:0`
- `amazon.titan-text-express-v1`

## 🔧 Common Configurations

### Enable Internet Search
```bash
aws secretsmanager update-secret \
  --secret-id librechat-app-secrets \
  --secret-string '{
    "google_search_api_key":"YOUR_KEY",
    "google_cse_id":"YOUR_CSE_ID"
  }'
```

### Custom Domain
```bash
cdk deploy \
  -c domainName=chat.company.com \
  -c certificateArn=arn:aws:acm:...
```

### High Availability
```bash
cdk deploy \
  -c configSource=production-ecs \
  -c desiredCount=3 \
  -c maxAzs=3
```

## 📈 Performance Targets

- **Response Time**: < 2 seconds
- **Document Processing**: < 30 seconds
- **Concurrent Users**: 100+ (ECS), 50+ (EC2)
- **Uptime**: 99.9% (Production)
- **Auto-scaling**: Triggers at 70% CPU

## 🚨 Troubleshooting

| Issue | Solution |
|-------|----------|
| Stack fails | Check CloudFormation events |
| Can't access | Verify security groups |
| Slow responses | Scale up instances |
| RAG not working | Check pgvector installation |
| Models not available | Verify Bedrock access |

## 📞 Support

- **Documentation**: See COMPREHENSIVE_ANALYSIS_AND_PLAN.md
- **Runbook**: See DEPLOYMENT_RUNBOOK.md
- **Issues**: GitHub Issues
- **Logs**: CloudWatch Logs

---
*Ready to deploy in minutes with full features enabled!*