# LibreChat CDK Deployment Runbook

## Pre-Deployment Checklist

### 1. Environment Requirements
- [ ] AWS Account configured with appropriate permissions
- [ ] AWS CLI v2 installed and configured (`aws --version`)
- [ ] Node.js 18+ installed (`node --version`)
- [ ] Docker installed and running (`docker --version`)
- [ ] CDK CLI installed (`npm install -g aws-cdk`)
- [ ] Git repository cloned locally

### 2. AWS Account Preparation
- [ ] AWS account has sufficient service quotas:
  - [ ] VPC limit (at least 1 available)
  - [ ] Elastic IP limit (at least 1 for NAT Gateway)
  - [ ] EC2 instance limit (t3.large or larger)
  - [ ] ECS Fargate vCPU limit (at least 8 vCPUs)
  - [ ] RDS instance limit
  - [ ] S3 bucket limit

### 3. Required Secrets Setup
```bash
# Create the main application secrets
aws secretsmanager create-secret \
  --name librechat-app-secrets \
  --description "LibreChat application secrets" \
  --secret-string '{
    "jwt_secret": "'$(openssl rand -hex 32)'",
    "jwt_refresh_secret": "'$(openssl rand -hex 32)'",
    "creds_key": "'$(openssl rand -hex 32)'",
    "creds_iv": "'$(openssl rand -hex 16)'",
    "meilisearch_master_key": "'$(openssl rand -hex 32)'",
    "google_search_api_key": "YOUR_GOOGLE_API_KEY_HERE",
    "google_cse_id": "YOUR_GOOGLE_CSE_ID_HERE",
    "bing_api_key": "YOUR_BING_API_KEY_HERE"
  }'
```

### 4. Environment Configuration
```bash
# Copy and configure environment file
cp .env.example .env.librechat

# Edit .env.librechat with your values:
cat > .env.librechat << EOF
# Deployment Configuration
DEPLOYMENT_ENV=development  # or staging, production
DEPLOYMENT_MODE=EC2  # or ECS
KEY_PAIR_NAME=your-ec2-key-pair  # Required for EC2 mode

# Network Configuration
ALLOWED_IPS=YOUR_IP/32  # Your IP for SSH access
DOMAIN_NAME=chat.yourdomain.com  # Optional
CERTIFICATE_ARN=arn:aws:acm:...  # Optional, for HTTPS

# Feature Flags
ENABLE_RAG=true
ENABLE_MEILISEARCH=true
ENABLE_SHAREPOINT=false

# Monitoring
ALERT_EMAIL=your-email@company.com
EOF
```

## Deployment Steps

### Option 1: Interactive Deployment (Recommended for First Time)

```bash
# Run the interactive deployment wizard
npm run wizard

# Follow the prompts to:
# 1. Select deployment environment (dev/staging/prod)
# 2. Choose deployment mode (EC2/ECS)
# 3. Configure features
# 4. Review and confirm
```

### Option 2: Direct CDK Deployment

#### Step 1: Bootstrap CDK (First Time Only)
```bash
# Bootstrap CDK in your target region
cdk bootstrap aws://ACCOUNT-ID/REGION

# Example:
cdk bootstrap aws://123456789012/us-east-1
```

#### Step 2: Build the Project
```bash
# Install dependencies
npm install

# Build TypeScript
npm run build

# Run tests to verify
npm test
```

#### Step 3: Synthesize and Review
```bash
# Synthesize CloudFormation template
npm run synth

# Review what will be deployed
cdk diff
```

#### Step 4: Deploy

##### For Development (EC2)
```bash
# Deploy with development configuration
npm run deploy:dev

# Or with specific configuration
cdk deploy -c configSource=minimal-dev
```

##### For Production (ECS)
```bash
# Deploy with production configuration
npm run deploy:prod

# Or with specific configuration
cdk deploy -c configSource=production-ecs
```

