# LibreChat CDK Repository Analysis Report

## Executive Summary

This repository implements an AWS CDK deployment for LibreChat with Bedrock integration, RAG pipeline, and both EC2/ECS deployment options. The analysis reveals that the core infrastructure is well-implemented but requires specific configuration updates for Claude Sonnet 4 as default and some missing environment variables.

## Repository Structure

```
librechat-cdk/
├── bin/
│   └── librechat.ts                    # CDK app entry point, configuration loader
├── config/
│   ├── deployment-config.ts            # Configuration system and presets
│   ├── librechat.yaml                  # LibreChat application configuration
│   └── resource-sizes.ts               # Resource sizing configurations
├── lib/
│   ├── librechat-stack.ts             # Main stack orchestrator
│   ├── constructs/
│   │   ├── compute/
│   │   │   ├── ec2-deployment.ts      # EC2 single-instance deployment
│   │   │   └── ecs-deployment.ts      # ECS Fargate deployment
│   │   ├── database/
│   │   │   └── database-construct.ts   # RDS PostgreSQL + pgvector, DocumentDB
│   │   ├── network/
│   │   │   └── network-construct.ts    # VPC and networking
│   │   ├── storage/
│   │   │   └── storage-construct.ts    # S3 and EFS storage
│   │   └── monitoring/
│   │       └── monitoring-construct.ts # CloudWatch monitoring
│   └── utils/
│       ├── iam-policies.ts            # IAM policy utilities
│       └── connection-strings.ts       # Database connection utilities
├── scripts/
│   ├── deploy-interactive.sh          # Interactive deployment wizard
│   └── estimate-cost.ts               # Cost estimation tool
└── test/
    └── librechat-stack.test.ts        # CDK stack tests
```

### Key File Purposes
- **bin/librechat.ts**: Loads configuration, handles context parameters, instantiates stack
- **config/deployment-config.ts**: Defines environments (dev, staging, prod, enterprise)
- **config/librechat.yaml**: LibreChat application settings (models, RAG, tools)
- **lib/librechat-stack.ts**: Main stack that orchestrates all constructs
- **lib/constructs/compute/ec2-deployment.ts**: Creates EC2 instance with Docker Compose
- **lib/constructs/compute/ecs-deployment.ts**: Creates ECS Fargate services
- **lib/utils/iam-policies.ts**: Creates least-privilege IAM policies for Bedrock

### Missing Expected Files
- No Dockerfile (uses official ghcr.io/danny-avila/librechat images)
- No docker-compose.yml at root (generated dynamically in user data)
- No .env file (must be created for deployment)

## Configuration Analysis

### Current Configurations

#### Environment Variables (EC2 Deployment - lib/constructs/compute/ec2-deployment.ts)
```typescript
// Lines 295-378
- HOST=0.0.0.0
- PORT=3080
- DOMAIN_SERVER/CLIENT (dynamic)
- DATABASE_URL (PostgreSQL with pgvector)
- MONGO_URI (DocumentDB or local MongoDB)
- AWS_REGION
- BEDROCK_AWS_REGION
- ENDPOINTS=bedrock
- S3_PROVIDER/BUCKET/REGION
- JWT_SECRET/CREDS_KEY/CREDS_IV (from Secrets Manager)
- RAG_ENABLED/RAG_API_URL
- EMBEDDINGS_PROVIDER=bedrock
- EMBEDDINGS_MODEL=amazon.titan-embed-text-v2:0
- SEARCH_ENABLED (Meilisearch)
- SEARCH=true (Web search)
```

#### Docker Settings (EC2 - Lines 381-483)
- LibreChat API: ghcr.io/danny-avila/librechat:latest
- RAG API: ghcr.io/danny-avila/librechat-rag-api-dev:latest
- MongoDB: mongo:latest
- Meilisearch: getmeili/meilisearch:v1.6

#### CDK Context Values
- configSource: minimal-dev, standard-dev, production-ec2, production-ecs, enterprise
- deploymentMode: EC2 or ECS (required)
- keyPairName: SSH key for EC2
- enableRag: true/false
- enableMeilisearch: true/false

#### IAM Permissions (lib/utils/iam-policies.ts)
```typescript
// Lines 33-47
- bedrock:InvokeModel
- bedrock:InvokeModelWithResponseStream
- bedrock:ListFoundationModels
- bedrock:GetFoundationModel
// Model families: anthropic.claude-*, amazon.titan-*, meta.llama*, mistral.*
```

### Required Configurations (from documentation)

#### Bedrock Requirements
- ✅ BEDROCK_AWS_DEFAULT_REGION (implemented as BEDROCK_AWS_REGION)
- ⚠️ BEDROCK_AWS_MODELS (optional, not implemented)
- ✅ IAM Role with Bedrock permissions (implemented)
- ✅ Model access in AWS console (user responsibility)

