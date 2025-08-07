# LibreChat CDK API Reference

## Core Stack

### `LibreChatStack`

Main CDK stack that orchestrates all infrastructure components.

```typescript
class LibreChatStack extends cdk.Stack
```

**Constructor:**
```typescript
constructor(scope: Construct, id: string, props: LibreChatStackProps)
```

**Properties:**
- `vpc: ec2.IVpc` - VPC for all resources
- `cluster?: ecs.Cluster` - ECS cluster (ECS mode only)
- `database?: DatabaseConstruct` - Database resources
- `storage: StorageConstruct` - Storage resources
- `monitoring?: MonitoringConstruct` - Monitoring resources

---

## Compute Constructs

### `EC2Deployment`

Single EC2 instance deployment with Docker Compose.

```typescript
class EC2Deployment extends Construct
```

**Props Interface:**
```typescript
interface EC2DeploymentProps {
  vpc: ec2.IVpc;
  keyPairName: string;
  instanceType?: string;
  allowedIps?: string[];
  database?: {
    endpoint: string;
    port: number;
    secretArn: string;
  };
  storage: {
    bucketName: string;
    bucketArn: string;
  };
  appSecrets: secretsmanager.ISecret;
  enableRag?: boolean;
  enableMeilisearch?: boolean;
  tags?: Record<string, string>;
}
```

**Public Properties:**
- `instance: ec2.Instance` - EC2 instance
- `loadBalancer: elbv2.ApplicationLoadBalancer` - ALB
- `targetGroup: elbv2.ApplicationTargetGroup` - Target group
- `securityGroup: ec2.SecurityGroup` - Instance security group

**Key Methods:**
- `createInstance()` - Creates and configures EC2 instance
- `createLoadBalancer()` - Sets up Application Load Balancer
- `setupAutoRecovery()` - Configures auto-recovery alarm

---

### `ECSDeployment`

Container deployment using ECS Fargate.

```typescript
class ECSDeployment extends Construct
```

**Props Interface:**
```typescript
interface ECSDeploymentProps {
  vpc: ec2.IVpc;
  cluster: ecs.Cluster;
  certificateArn?: string;
  domainName?: string;
  hostedZoneId?: string;
  database?: {
    endpoint: string;
    port: number;
    secretArn: string;
  };
  storage: {
    bucketName: string;
    bucketArn: string;
    fileSystem?: efs.FileSystem;
  };
  appSecrets: secretsmanager.ISecret;
  desiredCount?: number;
  cpu?: number;
  memory?: number;
  enableRag?: boolean;
  enableMeilisearch?: boolean;
  tags?: Record<string, string>;
}
```

**Public Properties:**
- `service: ecs.FargateService` - Main application service
- `loadBalancer: elbv2.ApplicationLoadBalancer` - ALB
- `taskDefinition: ecs.FargateTaskDefinition` - Task definition
- `ragService?: ecs.FargateService` - RAG API service
- `meilisearchService?: ecs.FargateService` - Search service

**Key Methods:**
- `createTaskDefinition()` - Creates ECS task definition
- `createService()` - Sets up Fargate service
- `setupAutoScaling()` - Configures auto-scaling
- `createRagService()` - Creates RAG pipeline service

---

## Database Constructs

### `DatabaseConstruct`

Manages database infrastructure (RDS PostgreSQL or DocumentDB).

```typescript
class DatabaseConstruct extends Construct
```

**Props Interface:**
```typescript
interface DatabaseConstructProps {
  vpc: ec2.IVpc;
  engine: 'postgres' | 'documentdb' | 'aurora';
  instanceClass?: string;
  allocatedStorage?: number;
  backupRetentionDays?: number;
  multiAz?: boolean;
  postgresVersion?: string;
  enablePerformanceInsights?: boolean;
  tags?: Record<string, string>;
}
```

**Public Properties:**
- `instance?: rds.DatabaseInstance` - RDS instance
- `cluster?: docdb.DatabaseCluster` - DocumentDB cluster
- `secret: secretsmanager.ISecret` - Database credentials
- `securityGroup: ec2.SecurityGroup` - Database security group
- `endpoint: string` - Database endpoint
- `port: number` - Database port

**Key Methods:**
- `createPostgresInstance()` - Creates RDS PostgreSQL
- `createDocumentDBCluster()` - Creates DocumentDB cluster
- `createAuroraServerless()` - Creates Aurora Serverless
- `enablePgVector()` - Enables pgvector extension

