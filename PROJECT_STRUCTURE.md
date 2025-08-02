# LibreChat CDK Project Structure

## 📁 Directory Overview

```md
librechat-cdk/
├── README.md                         # Main documentation - concise overview
├── QUICK_REFERENCE.md               # Commands and tips cheatsheet
├── PROJECT_STRUCTURE.md              # This file - repository organization
├── CLAUDE.md                         # Instructions for Claude Code AI assistant
├── package.json                      # Node.js dependencies and npm scripts
├── package-lock.json                 # (Generated) Locked dependency versions
├── tsconfig.json                      # TypeScript compiler configuration
├── cdk.json                          # CDK app configuration and feature flags
├── jest.config.js                    # Jest testing framework configuration
├── docker-compose.yaml               # Docker compose configuration for local dev
├── .gitignore                        # Git ignore patterns
├── .env.example                      # Environment variables template
│
├── bin/
│   └── librechat.ts                  # CDK app entry point - instantiates stack
│
├── lib/
│   ├── librechat-stack.ts            # Main stack definition - orchestrates constructs
│   └── constructs/                   # Modular CDK constructs
│       ├── compute/
│       │   ├── ec2-deployment.ts     # EC2-based deployment construct
│       │   └── ecs-deployment.ts     # ECS Fargate deployment construct
│       ├── database/
│       │   └── database-construct.ts # RDS PostgreSQL and DocumentDB constructs
│       ├── monitoring/
│       │   └── monitoring-construct.ts # CloudWatch alarms and dashboards
│       ├── network/
│       │   └── network-construct.ts  # VPC, subnets, and security groups
│       └── storage/
│           └── storage-construct.ts  # S3 buckets and EFS configuration
│
├── config/
│   ├── deployment-config.ts          # Deployment configuration builder
│   ├── librechat.yaml               # LibreChat application configuration
│   ├── development.env.example      # Development environment example
│   └── ecs-deployment.env.example   # ECS deployment example
│
├── lambda/                           # Lambda functions for initialization
│   ├── init-postgres/
│   │   ├── init_postgres.py          # PostgreSQL initialization with pgvector
│   │   └── requirements.txt          # Python dependencies
│   └── init-docdb/
│       ├── init_docdb.py             # DocumentDB initialization
│       └── requirements.txt          # Python dependencies
│
├── docs/                             # All detailed documentation
│   ├── README.md                     # Documentation index and navigation
│   ├── AWS_AUTHENTICATION.md         # AWS credentials and permissions setup
│   ├── LOCAL_TESTING_GUIDE.md        # Local development and testing
│   ├── ISENGARD_TOKEN_WORKAROUNDS.md # Enterprise AWS token solutions
│   ├── CLEANUP.md                    # Resource cleanup guide
│   ├── DEPLOYMENT_OPTIMIZATION.md    # Cost and performance optimization
│   ├── DOCUMENTDB_SETUP.md          # DocumentDB configuration guide
│   ├── NETWORK_ARCHITECTURE.md      # VPC and networking details
│   ├── SECURITY.md                   # Security best practices and features
│   └── TROUBLESHOOTING.md           # Common issues and solutions
│
├── test/
│   └── librechat-stack.test.ts       # Unit tests for CDK stack
│
├── scripts/                          # Utility scripts for deployment
│   ├── README-cleanup.md             # Cleanup scripts documentation
│   ├── analyze-deployment.sh         # Analyze deployment state
│   ├── check-resources.sh            # Check for remaining resources
│   ├── cleanup.sh                    # Consolidated cleanup script (v2.0.0)
│   ├── create-one-click-deploy.sh    # Generate CloudFormation template
│   ├── create-support-bundle.sh      # Generate diagnostic information
│   ├── deploy-interactive.sh         # Interactive deployment wizard
│   ├── deploy.sh                     # CI/CD deployment script
│   ├── estimate-cost.ts              # TypeScript cost estimation tool
│   └── setup-environment.sh          # Initial environment setup wizard
│
└── cdk.out/                          # (Generated) CDK synthesis output
    └── LibreChatStack.template.json  # Generated CloudFormation template
```

## 📄 Core Files Explained

### Infrastructure Definition

#### `lib/librechat-stack.ts`

The main stack orchestrator that:

- Determines deployment mode (EC2 vs ECS)
- Instantiates appropriate constructs
- Manages cross-construct dependencies
- Defines stack outputs