#### RAG API Requirements
- ✅ RAG_API_URL (implemented)
- ⚠️ RAG_OPENAI_API_KEY (not needed, using Bedrock embeddings)
- ✅ EMBEDDINGS_PROVIDER=bedrock (implemented)
- ✅ EMBEDDINGS_MODEL=amazon.titan-embed-text-v2:0 (implemented)
- ✅ PostgreSQL with pgvector (implemented)
- ✅ COLLECTION_NAME (implemented)
- ✅ CHUNK_SIZE/CHUNK_OVERLAP (implemented)

#### Network Requirements
- ✅ VPC with public/private subnets
- ✅ Security groups for services
- ✅ ALB for public access
- ✅ NAT Gateway for private subnet internet access

## Code Issues Identified

### Critical Errors

1. **[bin/librechat.ts:280]** - Deployment mode not specified error
   - **Issue**: CDK synthesis fails without explicit deployment mode
   - **Fix Required**: Set DEPLOYMENT_MODE environment variable or use context parameter

### Configuration Gaps

1. **Missing Claude Sonnet 4 as Default Model**
   - **Location**: lib/constructs/compute/ec2-deployment.ts:494-495
   - **Current**: Uses Claude 3.5 Sonnet as default
   - **Required**: Change to anthropic.claude-sonnet-4-20250514-v1:0
   - **Also**: config/librechat.yaml:6-7

2. **Missing BEDROCK_AWS_DEFAULT_REGION**
   - **Location**: lib/constructs/compute/ec2-deployment.ts:362
   - **Current**: Sets BEDROCK_AWS_DEFAULT_REGION in RAG section only
   - **Required**: Should be set in main AWS section

3. **Missing availableRegions in Docker librechat.yaml**
   - **Location**: lib/constructs/compute/ec2-deployment.ts:497
   - **Current**: Sets availableRegions in embedded config
   - **Required**: Ensure it's properly formatted

### Dependency Problems
- No package conflicts detected
- CDK version 2.142.1 is current
- Node v24.5.0 warning (non-critical, can be silenced with JSII_SILENCE_WARNING_UNTESTED_NODE_VERSION)

## Implementation Checklist

- [ ] Task 1: Create .env file with DEPLOYMENT_MODE=EC2 or ECS
- [ ] Task 2: Update default Bedrock model to Claude Sonnet 4 in ec2-deployment.ts:494-495
- [ ] Task 3: Update default Bedrock model to Claude Sonnet 4 in ecs-deployment.ts (similar location)
- [ ] Task 4: Update config/librechat.yaml:6-7 to use Claude Sonnet 4 as default
- [ ] Task 5: Add BEDROCK_AWS_DEFAULT_REGION to main environment section in ec2-deployment.ts:329
- [ ] Task 6: Verify IAM role has access to Claude Sonnet 4 model family
- [ ] Task 7: Enable model access in AWS Bedrock console for Claude Sonnet 4
- [ ] Task 8: Configure web search API keys in AWS Secrets Manager (optional)
- [ ] Task 9: Test RAG pipeline with document upload functionality
- [ ] Task 10: Validate ECS deployment configuration for Bedrock access

## Code Snippets Required

### For Bedrock Integration

```typescript
// Update in lib/constructs/compute/ec2-deployment.ts:494-495
'    titleModel: "anthropic.claude-sonnet-4-20250514-v1:0"',
'    defaultModel: "anthropic.claude-sonnet-4-20250514-v1:0"',
```

```typescript
// Add to lib/constructs/compute/ec2-deployment.ts:329 (after AWS_REGION)
`echo "BEDROCK_AWS_DEFAULT_REGION=${cdk.Stack.of(this).region}" >> .env`,
```

### For RAG Pipeline

```typescript
// Already implemented correctly in ec2-deployment.ts:448-473
'  rag-api:',
'    image: ghcr.io/danny-avila/librechat-rag-api-dev:latest',
'    environment:',
'      - EMBEDDINGS_PROVIDER=bedrock',
'      - EMBEDDINGS_MODEL=amazon.titan-embed-text-v2:0',
'      - BEDROCK_AWS_REGION=${region}',
'      - VECTOR_DB_TYPE=pgvector',
```

### For Docker Configuration

```yaml
# Dynamic docker-compose.yml generation is correct
# Located in ec2-deployment.ts:381-483
version: "3.8"
services:
  api:
    image: ghcr.io/danny-avila/librechat:latest
    env_file: .env
    volumes:
      - ./librechat.yaml:/app/librechat.yaml
```

### For Web Search Configuration