---

## Storage Constructs

### `StorageConstruct`

Manages S3 buckets and EFS file systems.

```typescript
class StorageConstruct extends Construct
```

**Props Interface:**
```typescript
interface StorageConstructProps {
  environment: string;
  enableVersioning?: boolean;
  enableReplication?: boolean;
  lifecycleRules?: s3.LifecycleRule[];
  enableEfs?: boolean;
  vpc?: ec2.IVpc;
  tags?: Record<string, string>;
}
```

**Public Properties:**
- `documentBucket: s3.Bucket` - Document storage bucket
- `backupBucket?: s3.Bucket` - Backup bucket
- `fileSystem?: efs.FileSystem` - EFS file system
- `accessPoint?: efs.AccessPoint` - EFS access point

**Key Methods:**
- `createDocumentBucket()` - Creates main S3 bucket
- `createBackupBucket()` - Creates backup bucket
- `createFileSystem()` - Creates EFS for containers
- `setupReplication()` - Configures cross-region replication

---

## Network Constructs

### `VpcConstruct`

Network infrastructure management.

```typescript
class VpcConstruct extends Construct
```

**Props Interface:**
```typescript
interface VpcConstructProps {
  useExisting?: boolean;
  vpcId?: string;
  cidr?: string;
  maxAzs?: number;
  natGateways?: number;
  enableFlowLogs?: boolean;
  tags?: Record<string, string>;
}
```

**Public Properties:**
- `vpc: ec2.IVpc` - VPC instance
- `publicSubnets: ec2.ISubnet[]` - Public subnets
- `privateSubnets: ec2.ISubnet[]` - Private subnets
- `isolatedSubnets: ec2.ISubnet[]` - Isolated subnets

**Key Methods:**
- `createVpc()` - Creates new VPC
- `importVpc()` - Imports existing VPC
- `createVpcEndpoints()` - Creates VPC endpoints
- `enableFlowLogs()` - Enables VPC flow logs

---

## Monitoring Constructs

### `MonitoringConstruct`

CloudWatch monitoring and alerting.

```typescript
class MonitoringConstruct extends Construct
```

**Props Interface:**
```typescript
interface MonitoringConstructProps {
  alertEmail?: string;
  environment: string;
  enableDetailedMonitoring?: boolean;
  customMetrics?: CloudWatchMetric[];
  tags?: Record<string, string>;
}
```

**Public Properties:**
- `dashboard: cloudwatch.Dashboard` - Main dashboard
- `alarmTopic: sns.Topic` - SNS topic for alarms
- `alarms: cloudwatch.Alarm[]` - List of alarms

**Key Methods:**
- `createDashboard()` - Creates CloudWatch dashboard
- `createAlarms()` - Sets up alarms
- `createCustomMetrics()` - Adds custom metrics
- `setupNotifications()` - Configures SNS notifications

---

## Security Constructs

### `AuditConstruct`

AWS CloudTrail and Config for auditing.

```typescript
class AuditConstruct extends Construct
```

**Props Interface:**
```typescript
interface AuditConstructProps {
  trailBucket: s3.IBucket;
  enableCloudTrail?: boolean;
  enableConfig?: boolean;
  tags?: Record<string, string>;
}
```

**Public Properties:**
- `trail?: cloudtrail.Trail` - CloudTrail trail
- `configRecorder?: config.CfnConfigurationRecorder` - Config recorder
- `configRules: config.ManagedRule[]` - Config rules

---

### `ComplianceConstruct`

HIPAA and compliance resources.

```typescript
class ComplianceConstruct extends Construct
```

**Props Interface:**
```typescript
interface ComplianceConstructProps {
  enableHipaaCompliance?: boolean;
  enableSoc2Compliance?: boolean;
  tags?: Record<string, string>;
}
```

---

## Utility Functions

### IAM Policy Helpers

```typescript
// Create Bedrock access policies
function createBedrockPolicyStatements(options: BedrockPolicyOptions): PolicyStatement[]

// Create S3 access policies  
function createS3PolicyStatements(options: S3PolicyOptions): PolicyStatement[]

// Create Secrets Manager policies
function createSecretsManagerPolicyStatements(options: SecretsPolicyOptions): PolicyStatement[]

// IP restriction condition
function createIpRestrictionCondition(allowedIps: string[]): Record<string, unknown>

// MFA requirement condition
function createMfaCondition(): Record<string, unknown>
```

