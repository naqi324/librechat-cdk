# LibreChat CDK Project Structure

## 📁 Directory Overview

```
librechat-cdk/
├── README.md                          # Main documentation (setup, deployment, operations)
├── PROJECT_STRUCTURE.md              # This file - explains project organization
├── package.json                       # Node.js dependencies and npm scripts
├── package-lock.json                 # (Generated) Locked dependency versions
├── tsconfig.json                      # TypeScript compiler configuration
├── cdk.json                          # CDK app configuration and feature flags
├── jest.config.js                    # Jest testing framework configuration
├── .gitignore                        # Git ignore patterns
│
├── bin/
│   └── librechat.ts                  # CDK app entry point - instantiates stack
│
├── lib/
│   └── librechat-stack.ts            # Main stack definition - all AWS resources
│
├── test/
│   └── librechat-stack.test.ts       # Unit tests for CDK stack
│
├── scripts/                          # Utility scripts for deployment
│   ├── deploy.sh                     # Interactive deployment wizard
│   ├── create-one-click-deploy.sh    # Generate shareable console URL
│   └── cleanup.sh                    # Remove all AWS resources
│
└── cdk.out/                          # (Generated) CDK synthesis output
    └── LibreChatStack.template.json  # Generated CloudFormation template
```

## 📄 Core Files Explained

### Infrastructure Definition

#### `lib/librechat-stack.ts` (~800 lines)
The heart of the project - defines all AWS resources:
- **Networking**: VPC with 2 public and 2 private subnets
- **Compute**: EC2 instance (t3.xlarge) with automated setup
- **Database**: RDS PostgreSQL 15.7 with pgvector extension
- **Storage**: S3 bucket with encryption and versioning
- **Load Balancing**: Application Load Balancer
- **IAM**: Role with Bedrock and S3 permissions
- **Monitoring**: CloudWatch alarms for CPU and DB connections
- **Secrets**: Secrets Manager for database password

Key sections:
```typescript
// VPC Creation (lines ~50-70)
const vpc = new ec2.Vpc(this, 'LibreChatVPC', {...})

// Database with pgvector (lines ~140-170)
const database = new rds.DatabaseInstance(this, 'Database', {...})

// EC2 with user data script (lines ~350-450)
const instance = new ec2.Instance(this, 'LibreChatInstance', {...})
```

#### `bin/librechat.ts` (~40 lines)
CDK application entry point that:
- Imports the LibreChatStack
- Reads context values for customization
- Creates the stack with proper environment
- Applies tags for cost tracking

### Configuration Files

#### `package.json`
```json
{
  "name": "librechat-cdk",
  "version": "1.0.0",
  "scripts": {
    "build": "tsc",
    "watch": "tsc -w",
    "test": "jest",
    "cdk": "cdk",
    "deploy": "npm run build && cdk deploy",
    "destroy": "cdk destroy",
    "synth": "npm run build && cdk synth",
    "export-template": "npm run build && cdk synth > cloudformation-template.yaml"
  },
  "dependencies": {
    "aws-cdk-lib": "2.150.0",
    "constructs": "^10.0.0",
    "source-map-support": "^0.5.21"
  },
  "devDependencies": {
    "@types/jest": "^29.5.5",
    "@types/node": "20.8.10",
    "jest": "^29.7.0",
    "ts-jest": "^29.1.1",
    "aws-cdk": "2.150.0",
    "ts-node": "^10.9.1",
    "typescript": "~5.2.2"
  }
}
```

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
```
*.js
!jest.config.js
*.d.ts
node_modules/
.npm/
.env
cdk.out/
.cdk.staging/
*.pem
cloudformation-template.yaml
```

### Deployment Scripts

#### `scripts/deploy.sh`
Interactive bash script that:
1. Checks for Node.js, AWS CLI, and CDK
2. Installs dependencies
3. Builds the TypeScript project
4. Offers three deployment methods:
   - Generate CloudFormation template
   - Deploy via CDK
   - Deploy via CloudFormation CLI

Key functions:
- `check_prerequisites()` - Validates environment
- `install_dependencies()` - Runs npm install
- `generate_template()` - Creates CF template
- `deploy_cdk()` - Interactive CDK deployment

#### `scripts/create-one-click-deploy.sh`
Creates a shareable deployment URL:
```bash
#!/bin/bash
REGION=${1:-us-east-1}
# Creates S3 bucket
# Uploads template
# Generates console URL
```

#### `scripts/cleanup.sh`
Safe resource cleanup:
```bash
#!/bin/bash
# Confirms deletion
# Removes CloudFormation stack
# Waits for completion
```

### Test Files

#### `test/librechat-stack.test.ts`
Jest tests that validate:
- VPC has correct CIDR and subnets
- Security groups have proper rules
- RDS has pgvector parameter group
- S3 bucket has encryption enabled
- EC2 instance has correct configuration
- IAM role has required permissions
- ALB and target group settings
- CloudWatch alarms are created
- Stack outputs are present

## 🛠️ Generated Files

### During Build
```
bin/*.js                              # Compiled JavaScript
lib/*.js                              # Compiled JavaScript
test/*.js                             # Compiled tests
*.d.ts                                # TypeScript declarations
```

### During CDK Synth
```
cdk.out/
├── LibreChatStack.template.json      # CloudFormation template (~2000 lines)
├── LibreChatStack.assets.json        # Asset metadata
├── manifest.json                     # CDK manifest
└── tree.json                         # Construct tree
```

### User-Generated
```
librechat-cloudformation.yaml         # From: cdk synth > filename.yaml
librechat-parameters.json             # Created by deploy.sh
```

## 🔧 Common Operations

### Initial Setup
```bash
# Clone and install
git clone <repository>
cd librechat-cdk
npm install

# First-time CDK setup
cdk bootstrap aws://ACCOUNT/REGION
```

### Development
```bash
# Compile TypeScript
npm run build

# Run tests
npm test

# Watch mode for development
npm run watch

# Check what will change
cdk diff
```

### Deployment
```bash
# Interactive deployment
./scripts/deploy.sh

# Direct CDK deployment
cdk deploy --parameters KeyName=my-key

# Generate CloudFormation
cdk synth > template.yaml
```

### Debugging
```bash
# Validate synthesis
cdk synth --quiet

# See construct tree
cdk synth --no-staging | jq .tree

# Check CloudFormation
cfn-lint librechat-cloudformation.yaml
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

1. **Single Stack Approach**
   - All resources in one stack for simplicity
   - Easy to deploy and tear down
   - Clear resource relationships

2. **EC2 vs Containers**
   - EC2 chosen for simplicity and SSH access
   - Docker Compose on EC2 for easy updates
   - Could be adapted for ECS/Fargate

3. **User Data vs Custom Resource**
   - User data script for one-time setup
   - Simpler than Lambda custom resources
   - Logs available in EC2 console

4. **Parameter vs Context**
   - Parameters for user-specific values (keys, IPs)
   - Context for deployment options (instance types)

### Extension Points

1. **Adding HTTPS**
   - Add ACM certificate parameter
   - Modify ALB listener for HTTPS
   - Update security groups

2. **Multi-AZ Database**
   - Change `multiAz: true` in RDS config
   - Increases cost but improves availability

3. **Auto Scaling**
   - Replace single instance with ASG
   - Add scaling policies
   - Update ALB target group

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

---

For deployment instructions, see [README.md](README.md)
