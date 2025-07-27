# Deployment Optimization Guide

## Overview

This guide explains how to optimize LibreChat CDK deployment speed and configure resource sizes.

## Deployment Speed

### Why Deployments Take Time

1. **RDS Database Creation (5-10 minutes)**
   - Primary bottleneck
   - AWS provisions hardware, installs PostgreSQL, configures networking
   - Cannot be significantly accelerated

2. **VPC and Networking (2-3 minutes)**
   - Creates subnets across availability zones
   - Sets up NAT gateways, route tables, security groups

3. **ECS/EC2 Resources (2-3 minutes)**
   - Launches instances, configures containers
   - Downloads Docker images

4. **Lambda Functions (~1 minute)**
   - Package and upload code
   - Create execution roles

### Fast Deployment Options

#### 1. Use Smaller Resources Initially

```bash
# Set resource size to extra small for fastest deployment
RESOURCE_SIZE=xs npm run deploy

# Or use the fast deployment script
npm run deploy:fast
```

This uses:
- t3.micro instances
- db.t3.micro RDS
- Minimal storage
- Deploys in ~10 minutes instead of 15-20

#### 2. CDK Hotswap (For Updates)

For code changes without infrastructure changes:

```bash
# Deploys Lambda/ECS changes in <2 minutes
npx cdk deploy --hotswap
```

#### 3. Parallel Stack Deployment

```bash
# Deploy with higher concurrency
npx cdk deploy --concurrency 10
```

## Resource Sizing

### Available Sizes

| Size | Users | EC2 Instance | ECS CPU/Memory | RDS Instance | Monthly Cost |
|------|-------|--------------|----------------|--------------|--------------|
| xs | 1-5 | t3.micro | 256/512 MB | db.t3.micro | ~$50 |
| small | 5-20 | t3.small | 512/1 GB | db.t3.small | ~$120 |
| medium | 20-100 | t3.large | 1024/2 GB | db.t3.medium | ~$300 |
| large | 100-500 | t3.xlarge | 2048/4 GB | db.r6g.large | ~$800 |
| xl | 500+ | t3.2xlarge | 4096/8 GB | db.r6g.xlarge | ~$2000 |

### Configuration Methods

#### 1. Setup Script (Recommended)

The setup script will prompt you:

```bash
./setup.sh
# Select resource size when prompted
```

#### 2. Environment Variable

```bash
export RESOURCE_SIZE=large
npm run deploy
```

#### 3. .env File

```env
RESOURCE_SIZE=large
```

### Autoscaling

#### ECS Autoscaling (Enabled by Default)

- **CPU-based**: Scales when CPU > 70%
- **Memory-based**: Scales when memory > 75%
- **Min/Max Tasks**: Based on resource size
  - Small: 1-3 tasks
  - Medium: 1-5 tasks
  - Large: 2-10 tasks
  - XL: 3-20 tasks

#### RDS Autoscaling

RDS storage autoscaling is enabled for medium+ sizes:
- Automatically grows storage when < 10% free
- No downtime during expansion

#### EC2 Autoscaling

Not implemented by default. EC2 deployments are fixed-size.

## Optimization Strategies

### 1. Start Small, Scale Up

```bash
# Initial deployment with small resources
RESOURCE_SIZE=small npm run deploy

# Later, update to larger size
RESOURCE_SIZE=large npm run deploy
```

### 2. Use ECS for Better Scaling

ECS mode provides:
- Automatic scaling based on load
- No SSH key management
- Better resource utilization
- Rolling updates without downtime

### 3. Regional Considerations

Deploy in regions closer to users:
- us-east-1: US East Coast
- us-west-2: US West Coast
- eu-west-1: Europe
- ap-southeast-1: Asia Pacific

### 4. Skip Optional Features

For faster initial deployment:

```bash
# Disable optional features
ENABLE_RAG=false ENABLE_MEILISEARCH=false npm run deploy
```

## Monitoring Resource Usage

### CloudWatch Metrics

After deployment, monitor:
- CPU utilization
- Memory usage
- Database connections
- Request latency

### Cost Optimization

Use AWS Cost Explorer to:
- Track actual costs vs estimates
- Identify underutilized resources
- Set up billing alerts

## Troubleshooting Slow Deployments

### 1. Check AWS Service Health

```bash
# Check for AWS service issues
aws health describe-events --region us-east-1
```

### 2. Clean Failed Deployments

```bash
# Remove failed stacks blocking deployment
./scripts/cleanup-failed.sh
```

### 3. Use Different Availability Zones

Some AZs may have capacity issues:

```bash
# Specify different AZs
export VPC_AZS="us-east-1a,us-east-1c"
npm run deploy
```

## Best Practices

1. **Development**: Use `xs` or `small` sizes
2. **Staging**: Use `medium` with same config as production
3. **Production**: Start with `medium`, scale based on metrics
4. **Cost Control**: Set up AWS Budgets alerts
5. **Updates**: Use CDK hotswap for code changes

## FAQ

**Q: Can I change resource sizes after deployment?**
A: Yes, update RESOURCE_SIZE and redeploy. Some resources require brief downtime.

**Q: Which deployment mode is faster?**
A: EC2 is slightly faster to deploy initially, but ECS provides better scaling.

**Q: Can I speed up RDS creation?**
A: No, this is an AWS limitation. Consider using Aurora Serverless for faster scaling.

**Q: Should I use Multi-AZ for production?**
A: Yes, it's enabled automatically for large+ sizes. Adds ~2 minutes to deployment.

**Q: How do I minimize costs?**
A: Use smallest viable size, enable autoscaling, use spot instances for non-critical workloads.