### Database Connection Utilities

```typescript
// Build DocumentDB connection string
function buildDocumentDBConnectionString(options: DocumentDBConnectionOptions): string

// Build connection template for scripts
function buildDocumentDBConnectionTemplate(host: string, port?: number): string

// Build ECS connection template
function buildDocumentDBConnectionTemplateECS(host: string, port?: number): string
```

### Tagging Strategy

```typescript
interface StandardTags {
  Environment: string;
  Project: string;
  Owner: string;
  CostCenter: string;
  DataClassification?: string;
  Compliance?: string;
  BackupPolicy?: string;
}

class TaggingStrategy {
  static applyTags(construct: IConstruct, tags: StandardTags): void
  static getRequiredTags(environment: string): StandardTags
  static validateTags(tags: StandardTags): boolean
}
```

---

## Configuration Builder

### `DeploymentConfigBuilder`

Fluent API for building deployment configurations.

```typescript
class DeploymentConfigBuilder
```

**Constructor:**
```typescript
constructor(environment: 'development' | 'staging' | 'production')
```

**Builder Methods:**
```typescript
withDeploymentMode(mode: 'EC2' | 'ECS'): this
withKeyPair(keyPairName: string): this
withDomain(domain: string, certificate?: string, hostedZone?: string): this
withAlertEmail(email: string): this
withAllowedIps(ips: string[]): this
withVpc(config: VpcConfig): this
withDatabase(config: DatabaseConfig): this
withCompute(config: ComputeConfig): this
withFeatures(features: FeatureFlags): this
withTags(tags: Record<string, string>): this
withRag(): this
withMeilisearch(): this
withSharePoint(): this
withEnhancedMonitoring(): this
build(): LibreChatStackProps
```

---

## Types and Interfaces

### Core Types

```typescript
type DeploymentMode = 'EC2' | 'ECS';
type Environment = 'development' | 'staging' | 'production';
type DatabaseEngine = 'postgres' | 'documentdb' | 'aurora';
```

### Feature Flags

```typescript
interface FeatureFlags {
  rag?: boolean;
  meilisearch?: boolean;
  sharepoint?: boolean;
  enhancedMonitoring?: boolean;
  auditLogging?: boolean;
  hipaaCompliance?: boolean;
}
```

### Resource Sizing

```typescript
interface ResourceSize {
  instanceType?: string;
  cpu?: number;
  memory?: number;
  storage?: number;
}

const RESOURCE_SIZES: Record<Environment, ResourceSize> = {
  development: { instanceType: 't3.medium', cpu: 1024, memory: 2048 },
  staging: { instanceType: 't3.large', cpu: 2048, memory: 4096 },
  production: { instanceType: 't3.xlarge', cpu: 4096, memory: 8192 }
};
```

---

## CloudFormation Outputs

Stack outputs available after deployment:

| Output Key | Description | Example |
|------------|-------------|---------|
| `LoadBalancerURL` | Application URL | `http://lb-123.region.elb.amazonaws.com` |
| `LoadBalancerDNS` | Load balancer DNS | `lb-123.region.elb.amazonaws.com` |
| `EC2InstanceId` | EC2 instance ID | `i-0123456789abcdef0` |
| `ClusterName` | ECS cluster name | `LibreChat-production` |
| `ServiceName` | ECS service name | `librechat-service` |
| `DatabaseEndpoint` | Database endpoint | `db.cluster.region.rds.amazonaws.com` |
| `DocumentBucketName` | S3 bucket name | `librechat-docs-123456` |
| `VPCId` | VPC ID | `vpc-0123456789abcdef0` |
| `DashboardURL` | CloudWatch dashboard | `https://console.aws.amazon.com/...` |

---

## Error Handling

Common exceptions and error codes:

```typescript
// Deployment validation errors
class DeploymentValidationError extends Error {
  code: 'INVALID_MODE' | 'MISSING_KEY_PAIR' | 'INVALID_CONFIG';
}

// Resource limit errors
class ResourceLimitError extends Error {
  code: 'QUOTA_EXCEEDED' | 'INSUFFICIENT_CAPACITY';
}

// Configuration errors
class ConfigurationError extends Error {
  code: 'INVALID_PRESET' | 'MISSING_REQUIRED' | 'CONFLICT';
}
```

---

*API Reference v2.0.0 - Generated for LibreChat CDK*