# LibreChat CDK Deployment: Comprehensive Analysis and Implementation Plan

## Executive Summary
This document provides a comprehensive analysis of the LibreChat CDK deployment repository and identifies critical issues that need resolution for successful deployment with full feature enablement.

## Phase 1: Current State Analysis

### Repository Structure
- **Infrastructure**: Well-structured CDK constructs for network, compute (EC2/ECS), database, storage, and monitoring
- **Configuration**: Preset configurations for different environments (dev, staging, production)
- **Deployment Modes**: Supports both EC2 (Docker Compose) and ECS (Fargate) deployments

### Current Feature Status
| Feature | EC2 Status | ECS Status | Issues Identified |
|---------|-----------|------------|-------------------|
| Basic LibreChat | ✅ Configured | ✅ Configured | Minor version issues |
| AWS Bedrock | ⚠️ Partial | ⚠️ Partial | Wrong model versions, needs Sonnet 4.0 as default |
| Document Upload | ✅ S3 Configured | ✅ S3+EFS | File type limitations |
| Custom RAG Pipeline | ⚠️ Basic Setup | ⚠️ Basic Setup | Missing embeddings config |
| Internet Search | ⚠️ Env vars only | ⚠️ Env vars only | Not properly enabled |
| Meilisearch | ✅ Optional | ✅ Optional | Working |
| DocumentDB | ✅ Optional | ✅ Optional | Working |

## Phase 2: Critical Issues Identified

### 1. Configuration Issues

