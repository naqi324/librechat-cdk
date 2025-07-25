// bin/librechat.ts
#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { LibreChatStack } from '../lib/librechat-stack';

const app = new cdk.App();

// Get context values for deployment customization
const alertEmail = app.node.tryGetContext('alertEmail');
const instanceType = app.node.tryGetContext('instanceType');
const dbInstanceClass = app.node.tryGetContext('dbInstanceClass');
const enableSharePoint = app.node.tryGetContext('enableSharePoint');

// Deploy the stack
new LibreChatStack(app, 'LibreChatStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'LibreChat Enterprise Deployment with AWS Bedrock, PostgreSQL pgvector, and RAG',
  alertEmail,
  instanceType,
  dbInstanceClass,
  enableSharePoint,

  // Add tags for organization
  tags: {
    Application: 'LibreChat',
    Environment: 'Production',
    ManagedBy: 'CDK',
    CostCenter: 'AI-Platform',
  },
});

// Add stack-level tags
cdk.Tags.of(app).add('Project', 'LibreChat-Enterprise');

app.synth();