##### Custom Deployment
```bash
cdk deploy \
  -c configSource=custom \
  -c environment=production \
  -c deploymentMode=ECS \
  -c keyPairName=prod-key \
  -c alertEmail=ops@company.com \
  -c enableRag=true \
  -c enableMeilisearch=true \
  -c domainName=chat.company.com \
  -c certificateArn=arn:aws:acm:us-east-1:123456789012:certificate/abc123
```

## Post-Deployment Verification

### 1. Stack Status Check
```bash
# Check CloudFormation stack status
aws cloudformation describe-stacks \
  --stack-name LibreChatStack \
  --query 'Stacks[0].StackStatus'

# Expected: CREATE_COMPLETE or UPDATE_COMPLETE
```

### 2. Get Application URL
```bash
# Get load balancer URL
aws cloudformation describe-stacks \
  --stack-name LibreChatStack \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerUrl`].OutputValue' \
  --output text
```

### 3. Service Health Checks

#### For EC2 Deployment
```bash
# Check EC2 instance status
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=LibreChat-Instance" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

aws ec2 describe-instance-status \
  --instance-ids $INSTANCE_ID \
  --query 'InstanceStatuses[0].InstanceStatus.Status'

# SSH into instance (replace with your key path)
ssh -i ~/.ssh/your-key.pem ec2-user@<instance-ip>

# Check Docker containers
docker ps

# Check logs
docker logs librechat-api
docker logs rag-api
```

#### For ECS Deployment
```bash
# Check ECS service status
aws ecs describe-services \
  --cluster librechat-cluster \
  --services librechat-service \
  --query 'services[0].runningCount'

# Check task health
aws ecs describe-tasks \
  --cluster librechat-cluster \
  --tasks $(aws ecs list-tasks --cluster librechat-cluster --service-name librechat-service --query 'taskArns[0]' --output text) \
  --query 'tasks[0].healthStatus'

# View logs
aws logs tail /ecs/librechat --follow
```

### 4. Database Verification
```bash
# Check RDS status
aws rds describe-db-instances \
  --query 'DBInstances[?contains(DBInstanceIdentifier, `librechat`)].DBInstanceStatus'

# Check database initialization
aws logs tail /aws/lambda/LibreChat-InitPgFn --since 5m
```

## Feature Testing Checklist

### 1. Basic Functionality
- [ ] Access the application URL in browser
- [ ] Login page loads without errors
- [ ] Can create a new account (if registration enabled)
- [ ] Can log in successfully

### 2. Bedrock Integration
- [ ] Claude Sonnet 4.0 appears as default model
- [ ] Can select different Bedrock models
- [ ] Models respond to queries
- [ ] Streaming responses work

### 3. Document Upload
- [ ] Can upload PDF files
- [ ] Can upload Office documents
- [ ] Can upload images
- [ ] Files are processed successfully
- [ ] Can query uploaded content

### 4. RAG Pipeline
- [ ] Documents are indexed properly
- [ ] RAG context appears in responses
- [ ] Similarity search works
- [ ] Can retrieve relevant chunks

### 5. Internet Search
- [ ] Google search returns results (if configured)
- [ ] Bing search returns results (if configured)
- [ ] Search results integrate into responses
- [ ] Web browser tool works

### 6. Performance
- [ ] Page load time < 3 seconds
- [ ] First response time < 5 seconds
- [ ] Can handle multiple concurrent users
- [ ] Auto-scaling triggers (ECS only)

## Monitoring and Logs

### CloudWatch Dashboards
```bash
# Open CloudWatch dashboard
aws cloudwatch get-dashboard \
  --dashboard-name LibreChat-Dashboard \
  --query 'DashboardBody' | jq -r . | jq .
```

### Application Logs
```bash
# EC2 logs
aws logs tail /aws/ec2/librechat --follow

# ECS logs
aws logs tail /ecs/librechat --follow
aws logs tail /ecs/rag-api --follow
aws logs tail /ecs/meilisearch --follow