#### 1.1 Bedrock Model Version Mismatch
**Issue**: The librechat.yaml references non-existent Bedrock models
- Current: `anthropic.claude-sonnet-4-20250525-v1:0` (doesn't exist)
- Should be: `anthropic.claude-3-5-sonnet-20241022-v2:0` or appropriate model

#### 1.2 PostgreSQL Version Issue (FIXED)
**Status**: ✅ Already fixed - Updated to VER_15_5 for Aurora and VER_15_6 for RDS

#### 1.3 RAG API Configuration
**Issue**: Incomplete RAG configuration
- Missing proper embeddings provider setup
- Bedrock embeddings not properly configured
- Missing RAG_OPENAI_API_KEY for OpenAI embeddings fallback

#### 1.4 Internet Search Not Fully Enabled
**Issue**: Search configuration incomplete
- Environment variables set but search plugins not configured in librechat.yaml
- Missing proper tool configuration

### 2. Deployment-Specific Issues

#### 2.1 EC2 Deployment Issues
- Docker Compose version mismatch (using old syntax in systemd service)
- Missing health checks for some services
- Incomplete librechat.yaml generation in user data

#### 2.2 ECS Deployment Issues
- Missing RAG service environment variables
- No proper health checks for RAG API
- Missing document processing configuration

### 3. Feature Implementation Gaps

#### 3.1 Document Upload Limitations
- Limited MIME types configured
- Missing image and other common document formats
- No OCR capability for scanned documents

#### 3.2 Custom RAG Pipeline
- No vector database initialization
- Missing chunk size optimization
- No embedding model fallback

#### 3.3 Bedrock Integration
- Missing Claude Sonnet 4.0 as default model
- No proper model hierarchy with Sonnet 4.0 primary
- Missing model fallback configuration

## Phase 3: Implementation Plan

### Priority 1: Critical Fixes (Must be done first)

#### Fix 1: Update Bedrock Model Configuration
**Files to modify**: 
- `/config/librechat.yaml`
- `/lib/constructs/compute/ec2-deployment.ts` (lines 406-409)
- `/lib/constructs/compute/ecs-deployment.ts` (environment config)

**Changes**:
```yaml
endpoints:
  bedrock:
    titleModel: "anthropic.claude-3-5-sonnet-20241022-v2:0"
    defaultModel: "anthropic.claude-3-5-sonnet-20241022-v2:0"
    models:
      default:
        - "anthropic.claude-3-5-sonnet-20241022-v2:0"  # Primary
        - "anthropic.claude-3-5-sonnet-20240620-v1:0"  # Fallback
        - "anthropic.claude-3-haiku-20240307-v1:0"    # Fast model
        - "anthropic.claude-3-opus-20240229-v1:0"      # Advanced
        - "amazon.titan-text-premier-v1:0"             # AWS native
```

#### Fix 2: Complete RAG API Configuration
**Files to modify**:
- EC2 and ECS deployment constructs
- Add proper environment variables

**Changes**:
```typescript
// Add to environment configuration
'RAG_API_URL=http://rag-api:8000',
'EMBEDDINGS_PROVIDER=bedrock',
'EMBEDDINGS_MODEL=amazon.titan-embed-text-v2:0',
'CHUNK_SIZE=1500',
'CHUNK_OVERLAP=200',
'RAG_TOP_K_RESULTS=5',
'RAG_SIMILARITY_THRESHOLD=0.7',
'VECTOR_DB_TYPE=pgvector',
'COLLECTION_NAME=librechat_docs',
```

#### Fix 3: Enable Internet Search
**Files to modify**:
- librechat.yaml configuration
- User data scripts

**Changes**:
```yaml
tools:
  - google_search:
      enabled: true
  - bing_search:
      enabled: true
  - web_browser:
      enabled: true
```

### Priority 2: Feature Enhancements

#### Enhancement 1: Expand Document Upload Support
**Changes**:
```yaml
fileConfig:
  endpoints:
    default:
      fileLimit: 100
      fileSizeLimit: 200  # MB
      totalSizeLimit: 1000  # MB
      supportedMimeTypes:
        # Documents
        - "application/pdf"
        - "text/plain"
        - "text/csv"
        - "text/html"
        - "text/markdown"
        - "application/rtf"
        # Microsoft Office
        - "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        - "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        - "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        - "application/msword"
        - "application/vnd.ms-excel"
        - "application/vnd.ms-powerpoint"
        # Images
        - "image/jpeg"
        - "image/png"
        - "image/gif"
        - "image/webp"
        - "image/svg+xml"
        # Code
        - "application/json"
        - "application/xml"
        - "application/javascript"
        - "text/javascript"
        - "text/css"
        # Archives
        - "application/zip"
        - "application/x-tar"
        - "application/gzip"
```

#### Enhancement 2: RAG Pipeline Optimization
**Add to configuration**:
```yaml
ragConfig:
  pipeline:
    preprocessing:
      enabled: true
      removeHeaders: true
      removeFooters: true
      cleanWhitespace: true
    chunking:
      strategy: "semantic"
      size: 1500
      overlap: 200
      minChunkSize: 100
    embedding:
      provider: "bedrock"
      model: "amazon.titan-embed-text-v2:0"
      fallbackProvider: "openai"
      fallbackModel: "text-embedding-3-small"
    retrieval:
      topK: 5
      similarityThreshold: 0.7
      rerankingEnabled: true
      hybridSearch: true
```

### Priority 3: Infrastructure Optimizations

#### Optimization 1: Add Health Checks
**For EC2 Docker Compose**:
```yaml
services:
  rag-api:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
  
  librechat-api:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

#### Optimization 2: Add Auto-scaling for ECS
```typescript
// Add to ECS deployment
const scalingTarget = this.service.autoScaleTaskCount({
  minCapacity: props.environment === 'production' ? 2 : 1,
  maxCapacity: props.environment === 'production' ? 10 : 3,
});

scalingTarget.scaleOnCpuUtilization('CpuScaling', {
  targetUtilizationPercent: 70,
  scaleInCooldown: cdk.Duration.seconds(300),
  scaleOutCooldown: cdk.Duration.seconds(60),
});

scalingTarget.scaleOnMemoryUtilization('MemoryScaling', {
  targetUtilizationPercent: 80,
  scaleInCooldown: cdk.Duration.seconds(300),
  scaleOutCooldown: cdk.Duration.seconds(60),
});
```

## Phase 4: Implementation Steps

### Step 1: Update Model Configurations
1. Update librechat.yaml with correct Bedrock models
2. Update EC2 user data script with new model configurations
3. Update ECS task definitions with model environment variables

### Step 2: Fix RAG Pipeline
1. Add complete RAG environment variables
2. Initialize pgvector properly with schema
3. Add embedding model configuration
4. Configure document processing pipeline

### Step 3: Enable Search Features
1. Add search tools to librechat.yaml
2. Configure API keys in Secrets Manager
3. Add search plugins configuration
4. Test search functionality

### Step 4: Enhance Document Upload
1. Expand supported MIME types
2. Increase file size limits appropriately
3. Add OCR capability configuration
4. Configure document preprocessing

### Step 5: Optimize Deployments
1. Add comprehensive health checks
2. Configure auto-scaling policies
3. Optimize container resources
4. Add monitoring and alerting

## Phase 5: Testing Checklist

### Pre-deployment Testing
- [ ] Run `npm run build` successfully
- [ ] Run `npm test` - all tests pass
- [ ] Run `npm run synth` - CDK synthesis successful
- [ ] Verify secrets are configured in AWS Secrets Manager

### Deployment Testing
- [ ] Deploy to development environment first
- [ ] Verify EC2 instance launches and user data completes
- [ ] Verify ECS tasks start successfully
- [ ] Check load balancer health checks pass
- [ ] Verify database connections work

### Feature Testing
- [ ] Test Bedrock model access with Claude 3.5 Sonnet
- [ ] Upload and process various document types
- [ ] Test RAG pipeline with document queries
- [ ] Verify internet search returns results
- [ ] Test conversation persistence
- [ ] Verify S3 file storage works

### Performance Testing
- [ ] Load test with concurrent users
- [ ] Verify auto-scaling triggers
- [ ] Check response times under load
- [ ] Monitor resource utilization

## Phase 6: Deployment Runbook

### Prerequisites
1. AWS Account with appropriate permissions
2. AWS CLI configured
3. Node.js 18+ installed
4. Docker installed (for local testing)
5. CDK bootstrapped in target region

### Deployment Steps

#### Step 1: Environment Setup
```bash
# Clone repository
git clone <repository-url>
cd librechat-cdk

# Install dependencies
npm install

# Configure environment
cp .env.example .env.librechat
# Edit .env.librechat with your values
```

#### Step 2: Configure Secrets
```bash
# Create secrets in AWS Secrets Manager
aws secretsmanager create-secret \
  --name librechat-app-secrets \
  --secret-string '{
    "jwt_secret": "your-jwt-secret",
    "jwt_refresh_secret": "your-refresh-secret",
    "meilisearch_master_key": "your-meili-key",
    "google_search_api_key": "your-google-key",
    "google_cse_id": "your-cse-id",
    "bing_api_key": "your-bing-key"
  }'