Key features:
- Supports multiple deployment configurations
- Handles environment-specific settings
- Integrates all constructs seamlessly

#### `lib/constructs/` - Modular Architecture

##### `network/network-construct.ts`
- Creates VPC with configurable AZs and subnets
- Sets up security groups and NACLs
- Configures VPC endpoints for AWS services
- Supports both public and private subnet configurations

##### `compute/ec2-deployment.ts`
- EC2 instance with automated LibreChat setup
- User data script for Docker installation
- Auto-recovery and monitoring
- SSH access configuration

##### `compute/ecs-deployment.ts`
- ECS Fargate cluster configuration
- Task definitions for LibreChat containers
- Auto-scaling policies
- Service discovery setup

##### `database/database-construct.ts`
- RDS PostgreSQL with pgvector extension
- Optional DocumentDB for MongoDB compatibility
- Automated backups and snapshots
- Multi-AZ support for production

##### `storage/storage-construct.ts`
- S3 buckets with encryption and versioning
- EFS for shared container storage (ECS mode)
- Lifecycle policies for cost optimization
- CORS configuration for web access

##### `monitoring/monitoring-construct.ts`
- CloudWatch dashboards
- Custom metrics and alarms
- SNS notifications
- Log aggregation

##### `security/audit-construct.ts`
- CloudTrail audit logging
- S3 bucket for audit logs
- KMS encryption for logs
- Data event tracking for S3 and Lambda
- Compliance-ready configuration

#### `lib/utils/` - Utility Functions

##### `connection-strings.ts`
- PostgreSQL connection string builder
- DocumentDB connection string builder
- Handles SSL/TLS parameters
- Environment-specific configurations

##### `iam-policies.ts`
- Least-privilege policy generators
- Bedrock access policies
- S3 bucket policies
- Secrets Manager policies
- Consistent security patterns

##### `tagging-strategy.ts`
- Comprehensive tagging framework
- Standard tags (Environment, Project, etc.)
- Compliance tags (HIPAA, SOC2)
- Cost allocation tags
- Automated tag application

#### `config/deployment-config.ts`

Defines deployment configurations:
- `minimal-dev`: Basic development setup
- `standard-dev`: Development with full features
- `production-ec2`: Production on EC2
- `production-ecs`: Production on ECS
- `enterprise`: Full enterprise features

#### `bin/librechat.ts`

CDK application entry point that:
- Loads deployment configuration
- Creates appropriate stack instance
- Applies environment-specific settings
- Manages stack dependencies

### Configuration Files

#### `package.json`

Key scripts for different deployment scenarios:

```json
{
  "name": "librechat-cdk",
  "version": "2.0.0",
  "scripts": {
    // Core CDK commands
    "build": "tsc",
    "synth": "npm run build && cdk synth",
    "deploy": "npm run build && cdk deploy",
    "destroy": "cdk destroy",
    
    // Environment-specific deployments
    "deploy:dev": "npm run build && cdk deploy -c configSource=standard-dev",
    "deploy:prod": "npm run build && DEPLOYMENT_ENV=production cdk deploy -c configSource=production-ecs",
    
    // Utility commands
    "wizard": "bash scripts/deploy-interactive.sh",
    "estimate-cost": "ts-node scripts/estimate-cost.ts",
    "validate": "npm run lint && npm run test && npm run build",
    
    // Testing and quality
    "test": "jest",
    "test:coverage": "jest --coverage",
    "lint": "eslint . --ext .ts",
    "format": "prettier --write '**/*.{ts,js,json,md}'"
  }
}
```

Enhanced with:
- Environment-specific deployment commands
- Interactive deployment wizard
- Cost estimation tools
- Code quality tools (ESLint, Prettier)
- Comprehensive testing setup

#### `cdk.json`

CDK configuration with:

- App entry point configuration
- Watch patterns for development
- Feature flags for CDK best practices
- Context defaults

#### `tsconfig.json`

TypeScript configuration:

- Target: ES2020
- Module: CommonJS
- Strict mode enabled
- Source maps for debugging

#### `.gitignore`

Key patterns for keeping the repository clean:

```
# TypeScript compilation outputs
*.js
*.d.ts
*.js.map
*.d.ts.map
!jest.config.js
!.eslintrc.js

# Node.js
node_modules/

# CDK outputs
cdk.out/
cdk.context.json

# Environment files
.env
.env.*
!.env.example
!.env.librechat.example

# Claude Code
claude-instance*/
claude-code-storage/
settings.local.json

# AWS credentials
*.pem
*.ppk
```