```typescript
// Add to AWS Secrets Manager app-secrets:
{
  "jwt_secret": "...",
  "creds_key": "...",
  "creds_iv": "...",
  "google_search_api_key": "YOUR_GOOGLE_API_KEY",  // Optional
  "google_cse_id": "YOUR_GOOGLE_CSE_ID",           // Optional
  "bing_api_key": "YOUR_BING_API_KEY"              // Optional
}
```

## File Modifications Needed

### File: lib/constructs/compute/ec2-deployment.ts
- Line 329: Add `echo "BEDROCK_AWS_DEFAULT_REGION=${cdk.Stack.of(this).region}" >> .env`
- Line 494: Change to `'    titleModel: "anthropic.claude-sonnet-4-20250514-v1:0"'`
- Line 495: Change to `'    defaultModel: "anthropic.claude-sonnet-4-20250514-v1:0"'`

### File: lib/constructs/compute/ecs-deployment.ts
- Find similar titleModel/defaultModel lines (around line 300-400)
- Update to use anthropic.claude-sonnet-4-20250514-v1:0

### File: config/librechat.yaml
- Line 6: Change to `titleModel: "anthropic.claude-sonnet-4-20250514-v1:0"`
- Line 7: Change to `defaultModel: "anthropic.claude-sonnet-4-20250514-v1:0"`

### File: .env (create new)
```bash
DEPLOYMENT_MODE=EC2  # or ECS
KEY_PAIR_NAME=your-ec2-key  # Required for EC2 mode
ALERT_EMAIL=your-email@example.com  # Optional
```

## Testing Commands

```bash
# 1. Validate environment setup
export DEPLOYMENT_MODE=EC2
export KEY_PAIR_NAME=test-key

# 2. Build TypeScript
npm run build

# 3. Synthesize CDK (test configuration)
npm run synth -- -c configSource=minimal-dev

# 4. Run unit tests
npm test

# 5. Estimate costs
npm run estimate-cost minimal-dev

# 6. Deploy to development
npm run deploy:dev

# 7. Test Bedrock connectivity
aws bedrock list-foundation-models --region us-east-1

# 8. Validate RAG API health (after deployment)
curl http://<load-balancer-dns>:8000/health

# 9. Test document upload (after deployment)
# Upload a PDF through LibreChat UI and verify indexing

# 10. Check CloudWatch logs
aws logs tail /aws/ec2/librechat --follow
```

## Error Resolution Map

| Error Message | Root Cause | Fix Required | File Location |
|--------------|------------|--------------|---------------|
| "Deployment mode is required" | Missing DEPLOYMENT_MODE | Set env var or use -c deploymentMode=EC2 | bin/librechat.ts:280 |
| "anthropic.claude-3-5-sonnet" model not found | Wrong model ID | Update to Claude 4 model ID | ec2-deployment.ts:494-495 |
| "RAG API unhealthy" | PostgreSQL not configured | Ensure enableRag=true and RDS is provisioned | deployment-config.ts |
| "Bedrock InvokeModel denied" | Missing IAM permissions | Check IAM role has bedrock:InvokeModel | iam-policies.ts:33-47 |
| "Cannot read property 'secretArn'" | Database not provisioned | Check if enableRag is true | ec2-deployment.ts:266-280 |
| "S3 access denied" | Missing S3 permissions | Verify IAM role has S3 access | iam-policies.ts:87-132 |

## Deployment Strategy

### Phase 1: Environment Setup
1. Create .env file with DEPLOYMENT_MODE
2. Configure AWS credentials
3. Enable Bedrock model access in AWS Console

### Phase 2: Code Updates
1. Update default models to Claude Sonnet 4
2. Add missing environment variables
3. Configure web search API keys (optional)

### Phase 3: Deployment
1. Run `npm run build` to compile
2. Run `npm run synth` to validate
3. Deploy with `npm run deploy:dev`

### Phase 4: Validation
1. Access LibreChat UI
2. Test Bedrock model selection
3. Upload document to test RAG
4. Verify web search functionality

## Success Criteria

✅ CDK synthesizes without errors
✅ Deployment completes successfully
✅ Claude Sonnet 4 appears as default model
✅ Document upload and RAG retrieval works
✅ Web search returns results (if configured)
✅ All health checks pass
✅ CloudWatch logs show no errors

## Additional Notes

1. The codebase is well-structured with good separation of concerns
2. IAM policies follow least-privilege principle
3. Database setup with pgvector is correctly implemented
4. Docker Compose generation is dynamic and environment-aware
5. Both EC2 and ECS deployments are fully functional
6. Cost estimation tools are helpful for budget planning
7. The main issue is configuration, not implementation

## Next Steps

1. Apply the configuration fixes listed above
2. Test deployment in development environment
3. Validate all features work as expected
4. Consider enabling web search APIs for enhanced functionality
5. Set up monitoring alerts for production deployment