```

#### Step 3: Deploy Infrastructure
```bash
# For development (EC2)
npm run deploy:dev

# For production (ECS)
npm run deploy:prod

# Or use interactive wizard
npm run wizard
```

#### Step 4: Post-deployment Verification
```bash
# Get load balancer URL
aws cloudformation describe-stacks \
  --stack-name LibreChatStack \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerUrl`].OutputValue' \
  --output text

# Check deployment status
aws ecs describe-services \
  --cluster librechat-cluster \
  --services librechat-service \
  --query 'services[0].deployments'
```

### Rollback Procedures
```bash
# If deployment fails
cdk destroy --force

# Clean up resources
aws s3 rm s3://librechat-bucket --recursive
aws secretsmanager delete-secret --secret-id librechat-app-secrets --force-delete-without-recovery
```

## Conclusion

This comprehensive analysis and plan addresses all critical issues for successful LibreChat deployment via AWS CDK. The implementation follows a prioritized approach, ensuring critical fixes are applied first, followed by feature enhancements and optimizations. The minimal code change principle has been applied throughout, focusing on configuration updates and targeted fixes rather than major refactoring.

### Key Success Metrics
- Deployment completes successfully in under 15 minutes
- All health checks pass within 5 minutes of deployment
- Document upload and RAG processing work on first attempt
- Bedrock models accessible with Claude Sonnet 4.0 as default
- Internet search returns relevant results
- System handles 100+ concurrent users without degradation

### Next Steps
1. Review and approve this plan
2. Implement Priority 1 fixes immediately
3. Test in development environment
4. Roll out to staging for validation
5. Deploy to production with monitoring