# LibreChat AWS CDK Deployment

> 🚀 **One-click enterprise deployment of LibreChat with AWS Bedrock, PostgreSQL pgvector, and RAG**

## 📦 What's Included

This CDK application provides a complete Infrastructure as Code solution for deploying LibreChat on AWS. Get a production-ready AI chat platform running in 20 minutes!

### ✨ Key Features

- **Complete Infrastructure as Code** - All AWS resources defined in TypeScript
- **Multiple Deployment Options** - AWS Console, CDK CLI, or one-click URL
- **Automated Setup** - LibreChat containers auto-configured and started
- **Enterprise Ready** - Security, monitoring, and scalability built-in
- **Cost Optimized** - ~$220-250/month for a complete solution

### 🏗️ Resources Created

- **Networking**: VPC with public/private subnets across 2 AZs
- **Compute**: EC2 instance (t3.xlarge) with automated LibreChat setup
- **Database**: RDS PostgreSQL with pgvector extension for RAG
- **Storage**: S3 bucket for document storage with encryption
- **Load Balancing**: Application Load Balancer with health checks
- **Security**: IAM roles, security groups, and Secrets Manager
- **Monitoring**: CloudWatch alarms and SNS notifications

### 📁 Project Structure

See [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) for detailed file descriptions and organization.

## 🚀 Quick Start - Console Deployment

The fastest way to deploy LibreChat - no command line required!

### Step 1: Download the CDK Package
```bash
git clone https://github.com/your-org/librechat-cdk.git
cd librechat-cdk
```

### Step 2: Generate CloudFormation Template
```bash
npm install
npm run build
cdk synth > librechat-cloudformation.yaml
```