### Deployment Scripts

#### `scripts/deploy-interactive.sh`

Advanced interactive deployment wizard that:
- Detects existing deployments
- Offers deployment mode selection (EC2/ECS)
- Configures environment-specific settings
- Validates prerequisites
- Provides cost estimates
- Executes deployment with progress tracking

#### `scripts/deploy.sh`

Basic deployment script for CI/CD pipelines:
- Minimal interaction required
- Parameter-based configuration
- Suitable for automation

#### `scripts/setup-environment.sh`

Initial environment setup wizard:
- Checks AWS CLI configuration
- Validates Bedrock access
- Creates EC2 key pairs if needed
- Sets up .env.librechat file
- Bootstraps CDK environment

#### `scripts/create-one-click-deploy.sh`

Creates shareable deployment URLs:
- Uploads template to S3
- Generates pre-signed URLs
- Creates CloudFormation quick-create links
- Supports parameter pre-population

#### `scripts/cleanup.sh`

Safe and thorough cleanup:
- Lists all resources to be deleted
- Confirms deletion with user
- Removes stacks in dependency order
- Cleans up S3 buckets
- Deletes CloudWatch log groups

#### `scripts/estimate-cost.ts`

TypeScript cost estimation tool:
- Analyzes deployment configuration
- Provides monthly cost breakdown
- Compares different deployment modes
- Suggests optimization strategies

### Lambda Functions

#### `lambda/init-postgres/init_postgres.py`

PostgreSQL initialization function:
- Installs pgvector extension
- Creates required schemas
- Sets up initial tables
- Configures vector search indexes
- Handles connection pooling

#### `lambda/init-docdb/init_docdb.py`

DocumentDB initialization function:
- Creates collections
- Sets up indexes
- Configures sharding (if applicable)
- Initializes replication

### Test Files

#### `test/librechat-stack.test.ts`

Comprehensive Jest tests that validate:

- VPC configuration for all deployment modes
- Security group rules and network ACLs
- Database configurations (RDS/DocumentDB)
- Compute resources (EC2/ECS)
- Storage configurations (S3/EFS)
- IAM policies and roles
- Load balancer configurations
- Monitoring and alarms
- Stack outputs and exports
- Cost tags and metadata

## 🛠️ Generated Files

### During Build

```md
bin/*.js                              # Compiled JavaScript
lib/*.js                              # Compiled JavaScript
test/*.js                             # Compiled tests
*.d.ts                                # TypeScript declarations
```

### During CDK Synth

```md
cdk.out/
├── LibreChatStack.template.json      # CloudFormation template (~2000 lines)
├── LibreChatStack.assets.json        # Asset metadata
├── manifest.json                     # CDK manifest
└── tree.json                         # Construct tree
```

### User-Generated

```md
librechat-cloudformation.yaml         # From: cdk synth > filename.yaml
librechat-parameters.json             # Created by deploy.sh
```

## 📚 Documentation

### `docs/SECURITY.md`

Comprehensive security guide covering:
- AWS security best practices
- Network isolation strategies
- Encryption implementation
- Access control patterns
- Compliance considerations
- Incident response procedures

### `docs/TROUBLESHOOTING.md`

Troubleshooting guide with:
- Common deployment issues
- Performance optimization tips
- Debugging techniques
- Log analysis guides
- Recovery procedures
- FAQ section

## 🔧 Common Operations

### Initial Setup

```bash
# Run the setup wizard
./scripts/setup-environment.sh

# Or manual setup
npm install
aws configure
cdk bootstrap
```

### Development

```bash
# Local development with Docker
docker-compose up -d

# Run tests with coverage
npm run test:coverage

# Lint and format code
npm run lint:fix
npm run format

# Validate everything
npm run validate
```

### Deployment

```bash
# Interactive wizard (recommended)
npm run wizard

# Environment-specific deployments
npm run deploy:dev
npm run deploy:staging
npm run deploy:prod

# Custom configuration
cdk deploy -c configSource=my-config

# Cost estimation
npm run estimate-cost production
```

### Monitoring & Debugging

```bash
# View stack status
aws cloudformation describe-stacks --stack-name LibreChatStack

# Stream logs
aws logs tail /aws/librechat --follow

# Check ECS services (if using ECS)
aws ecs list-services --cluster LibreChat-Cluster

# Generate support bundle
./scripts/create-support-bundle.sh
```

## 📊 Key File Sections