# Lambda logs (database initialization)
aws logs tail /aws/lambda/LibreChat-InitPgFn
```

### Metrics to Monitor
- CPU utilization (target: < 70%)
- Memory utilization (target: < 80%)
- Request count and latency
- Error rate (target: < 1%)
- Database connections
- S3 storage usage

## Troubleshooting

### Common Issues and Solutions

#### 1. Stack Creation Failed
```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name LibreChatStack \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'

# Common causes:
# - Missing IAM permissions
# - Service quota limits
# - Invalid configuration
```

#### 2. Database Connection Issues
```bash
# Check security groups
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=*postgres*" \
  --query 'SecurityGroups[].IpPermissions'

# Test database connectivity
psql -h <rds-endpoint> -U postgres -d librechat
```

#### 3. Container Health Check Failures
```bash
# For EC2
docker logs librechat-api --tail 100
docker exec librechat-api curl -f http://localhost:3080/health

# For ECS
aws ecs describe-tasks \
  --cluster librechat-cluster \
  --tasks <task-arn> \
  --query 'tasks[0].containers[].healthStatus'
```

#### 4. RAG API Not Working
```bash
# Check RAG container logs
docker logs rag-api --tail 100

# Test RAG health endpoint
curl http://<load-balancer-url>:8000/health

# Verify pgvector extension
psql -h <rds-endpoint> -U postgres -d librechat -c "\dx"
```

## Rollback Procedures

### Quick Rollback
```bash
# Revert to previous version
cdk deploy --rollback

# Or manually update task definition (ECS)
aws ecs update-service \
  --cluster librechat-cluster \
  --service librechat-service \
  --task-definition librechat-task:PREVIOUS_VERSION
```

### Complete Teardown
```bash
# Destroy all resources (WARNING: This deletes everything)
cdk destroy --force

# Clean up remaining resources
aws s3 rm s3://librechat-uploads-bucket --recursive
aws secretsmanager delete-secret \
  --secret-id librechat-app-secrets \
  --force-delete-without-recovery
```

## Maintenance Tasks

### 1. Update LibreChat Version
```bash
# Update Docker image in code
# Edit lib/constructs/compute/ec2-deployment.ts or ecs-deployment.ts
# Change: ghcr.io/danny-avila/librechat:latest
# To: ghcr.io/danny-avila/librechat:v0.7.4

# Deploy update
cdk deploy
```

### 2. Scale Resources
```bash
# For ECS - Update desired count
aws ecs update-service \
  --cluster librechat-cluster \
  --service librechat-service \
  --desired-count 5

# For EC2 - Change instance type
# Edit config/deployment-config.ts
# Update instanceType: 't3.xlarge'
cdk deploy
```

### 3. Backup Database
```bash
# Create manual snapshot
aws rds create-db-snapshot \
  --db-instance-identifier librechat-postgres \
  --db-snapshot-identifier librechat-backup-$(date +%Y%m%d)
```

## Security Best Practices

1. **Secrets Management**
   - Rotate secrets regularly
   - Never commit secrets to git
   - Use AWS Secrets Manager for all sensitive data

2. **Network Security**
   - Restrict SSH access to specific IPs
   - Use private subnets for databases
   - Enable VPC Flow Logs

3. **Application Security**
   - Keep Docker images updated
   - Enable AWS WAF for production
   - Implement rate limiting

4. **Monitoring**
   - Set up CloudWatch alarms
   - Enable AWS GuardDuty
   - Review access logs regularly

## Support and Resources

- LibreChat Documentation: https://www.librechat.ai/docs
- AWS CDK Documentation: https://docs.aws.amazon.com/cdk/
- CloudFormation Events: Check for detailed error messages
- Application Logs: Primary source for debugging

## Contact Information

For issues or questions:
- GitHub Issues: [Your Repository]/issues
- AWS Support: Via AWS Console
- Team Slack: #librechat-deployment