### Step 3: Deploy via AWS Console
1. Go to [AWS CloudFormation Console](https://console.aws.amazon.com/cloudformation)
2. Click **Create stack** → **With new resources**
3. Choose **Upload a template file**
4. Upload `librechat-cloudformation.yaml`
5. Configure parameters:
   - **Stack name**: LibreChat-Production
   - **AlertEmail**: your-email@domain.com
   - **KeyName**: Select your EC2 key pair
   - **AllowedSSHIP**: Your IP (x.x.x.x/32)
6. Review and create (acknowledge IAM resources)

### Step 4: Access LibreChat
- Wait 15-20 minutes for deployment
- Find the URL in CloudFormation **Outputs** tab
- Create your first user account

## 📋 Prerequisites

Before deploying, ensure you have:

1. **AWS Account with Bedrock Access**
   - Go to [AWS Bedrock console](https://console.aws.amazon.com/bedrock/)
   - Request access to Anthropic Claude models
   - Wait for approval (usually instant)

2. **EC2 Key Pair** (for SSH access)
   - Create in [EC2 console](https://console.aws.amazon.com/ec2/) > Key Pairs
   - Download and save the .pem file

3. **For CLI Deployment**:
   ```bash
   npm install -g aws-cdk
   aws configure
   ```

## 🎯 Deployment Options

### Option 1: One-Click Deploy URL

Create a shareable deployment link:

```bash
./scripts/create-one-click-deploy.sh us-east-1

# This generates a URL like:
# https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/new?stackName=LibreChat&templateURL=...
```

Share this URL with others for instant deployment!

### Option 2: Deploy via CDK CLI

```bash
# First time only - bootstrap CDK
cdk bootstrap aws://ACCOUNT-NUMBER/REGION

# Deploy with interactive prompts
./scripts/deploy.sh

# Or deploy directly
cdk deploy \
  --parameters AlertEmail=admin@company.com \
  --parameters KeyName=my-key-pair \
  --parameters AllowedSSHIP=203.0.113.1/32
```

### Option 3: Deploy via CloudFormation CLI

```bash
# Create parameters file
cat > parameters.json << EOF
[
  {"ParameterKey": "AlertEmail", "ParameterValue": "admin@company.com"},
  {"ParameterKey": "KeyName", "ParameterValue": "my-key-pair"},
  {"ParameterKey": "AllowedSSHIP", "ParameterValue": "203.0.113.1/32"}
]
EOF

# Deploy stack
aws cloudformation create-stack \
  --stack-name LibreChat-Production \
  --template-body file://librechat-cloudformation.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_IAM
```

### Option 4: AWS Service Catalog (For Organizations)

Create a one-click product for your organization:

```bash
# Upload template to S3
aws s3 cp librechat-cloudformation.yaml s3://your-bucket/templates/

# Create Service Catalog product
aws servicecatalog create-product \
  --name "LibreChat Enterprise" \
  --owner "IT Department" \
  --product-type CLOUD_FORMATION_TEMPLATE \
  --provisioning-artifact-parameters file://product-config.json
```

## 🔧 Configuration & Customization

### Stack Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| AlertEmail | Email for CloudWatch alarms | - | No |
| KeyName | EC2 SSH key pair name | - | Yes |
| AllowedSSHIP | IP range for SSH access | 0.0.0.0/0 | No |

### Advanced Customization via CDK Context

```bash
# Deploy with larger instance
cdk deploy --context instanceType=t3.2xlarge

# Deploy with custom database
cdk deploy --context dbInstanceClass=db.t3.large

# Enable SharePoint integration
cdk deploy \
  --context enableSharePoint=true \
  --context sharePointTenantId=YOUR-TENANT-ID \
  --context sharePointClientId=YOUR-CLIENT-ID \
  --context sharePointClientSecret=YOUR-SECRET \
  --context sharePointSiteUrl=https://company.sharepoint.com/sites/docs
```

### Infrastructure Customization

Edit `lib/librechat-stack.ts` to modify:
- VPC CIDR ranges and subnet configuration
- Instance types and storage sizes
- Security group rules
- Monitoring thresholds
- Backup schedules
- Additional AWS services

## 📊 Cost Analysis

### Estimated Monthly Costs

| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| EC2 | t3.xlarge (4 vCPU, 16GB RAM) | ~$120 |
| RDS | db.t3.medium PostgreSQL | ~$70 |
| ALB | Application Load Balancer | ~$20 |
| S3 | Document storage | ~$5-20 |
| **Total** | **Infrastructure** | **~$220-250** |


### Cost Optimization Tips

1. **Development Environment**
   ```bash
   cdk deploy --context instanceType=t3.medium --context dbInstanceClass=db.t3.micro
   ```

2. **Auto-Stop/Start Schedule**
   ```bash
   # Add to crontab for non-production
   0 19 * * 1-5 aws ec2 stop-instances --instance-ids $INSTANCE_ID
   0 7 * * 1-5 aws ec2 start-instances --instance-ids $INSTANCE_ID
   ```

3. **Monitor Usage**
   ```bash
   aws ce get-cost-and-usage \
     --time-period Start=2025-01-01,End=2025-01-31 \
     --granularity MONTHLY \
     --metrics "UnblendedCost" \
     --group-by Type=DIMENSION,Key=SERVICE
   ```

## 🔐 Security Features

- **Encryption**: All data encrypted at rest (RDS, S3) and in transit (TLS)
- **Network Security**: Private subnets for database, security groups with least privilege
- **IAM Roles**: No hardcoded credentials, using AWS best practices
- **Secrets Manager**: Automated password generation and rotation ready
- **Monitoring**: CloudWatch alarms for security events
- **Compliance Ready**: Supports HIPAA, SOC2, and GDPR requirements

## 📋 Post-Deployment Setup

### 1. Access LibreChat

After deployment completes (~20 minutes):

1. Find the Load Balancer URL in CloudFormation Outputs
2. Access: `http://YOUR-ALB-DNS-NAME`
3. Create admin account:
   ```bash
   curl -X POST http://YOUR-ALB-DNS/api/auth/register \
     -H "Content-Type: application/json" \
     -d '{
       "email": "admin@yourdomain.com",
       "password": "SecurePassword123!",
       "name": "Admin User"
     }'
   ```

### 2. Configure HTTPS (Required for Production)

#### Option A: AWS Certificate Manager with Route 53
```bash
# Request certificate
aws acm request-certificate \
  --domain-name chat.yourdomain.com \
  --validation-method DNS

# After validation, update ALB listener
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTPS \
  --port 443 \
  --certificates CertificateArn=$CERT_ARN \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN
```

#### Option B: Use CloudFlare
- Add your domain to CloudFlare
- Point to ALB DNS name
- Enable "Full SSL/TLS"

### 3. Configure SharePoint Integration (Optional)

1. **Create Azure App Registration**
   - Go to Azure Portal > App registrations
   - Create new registration
   - Add Microsoft Graph permissions: `Files.Read.All`, `Sites.Read.All`
   - Create client secret

2. **Update LibreChat Configuration**
   ```bash
   # SSH to instance
   ssh -i your-key.pem ubuntu@INSTANCE-IP

   # Add to .env file
   echo "SHAREPOINT_TENANT_ID=your-tenant-id" >> /opt/LibreChat/.env
   echo "SHAREPOINT_CLIENT_ID=your-client-id" >> /opt/LibreChat/.env
   echo "SHAREPOINT_CLIENT_SECRET=your-secret" >> /opt/LibreChat/.env

   # Restart containers
   cd /opt/LibreChat && docker-compose restart
   ```

### 4. Set Up Monitoring Dashboard

Create a CloudWatch dashboard for key metrics:

```bash
aws cloudwatch put-dashboard \
  --dashboard-name LibreChat-Monitoring \
  --dashboard-body file://cloudwatch-dashboard.json
```

## 🧪 Testing & Validation

### Automated Tests
```bash
# Run CDK unit tests
npm test

# Validate CloudFormation template
cdk synth --quiet
cfn-lint librechat-cloudformation.yaml
```

### Manual Validation Checklist
- [ ] Access LibreChat URL successfully
- [ ] Create and login with user account
- [ ] Select and use Bedrock models
- [ ] Upload and query documents (RAG)
- [ ] Check CloudWatch alarms are active
- [ ] Verify SSL certificate (if configured)
- [ ] Test file uploads to S3
- [ ] Monitor costs in Cost Explorer

### Load Testing
```bash
# Install artillery
npm install -g artillery

# Run load test
artillery quick --count 50 --num 10 http://YOUR-ALB-DNS/health
```

## 🛠️ Maintenance & Operations

### Updating LibreChat

```bash
# SSH to instance
ssh -i your-key.pem ubuntu@INSTANCE-IP

# Update containers
cd /opt/LibreChat
docker-compose pull
docker-compose down
docker-compose up -d
```

### Backup & Recovery

Automated backups are configured for:
- **RDS**: 7-day retention with point-in-time recovery
- **S3**: Versioning enabled

Manual backup:
```bash
# Database backup
aws rds create-db-snapshot \
  --db-instance-identifier librechat-postgres \
  --db-snapshot-identifier manual-backup-$(date +%Y%m%d)

# S3 backup
aws s3 sync s3://source-bucket s3://backup-bucket
```

### Monitoring & Alerts

View CloudWatch dashboards:
```bash
# Get metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --statistics Average \
  --start-time 2025-01-01T00:00:00Z \
  --end-time 2025-01-02T00:00:00Z \
  --period 3600
```

## 🧹 Cleanup

To avoid ongoing charges, remove all resources:

```bash
# Option 1: Via CDK
cdk destroy

# Option 2: Via CloudFormation Console
# Select stack → Delete

# Option 3: Via CLI
aws cloudformation delete-stack --stack-name LibreChat-Production

# Option 4: Use cleanup script
./scripts/cleanup.sh
```

## 🆘 Troubleshooting

### Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| Stack creation fails | Check CloudFormation Events tab for specific error |
| Can't access LibreChat | Wait 10 minutes, check security group, verify ALB target health |
| Bedrock models not available | Ensure Bedrock access is enabled in AWS Console |
| High costs | Set up AWS Budgets, use smaller instances for dev/test |
| Database connection errors | Check security groups, verify RDS is available |

### Debug Commands

```bash
# View instance logs
aws ec2 get-console-output --instance-id $INSTANCE_ID

# Check container status
ssh -i key.pem ubuntu@INSTANCE-IP "docker ps"

# View application logs
ssh -i key.pem ubuntu@INSTANCE-IP "docker logs librechat"

# Test local health
ssh -i key.pem ubuntu@INSTANCE-IP "curl localhost:3080/health"
```

## 📚 Additional Resources

- **LibreChat Documentation**: https://www.librechat.ai/docs
- **AWS CDK Reference**: https://docs.aws.amazon.com/cdk/
- **Project Structure**: See [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)
- **GitHub Issues**: https://github.com/danny-avila/LibreChat/issues
- **Community Discord**: https://discord.librechat.ai

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

## 📄 License

This CDK application is provided under the MIT License. LibreChat itself is also MIT licensed.

---

**Ready to deploy?** Choose your preferred method above and have LibreChat running in under 30 minutes! 🚀