### User Data Script (in librechat-stack.ts)

The EC2 user data script (lines ~250-350) automatically:

1. Installs Docker and dependencies
2. Clones LibreChat repository
3. Configures environment variables
4. Initializes PostgreSQL with pgvector
5. Starts Docker containers
6. Configures Nginx

### IAM Permissions (in librechat-stack.ts)

The EC2 role includes:

```typescript
// Bedrock access (lines ~180-190)
actions: [
  'bedrock:InvokeModel',
  'bedrock:InvokeModelWithResponseStream',
  'bedrock:ListFoundationModels'
]

// S3 access (lines ~192-202)
actions: [
  's3:GetObject',
  's3:PutObject',
  's3:DeleteObject',
  's3:ListBucket'
]
```

### Stack Parameters (in librechat-stack.ts)

Three CloudFormation parameters:

1. `AlertEmail` - For CloudWatch notifications
2. `KeyName` - EC2 SSH key pair
3. `AllowedSSHIP` - IP CIDR for SSH access

## 🏗️ Architecture Notes

### Design Decisions

1. **Modular Construct Approach**
   - Separation of concerns with dedicated constructs
   - Reusable components across different stacks
   - Easier testing and maintenance
   - Support for multiple deployment patterns

2. **Dual Deployment Modes**
   - **EC2 Mode**: Simple, cost-effective, SSH access
   - **ECS Mode**: Scalable, managed, production-grade
   - Shared constructs for networking, database, storage
   - Mode selected via configuration

3. **Configuration-Driven Deployment**
   - Pre-defined configurations for common scenarios
   - Environment variables for runtime settings
   - CDK context for deployment customization
   - Support for GitOps workflows

4. **Lambda for Initialization**
   - Custom resources for database setup
   - Idempotent operations
   - CloudFormation integration
   - Automatic retry on failure

### Extension Points

1. **Custom Deployment Modes**
   - Add new compute constructs (e.g., EKS)
   - Implement in `lib/constructs/compute/`
   - Update deployment configurations
   - Maintain interface compatibility

2. **Additional AWS Services**
   - Cognito for authentication
   - ElastiCache for session management
   - API Gateway for REST APIs
   - EventBridge for event-driven features

3. **Multi-Region Deployment**
   - Cross-region replication for RDS
   - CloudFront for global distribution
   - Route 53 for geo-routing
   - S3 cross-region replication

4. **Enterprise Features**
   - AWS SSO integration
   - AWS Control Tower compliance
   - AWS Organizations support
   - Service Catalog products

## 🎯 Best Practices

1. **Security**
   - Never commit `.env` files
   - Use Secrets Manager for passwords
   - Restrict SSH access by IP
   - Enable CloudTrail logging

2. **Cost Optimization**
   - Use smaller instances for dev/test
   - Set up billing alerts
   - Review CloudWatch logs retention
   - Consider Reserved Instances

3. **Operations**
   - Tag all resources consistently
   - Use CloudFormation outputs
   - Monitor CloudWatch alarms
   - Regular backup testing

### Additional Configuration Files

#### `docker-compose.yaml`

Local development environment with:
- LibreChat application container
- PostgreSQL with pgvector
- Redis for caching
- Meilisearch for full-text search
- Volume mappings for hot-reload
- Environment variable configuration

## 🚀 Quick Reference

### File Locations

| What | Where |
|------|-------|
| Main stack | `lib/librechat-stack.ts` |
| Network setup | `lib/constructs/network/network-construct.ts` |
| EC2 deployment | `lib/constructs/compute/ec2-deployment.ts` |
| ECS deployment | `lib/constructs/compute/ecs-deployment.ts` |
| Database setup | `lib/constructs/database/database-construct.ts` |
| Deployment configs | `config/deployment-config.ts` |
| Interactive deploy | `scripts/deploy-interactive.sh` |
| Cost estimation | `scripts/estimate-cost.ts` |

### Common Tasks

| Task | Command |
|------|---------|
| Deploy development | `npm run deploy:dev` |
| Deploy production | `npm run deploy:prod` |
| Interactive wizard | `npm run wizard` |
| Estimate costs | `npm run estimate-cost` |
| Run tests | `npm test` |
| Clean build | `npm run clean` |
| Update dependencies | `npm run update-deps` |

---

For deployment instructions, see [README.md](README.md)

For security information, see [docs/SECURITY.md](docs/SECURITY.md)

For troubleshooting, see [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
