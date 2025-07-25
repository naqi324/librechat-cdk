# LibreChat CDK Security Best Practices

## Overview

This guide provides comprehensive security best practices for deploying and operating LibreChat on AWS using the CDK implementation.

## Table of Contents

1. [Infrastructure Security](#infrastructure-security)
2. [Network Security](#network-security)
3. [Identity and Access Management](#identity-and-access-management)
4. [Data Protection](#data-protection)
5. [Application Security](#application-security)
6. [Monitoring and Compliance](#monitoring-and-compliance)
7. [Incident Response](#incident-response)
8. [Security Checklist](#security-checklist)

## Infrastructure Security

### 1. Use Latest AMIs and Container Images

**Always use the latest AMIs:**
```typescript
const ami = ec2.MachineImage.latestAmazonLinux2023({
  cpuType: ec2.AmazonLinuxCpuType.X86_64,
});
```

**Scan container images:**
```bash
# Scan before deployment
trivy image ghcr.io/danny-avila/librechat:latest

# Enable ECR scanning
aws ecr put-image-scanning-configuration \
  --repository-name librechat \
  --image-scanning-configuration scanOnPush=true
```

### 2. Enable Automatic Security Updates

**EC2 User Data:**
```bash
#!/bin/bash
# Enable automatic security updates
echo "Enabling automatic security updates..."
yum install -y yum-cron
sed -i 's/apply_updates = no/apply_updates = yes/g' /etc/yum/yum-cron.conf
systemctl enable yum-cron
systemctl start yum-cron
```

**ECS Task Definition:**
```typescript
taskDefinition.addContainer('librechat', {
  image: ecs.ContainerImage.fromRegistry('ghcr.io/danny-avila/librechat:latest'),
  // Pull latest image on each deployment
  imagePullPolicy: ecs.ImagePullPolicy.ALWAYS,
});
```

### 3. Implement Resource Tagging

```typescript
cdk.Tags.of(stack).add('Environment', environment);
cdk.Tags.of(stack).add('DataClassification', 'Confidential');
cdk.Tags.of(stack).add('Compliance', 'HIPAA');
cdk.Tags.of(stack).add('Owner', 'AI-Team');
cdk.Tags.of(stack).add('CostCenter', 'Engineering');
```

## Network Security

### 1. VPC Configuration

**Use private subnets for sensitive resources:**
```typescript
const vpc = new ec2.Vpc(this, 'VPC', {
  maxAzs: 3, // Multi-AZ for high availability
  natGateways: 2, // Redundant NAT gateways
  subnetConfiguration: [
    {
      name: 'Public',
      subnetType: ec2.SubnetType.PUBLIC,
      cidrMask: 24,
    },
    {
      name: 'Private',
      subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      cidrMask: 24,
    },
    {
      name: 'Isolated',
      subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      cidrMask: 24,
    },
  ],
  // Enable flow logs
  flowLogs: {
    'VPCFlowLogs': {
      destination: ec2.FlowLogDestination.toCloudWatchLogs(),
      trafficType: ec2.FlowLogTrafficType.ALL,
    },
  },
});
```

### 2. Security Group Best Practices

**Principle of least privilege:**
```typescript
// ALB Security Group - Only allow necessary ports
const albSecurityGroup = new ec2.SecurityGroup(this, 'ALBSecurityGroup', {
  vpc,
  description: 'Security group for LibreChat ALB',
  allowAllOutbound: false, // Explicit outbound rules
});

albSecurityGroup.addIngressRule(
  ec2.Peer.anyIpv4(),
  ec2.Port.tcp(443),
  'Allow HTTPS from internet'
);

// Enforce HTTPS only
albSecurityGroup.addIngressRule(
  ec2.Peer.anyIpv4(),
  ec2.Port.tcp(80),
  'Allow HTTP for redirect only'
);

// Application Security Group - Only from ALB
const appSecurityGroup = new ec2.SecurityGroup(this, 'AppSecurityGroup', {
  vpc,
  description: 'Security group for LibreChat application',
  allowAllOutbound: false,
});

appSecurityGroup.addIngressRule(
  albSecurityGroup,
  ec2.Port.tcp(3080),
  'Allow traffic from ALB only'
);

// Database Security Group - Only from app
const dbSecurityGroup = new ec2.SecurityGroup(this, 'DBSecurityGroup', {
  vpc,
  description: 'Security group for database',
  allowAllOutbound: false,
});

dbSecurityGroup.addIngressRule(
  appSecurityGroup,
  ec2.Port.tcp(5432),
  'Allow PostgreSQL from application only'
);
```

### 3. Network ACLs

```typescript
const nacl = new ec2.NetworkAcl(this, 'IsolatedSubnetNACL', {
  vpc,
  subnetSelection: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
});

// Deny all inbound traffic by default
nacl.addEntry('DenyAllInbound', {
  ruleNumber: 100,
  cidr: ec2.AclCidr.anyIpv4(),
  traffic: ec2.AclTraffic.allTraffic(),
  direction: ec2.TrafficDirection.INGRESS,
  ruleAction: ec2.Action.DENY,
});

// Allow specific traffic
nacl.addEntry('AllowAppTraffic', {
  ruleNumber: 90,
  cidr: ec2.AclCidr.ipv4('10.0.1.0/24'), // App subnet
  traffic: ec2.AclTraffic.tcpPort(5432),
  direction: ec2.TrafficDirection.INGRESS,
  ruleAction: ec2.Action.ALLOW,
});
```

### 4. AWS WAF Integration

```typescript
const webAcl = new wafv2.CfnWebACL(this, 'LibreChatWAF', {
  scope: 'REGIONAL',
  defaultAction: { allow: {} },
  rules: [
    {
      name: 'RateLimitRule',
      priority: 1,
      statement: {
        rateBasedStatement: {
          limit: 2000,
          aggregateKeyType: 'IP',
        },
      },
      action: { block: {} },
      visibilityConfig: {
        sampledRequestsEnabled: true,
        cloudWatchMetricsEnabled: true,
        metricName: 'RateLimitRule',
      },
    },
    {
      name: 'SQLiRule',
      priority: 2,
      statement: {
        managedRuleGroupStatement: {
          vendorName: 'AWS',
          name: 'AWSManagedRulesSQLiRuleSet',
        },
      },
      overrideAction: { none: {} },
      visibilityConfig: {
        sampledRequestsEnabled: true,
        cloudWatchMetricsEnabled: true,
        metricName: 'SQLiRule',
      },
    },
  ],
  visibilityConfig: {
    sampledRequestsEnabled: true,
    cloudWatchMetricsEnabled: true,
    metricName: 'LibreChatWAF',
  },
});
```

## Identity and Access Management

### 1. IAM Role Best Practices

```typescript
// Minimal permissions for EC2 instance
const instanceRole = new iam.Role(this, 'InstanceRole', {
  assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
  description: 'Minimal role for LibreChat EC2 instance',
});

// S3 access - specific bucket only
instanceRole.addToPolicy(new iam.PolicyStatement({
  effect: iam.Effect.ALLOW,
  actions: [
    's3:GetObject',
    's3:PutObject',
    's3:DeleteObject',
  ],
  resources: [`${bucket.bucketArn}/*`],
  conditions: {
    StringEquals: {
      's3:x-amz-server-side-encryption': 'AES256',
    },
  },
}));

// Bedrock access - specific models only
instanceRole.addToPolicy(new iam.PolicyStatement({
  effect: iam.Effect.ALLOW,
  actions: [
    'bedrock:InvokeModel',
    'bedrock:InvokeModelWithResponseStream',
  ],
  resources: [
    'arn:aws:bedrock:*::foundation-model/anthropic.claude-*',
    'arn:aws:bedrock:*::foundation-model/amazon.titan-*',
  ],
}));

// Secrets Manager - specific secrets only
instanceRole.addToPolicy(new iam.PolicyStatement({
  effect: iam.Effect.ALLOW,
  actions: [
    'secretsmanager:GetSecretValue',
    'secretsmanager:DescribeSecret',
  ],
  resources: [
    dbSecret.secretArn,
    appSecret.secretArn,
  ],
  conditions: {
    StringEquals: {
      'secretsmanager:VersionStage': 'AWSCURRENT',
    },
  },
}));
```

### 2. Service-Linked Roles

```typescript
// Use service-linked roles where possible
new iam.ServiceLinkedRole(this, 'ECSServiceLinkedRole', {
  awsServiceName: 'ecs.amazonaws.com',
});

new iam.ServiceLinkedRole(this, 'RDSEnhancedMonitoringRole', {
  awsServiceName: 'rds.amazonaws.com',
});
```

### 3. Cross-Account Access

```typescript
// If needed, use external IDs for cross-account access
const crossAccountRole = new iam.Role(this, 'CrossAccountRole', {
  assumedBy: new iam.AccountPrincipal('123456789012').withConditions({
    StringEquals: {
      'sts:ExternalId': cdk.SecretValue.secretsManager('cross-account-external-id'),
    },
  }),
  maxSessionDuration: cdk.Duration.hours(1),
});
```

## Data Protection

### 1. Encryption at Rest

```typescript
// S3 Bucket Encryption
const bucket = new s3.Bucket(this, 'DataBucket', {
  encryption: s3.BucketEncryption.S3_MANAGED,
  bucketKeyEnabled: true, // Reduce encryption costs
  enforceSSL: true,
  blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
  versioned: true,
  lifecycleRules: [{
    id: 'delete-old-versions',
    noncurrentVersionExpiration: cdk.Duration.days(90),
    abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
  }],
});

// RDS Encryption
const database = new rds.DatabaseInstance(this, 'Database', {
  engine: rds.DatabaseInstanceEngine.postgres({
    version: rds.PostgresEngineVersion.VER_15_7,
  }),
  storageEncrypted: true,
  storageEncryptionKey: kms.Key.fromLookup(this, 'RDSKey', {
    aliasName: 'alias/aws/rds',
  }),
});

// EFS Encryption
const fileSystem = new efs.FileSystem(this, 'FileSystem', {
  vpc,
  encrypted: true,
  kmsKey: new kms.Key(this, 'EFSKey', {
    enableKeyRotation: true,
    description: 'KMS key for EFS encryption',
  }),
});

// Secrets Manager
const secret = new secretsmanager.Secret(this, 'AppSecret', {
  description: 'LibreChat application secrets',
  encryptionKey: new kms.Key(this, 'SecretsKey', {
    enableKeyRotation: true,
  }),
});
```

### 2. Encryption in Transit

```typescript
// Enforce TLS for RDS
const parameterGroup = new rds.ParameterGroup(this, 'ParameterGroup', {
  engine: rds.DatabaseInstanceEngine.postgres({
    version: rds.PostgresEngineVersion.VER_15_7,
  }),
  parameters: {
    'rds.force_ssl': '1',
  },
});

// ALB HTTPS Only
const listener = alb.addListener('HTTPSListener', {
  port: 443,
  protocol: elbv2.ApplicationProtocol.HTTPS,
  certificates: [certificate],
  sslPolicy: elbv2.SslPolicy.TLS13_RES,
});

// Redirect HTTP to HTTPS
alb.addListener('HTTPListener', {
  port: 80,
  protocol: elbv2.ApplicationProtocol.HTTP,
  defaultAction: elbv2.ListenerAction.redirect({
    port: '443',
    protocol: 'HTTPS',
    permanent: true,
  }),
});
```

### 3. Data Loss Prevention

```typescript
// Enable backups
const backupPlan = backup.BackupPlan.daily35DayRetention(this, 'BackupPlan');

backupPlan.addSelection('BackupSelection', {
  resources: [
    backup.BackupResource.fromRdsDatabaseInstance(database),
    backup.BackupResource.fromEfsFileSystem(fileSystem),
  ],
  allowRestores: false, // Prevent accidental restores
});

// Enable point-in-time recovery
const table = new dynamodb.Table(this, 'Table', {
  partitionKey: { name: 'id', type: dynamodb.AttributeType.STRING },
  pointInTimeRecovery: true,
  stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
});
```

## Application Security

### 1. Environment Variables

```typescript
// Never hardcode secrets
const container = taskDefinition.addContainer('app', {
  image: ecs.ContainerImage.fromRegistry('app:latest'),
  environment: {
    NODE_ENV: 'production',
    LOG_LEVEL: 'info',
    // Non-sensitive configuration only
  },
  secrets: {
    // All sensitive values from Secrets Manager
    DATABASE_URL: ecs.Secret.fromSecretsManager(dbSecret, 'url'),
    JWT_SECRET: ecs.Secret.fromSecretsManager(appSecret, 'jwtSecret'),
    API_KEYS: ecs.Secret.fromSecretsManager(apiKeysSecret),
  },
});
```

### 2. Container Security

```typescript
// Run as non-root user
taskDefinition.addContainer('app', {
  image: ecs.ContainerImage.fromRegistry('app:latest'),
  user: '1000:1000', // Non-root user
  readonlyRootFilesystem: true,
  linuxParameters: new ecs.LinuxParameters(this, 'LinuxParams', {
    initProcessEnabled: true,
  }),
});

// Security options
container.linuxParameters?.addCapabilities(
  // Drop all capabilities
  ecs.Capability.ALL,
);

container.linuxParameters?.dropCapabilities(
  // Only add back what's needed
  ecs.Capability.NET_BIND_SERVICE,
);
```

### 3. Input Validation

```typescript
// API Gateway request validation
const requestValidator = new apigateway.RequestValidator(this, 'Validator', {
  restApi: api,
  validateRequestBody: true,
  validateRequestParameters: true,
});

// Model for request validation
const userModel = api.addModel('UserModel', {
  contentType: 'application/json',
  schema: {
    type: apigateway.JsonSchemaType.OBJECT,
    properties: {
      email: {
        type: apigateway.JsonSchemaType.STRING,
        pattern: '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$',
      },
      name: {
        type: apigateway.JsonSchemaType.STRING,
        minLength: 1,
        maxLength: 100,
      },
    },
    required: ['email', 'name'],
  },
});
```

## Monitoring and Compliance

### 1. Enable AWS Security Services

```typescript
// GuardDuty
new guardduty.CfnDetector(this, 'GuardDuty', {
  enable: true,
  findingPublishingFrequency: 'SIX_HOURS',
  dataSources: {
    s3Logs: { enable: true },
    kubernetes: { auditLogs: { enable: true } },
  },
});

// Security Hub
new securityhub.CfnHub(this, 'SecurityHub', {
  controlFindingGenerator: 'SECURITY_CONTROL',
  enableDefaultStandards: true,
  autoEnableControls: true,
});

// AWS Config
new config.CfnConfigurationRecorder(this, 'ConfigRecorder', {
  name: 'LibreChat-Config',
  roleArn: configRole.roleArn,
  recordingGroup: {
    allSupported: true,
    includeGlobalResourceTypes: true,
  },
});
```

### 2. CloudTrail Logging

```typescript
const trail = new cloudtrail.Trail(this, 'Trail', {
  bucket: logBucket,
  encryptionKey: trailKey,
  includeGlobalServiceEvents: true,
  isMultiRegionTrail: true,
  enableFileValidation: true,
  eventSelectors: [{
    readWriteType: cloudtrail.ReadWriteType.ALL,
    includeManagementEvents: true,
    dataResources: [{
      dataResourceType: cloudtrail.DataResourceType.S3_OBJECT,
      values: [`${dataBucket.bucketArn}/`],
    }],
  }],
});
```

### 3. Compliance Monitoring

```typescript
// Create compliance dashboard
const dashboard = new cloudwatch.Dashboard(this, 'ComplianceDashboard', {
  dashboardName: 'LibreChat-Compliance',
  widgets: [
    [
      new cloudwatch.GraphWidget({
        title: 'Unauthorized API Calls',
        left: [unauthorizedMetric],
      }),
      new cloudwatch.GraphWidget({
        title: 'Failed Login Attempts',
        left: [failedLoginMetric],
      }),
    ],
    [
      new cloudwatch.SingleValueWidget({
        title: 'Security Score',
        metrics: [securityScoreMetric],
      }),
    ],
  ],
});
```

## Incident Response

### 1. Automated Response

```typescript
// Lambda for automated remediation
const remediationFunction = new lambda.Function(this, 'RemediationFunction', {
  runtime: lambda.Runtime.PYTHON_3_11,
  handler: 'remediate.handler',
  code: lambda.Code.fromAsset('lambda/security'),
  environment: {
    SLACK_WEBHOOK: secretsManager.Secret.fromSecretNameV2(
      this, 'SlackWebhook', 'slack-webhook'
    ).secretValue.unsafeUnwrap(),
  },
});

// EventBridge rule for GuardDuty findings
new events.Rule(this, 'GuardDutyRule', {
  eventPattern: {
    source: ['aws.guardduty'],
    detailType: ['GuardDuty Finding'],
    detail: {
      severity: [{ numeric: ['>=', 7] }],
    },
  },
  targets: [
    new targets.LambdaFunction(remediationFunction),
    new targets.SnsTopic(alertTopic),
  ],
});
```

### 2. Incident Response Runbook

```typescript
// Systems Manager document for incident response
new ssm.CfnDocument(this, 'IncidentResponseRunbook', {
  documentType: 'Automation',
  content: {
    schemaVersion: '0.3',
    description: 'LibreChat Incident Response Runbook',
    mainSteps: [
      {
        name: 'IsolateInstance',
        action: 'aws:changeInstanceState',
        inputs: {
          InstanceIds: ['{{ InstanceId }}'],
          DesiredState: 'stopped',
        },
      },
      {
        name: 'CreateSnapshot',
        action: 'aws:createSnapshot',
        inputs: {
          VolumeId: '{{ VolumeId }}',
          Description: 'Incident Response Snapshot',
        },
      },
      {
        name: 'NotifyTeam',
        action: 'aws:sns:publish',
        inputs: {
          TopicArn: alertTopic.topicArn,
          Message: 'Incident response initiated for {{ InstanceId }}',
        },
      },
    ],
  },
});
```

## Security Checklist

### Pre-Deployment

- [ ] All container images scanned for vulnerabilities
- [ ] IAM roles follow least privilege principle
- [ ] Secrets stored in Secrets Manager
- [ ] VPC configured with private subnets
- [ ] Security groups restrict access appropriately
- [ ] Encryption enabled for all data stores
- [ ] Backup strategy implemented
- [ ] WAF rules configured
- [ ] SSL/TLS certificates valid

### Post-Deployment

- [ ] GuardDuty enabled and monitored
- [ ] Security Hub standards enabled
- [ ] CloudTrail logging active
- [ ] VPC Flow Logs enabled
- [ ] Automated patching configured
- [ ] Incident response plan tested
- [ ] Regular security audits scheduled
- [ ] Penetration testing completed
- [ ] Compliance requirements verified

### Ongoing Operations

- [ ] Monitor security alerts daily
- [ ] Review access logs weekly
- [ ] Update dependencies monthly
- [ ] Conduct security reviews quarterly
- [ ] Perform disaster recovery drills
- [ ] Audit IAM permissions
- [ ] Review cost anomalies
- [ ] Update security documentation

Remember: Security is everyone's responsibility. When in doubt, escalate!
