# LibreChat CDK Project Index

> **AWS CDK Infrastructure for LibreChat Enterprise Deployment**  
> Version: 2.0.0 | AWS CDK: 2.142.1 | TypeScript

## 📚 Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Components](#components)
- [Configuration](#configuration)
- [Deployment Modes](#deployment-modes)
- [API Reference](#api-reference)
- [Scripts & Commands](#scripts--commands)
- [Testing](#testing)
- [Cost Analysis](#cost-analysis)

## Overview

Enterprise-grade AWS CDK deployment for LibreChat with support for:
- 🚀 **Two deployment modes**: EC2 (simple) and ECS Fargate (scalable)
- 🤖 **AWS Bedrock**: Integration with Claude, Llama, and other AI models
- 🔍 **RAG Pipeline**: pgvector for semantic search and document processing
- 🔒 **Enterprise Security**: Encryption, IAM roles, VPC isolation
- 📊 **Monitoring**: CloudWatch dashboards and alarms
- 💰 **Cost Optimization**: Environment-specific resource sizing

## Quick Start

```bash
# Interactive deployment wizard (recommended)
./deploy.sh

# Direct deployment with configuration
cdk deploy -c configSource=minimal-dev -c deploymentMode=EC2 -c keyPairName=my-key

# Quick development deployment
npm run deploy:quick
```

## Architecture

### Stack Structure

```
LibreChatStack (Main)
├── VpcConstruct           # Network infrastructure
├── DatabaseConstruct       # RDS PostgreSQL / DocumentDB
├── StorageConstruct        # S3 buckets, EFS
├── ComputeConstruct        # EC2 or ECS deployment
│   ├── EC2Deployment       # Single instance with Docker
│   └── ECSDeployment       # Fargate containers
├── MonitoringConstruct     # CloudWatch, SNS
├── AuditConstruct          # CloudTrail, Config
└── ComplianceConstruct     # HIPAA compliance resources
```

### File Structure

```
librechat-cdk/
├── bin/
│   └── librechat.ts              # CDK app entry point
├── lib/
│   ├── librechat-stack.ts        # Main stack orchestrator
│   ├── constructs/
│   │   ├── compute/              # EC2 & ECS deployments
│   │   ├── database/             # Database constructs
│   │   ├── monitoring/           # Monitoring & alerts
│   │   ├── network/              # VPC & networking
│   │   ├── security/             # Security & compliance
│   │   └── storage/              # S3 & EFS storage
│   └── utils/
│       ├── iam-policies.ts       # IAM policy helpers
│       ├── tagging-strategy.ts   # Resource tagging
│       └── connection-strings.ts  # DB connection utilities
├── config/
│   ├── deployment-config.ts      # Configuration builder
│   └── resource-sizes.ts         # Resource sizing
├── scripts/
│   └── estimate-cost.ts          # Cost estimation tool
└── test/
    └── librechat-stack.test.ts   # Unit tests
```

## Components

### Core Constructs

#### 🌐 **VpcConstruct**
- **Purpose**: Network infrastructure management
- **Location**: `lib/constructs/network/network-construct.ts`
- **Features**:
  - Custom VPC with configurable CIDR
  - Public/private subnet configuration
  - NAT gateway management (optional)
  - VPC endpoints for AWS services

#### 💾 **DatabaseConstruct** 
- **Purpose**: Database infrastructure (RDS/DocumentDB)
- **Location**: `lib/constructs/database/database-construct.ts`
- **Lines**: 558
- **Features**:
  - RDS PostgreSQL with pgvector extension
  - DocumentDB cluster (MongoDB compatible)
  - Automated backups and snapshots
  - High availability options

#### 🖥️ **EC2Deployment**
- **Purpose**: Single instance deployment with Docker
- **Location**: `lib/constructs/compute/ec2-deployment.ts`
- **Lines**: 963
- **Features**:
  - Auto-configured EC2 instance
  - Docker Compose orchestration
  - Application Load Balancer
  - Auto-recovery and monitoring

#### 🐳 **ECSDeployment**
- **Purpose**: Container orchestration with Fargate
- **Location**: `lib/constructs/compute/ecs-deployment.ts` 
- **Lines**: 774
- **Features**:
  - Auto-scaling Fargate services
  - Service discovery
  - Container health checks
  - Blue/green deployments

#### 📦 **StorageConstruct**
- **Purpose**: Object storage and file systems
- **Location**: `lib/constructs/storage/storage-construct.ts`
- **Features**:
  - S3 buckets with encryption
  - EFS for shared storage (ECS)
  - Lifecycle policies
  - CORS configuration

#### 📊 **MonitoringConstruct**
- **Purpose**: Observability and alerting
- **Location**: `lib/constructs/monitoring/monitoring-construct.ts`
- **Features**:
  - CloudWatch dashboards
  - Custom metrics and alarms
  - SNS notifications
  - Log aggregation

### Utility Modules

#### 🔐 **IAM Policies**
- **Location**: `lib/utils/iam-policies.ts`
- **Exports**:
  - `createBedrockPolicyStatements()` - Bedrock AI access
  - `createS3PolicyStatements()` - S3 bucket access
  - `createSecretsManagerPolicyStatements()` - Secrets access
  - `createIpRestrictionCondition()` - IP-based restrictions

#### 🏷️ **Tagging Strategy**
- **Location**: `lib/utils/tagging-strategy.ts`
- **Purpose**: Consistent resource tagging for cost allocation and compliance

## Configuration

### Deployment Configuration Builder

```typescript
// config/deployment-config.ts
const config = new DeploymentConfigBuilder('production')
  .withDeploymentMode('ECS')
  .withKeyPair('prod-key')         // EC2 only
  .withDomain('chat.example.com')
  .withCertificate('arn:...')
  .withFeatures({
    rag: true,
    meilisearch: true,
    sharepoint: false
  })
  .build();
```

### Preset Configurations

| Preset | Mode | Resources | Cost/Month | Use Case |
|--------|------|-----------|------------|----------|
| `minimal-dev` | EC2 | t3.medium, 20GB RDS | ~$150 | Development |
| `standard-dev` | EC2 | t3.large, 50GB RDS | ~$250 | Team development |
| `production-ec2` | EC2 | t3.xlarge, 100GB RDS | ~$400 | Small production |
| `production-ecs` | ECS | 2 vCPU, 4GB RAM | ~$600 | Scalable production |
| `enterprise` | ECS | 4 vCPU, 8GB RAM, HA | ~$1200 | Enterprise |

## Deployment Modes

### EC2 Mode
- **Best for**: Development, small teams, cost optimization
- **Architecture**: Single EC2 instance with Docker Compose
- **Features**:
  - SSH access for debugging
  - Simple deployment model
  - Lower cost (~$250/month)
  - Quick startup time

### ECS Mode
- **Best for**: Production, high availability, auto-scaling
- **Architecture**: Fargate containers with ALB
- **Features**:
  - No server management
  - Auto-scaling capabilities
  - Blue/green deployments
  - Higher availability

## API Reference

### Main Stack Props

```typescript
interface LibreChatStackProps {
  deploymentMode: 'EC2' | 'ECS';
  environment: 'development' | 'staging' | 'production';
  keyPairName?: string;           // Required for EC2
  allowedIps?: string[];          // SSH access IPs
  domainName?: string;
  certificateArn?: string;
  alertEmail?: string;
  enableRag?: boolean;
  enableMeilisearch?: boolean;
  vpcConfig?: VpcConfig;
  databaseConfig?: DatabaseConfig;
  computeConfig?: ComputeConfig;
}
```

### Key Interfaces

```typescript
// Network Configuration
interface VpcConfig {
  useExisting?: boolean;
  vpcId?: string;
  cidr?: string;
  maxAzs?: number;
  natGateways?: number;
}

// Database Configuration  
interface DatabaseConfig {
  engine: 'postgres' | 'documentdb' | 'aurora';
  instanceClass: string;
  allocatedStorage?: number;
  backupRetentionDays: number;
  multiAz?: boolean;
}

// Compute Configuration
interface ComputeConfig {
  instanceType?: string;    // EC2
  desiredCount?: number;    // ECS
  cpu?: number;            // ECS
  memory?: number;         // ECS
  maxCapacity?: number;    // Auto-scaling
}
```

## Scripts & Commands

### NPM Scripts

| Command | Description |
|---------|-------------|
| `npm run build` | Compile TypeScript |
| `npm run test` | Run unit tests |
| `npm run deploy` | Interactive deployment |
| `npm run deploy:dev` | Deploy development |
| `npm run deploy:prod` | Deploy production |
| `npm run synth` | Synthesize CloudFormation |
| `npm run estimate-cost` | Estimate AWS costs |
| `npm run destroy` | Tear down stack |

### CDK Commands

```bash
# Bootstrap CDK (first time)
cdk bootstrap aws://ACCOUNT/REGION

# List stacks
cdk list

# Show changes
cdk diff

# Deploy with context
cdk deploy -c configSource=production-ecs

# Destroy stack
cdk destroy LibreChatStack-production
```

## Testing

### Test Structure

```bash
test/
└── librechat-stack.test.ts
    ├── Development EC2 Deployment
    ├── Production ECS Deployment  
    ├── Feature Flags
    ├── Stack Outputs
    ├── Cost Optimization
    └── Security
```

### Running Tests

```bash
# Run all tests
npm test

# Run with coverage
npm run test:coverage

# Watch mode
npm run test:watch

# Specific test
npx jest --testNamePattern="EC2"
```

## Cost Analysis

### Cost Estimation Tool

```bash
# Estimate costs for configuration
npm run estimate-cost production-ec2

# Output includes:
# - Compute costs (EC2/ECS)
# - Storage costs (S3/EBS/EFS)
# - Database costs (RDS/DocumentDB)
# - Network costs (ALB/NAT)
# - Total monthly estimate
```

### Typical Costs by Environment

| Environment | EC2 Mode | ECS Mode |
|-------------|----------|----------|
| Development | $150/mo | $300/mo |
| Staging | $250/mo | $450/mo |
| Production | $400/mo | $600/mo |
| Enterprise | N/A | $1200/mo |

## Environment Variables

### Required Variables

```bash
# Deployment mode (required)
DEPLOYMENT_MODE=EC2|ECS

# EC2 mode only
KEY_PAIR_NAME=my-ssh-key

# Optional
DEPLOYMENT_ENV=development|staging|production
ALERT_EMAIL=ops@company.com
DOMAIN_NAME=chat.company.com
CERTIFICATE_ARN=arn:aws:acm:...
```

### AWS Credentials

```bash
# Standard AWS environment variables
AWS_REGION=us-east-1
AWS_PROFILE=default
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
```

## Security Features

- 🔐 **Encryption**: All data encrypted at rest and in transit
- 🛡️ **IAM**: Least privilege access with role-based permissions
- 🔒 **Secrets**: AWS Secrets Manager for sensitive data
- 🌐 **Network**: VPC isolation with security groups
- 📝 **Audit**: CloudTrail logging and AWS Config rules
- 🏥 **Compliance**: Optional HIPAA compliance mode

## Monitoring & Alerts

### CloudWatch Dashboards
- Application metrics
- Infrastructure health
- API performance
- Database connections
- Container metrics (ECS)

### Alarms
- High CPU/memory usage
- Database connection failures
- Application errors
- SSL certificate expiry
- Disk space warnings

## Troubleshooting

### Common Issues

1. **EC2 Instance Not Created**
   - Ensure key pair exists: `aws ec2 describe-key-pairs`
   - Check CloudFormation events
   - Verify deployment mode is set

2. **ECS Tasks Failing**
   - Check CloudWatch logs
   - Verify task IAM role permissions
   - Check container health checks

3. **Database Connection Issues**
   - Verify security groups
   - Check VPC/subnet configuration
   - Validate credentials in Secrets Manager

## Related Documentation

- [README.md](README.md) - Getting started guide
- [CLAUDE.md](CLAUDE.md) - AI assistant instructions
- [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) - Detailed structure
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Command reference

## Support

For issues and questions:
- GitHub Issues: [Report bugs or request features]
- AWS Support: For infrastructure issues
- LibreChat Community: Application-specific questions

---

*Generated: 2024 | LibreChat CDK v2.0.0*