// lib/librechat-stack.ts
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as actions from 'aws-cdk-lib/aws-cloudwatch-actions';
import { Construct } from 'constructs';

export interface LibreChatStackProps extends cdk.StackProps {
  /**
   * Email address for CloudWatch alarm notifications
   * @default - No email notifications
   */
  alertEmail?: string;

  /**
   * Domain name for the application (optional)
   * @default - Use ALB DNS name
   */
  domainName?: string;

  /**
   * Instance type for the EC2 instance
   * @default t3.xlarge
   */
  instanceType?: string;

  /**
   * RDS instance class
   * @default db.t3.medium
   */
  dbInstanceClass?: string;

  /**
   * Enable SharePoint integration
   * @default false
   */
  enableSharePoint?: boolean;

  /**
   * SharePoint configuration (required if enableSharePoint is true)
   */
  sharePointConfig?: {
    tenantId: string;
    clientId: string;
    clientSecret: string;
    siteUrl: string;
  };
}

export class LibreChatStack extends cdk.Stack {
  public readonly loadBalancerDnsName: string;
  public readonly instanceId: string;
  public readonly databaseEndpoint: string;
  public readonly s3BucketName: string;

  constructor(scope: Construct, id: string, props?: LibreChatStackProps) {
    super(scope, id, props);

    // Parameters for CloudFormation template
    const alertEmailParam = new cdk.CfnParameter(this, 'AlertEmail', {
      type: 'String',
      description: 'Email address for CloudWatch alarm notifications',
      default: props?.alertEmail || '',
    });

    const keyNameParam = new cdk.CfnParameter(this, 'KeyName', {
      type: 'AWS::EC2::KeyPair::KeyName',
      description: 'EC2 Key Pair for SSH access',
    });

    const allowedIpParam = new cdk.CfnParameter(this, 'AllowedSSHIP', {
      type: 'String',
      description: 'IP address allowed to SSH to the instance (e.g., 1.2.3.4/32)',
      default: '0.0.0.0/0',
      constraintDescription: 'Must be a valid IP CIDR range of the form x.x.x.x/x',
    });

    // ===== NETWORKING =====
    const vpc = new ec2.Vpc(this, 'LibreChatVPC', {
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
      maxAzs: 2,
      natGateways: 0, // Cost optimization - using public subnets
      subnetConfiguration: [
        {
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24,
        },
        {
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
          cidrMask: 24,
        },
      ],
    });

    // ===== SECURITY GROUPS =====
    const albSecurityGroup = new ec2.SecurityGroup(this, 'ALBSecurityGroup', {
      vpc,
      description: 'Security group for LibreChat ALB',
      allowAllOutbound: true,
    });
    albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP traffic'
    );
    albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS traffic'
    );

    const ec2SecurityGroup = new ec2.SecurityGroup(this, 'EC2SecurityGroup', {
      vpc,
      description: 'Security group for LibreChat EC2 instance',
      allowAllOutbound: true,
    });
    ec2SecurityGroup.addIngressRule(
      ec2.Peer.ipv4(allowedIpParam.valueAsString),
      ec2.Port.tcp(22),
      'Allow SSH from specified IP'
    );
    ec2SecurityGroup.addIngressRule(
      albSecurityGroup,
      ec2.Port.tcp(3080),
      'Allow traffic from ALB'
    );

    const rdsSecurityGroup = new ec2.SecurityGroup(this, 'RDSSecurityGroup', {
      vpc,
      description: 'Security group for LibreChat RDS instance',
      allowAllOutbound: false,
    });
    rdsSecurityGroup.addIngressRule(
      ec2SecurityGroup,
      ec2.Port.tcp(5432),
      'Allow PostgreSQL from EC2'
    );

    // ===== DATABASE =====
    const dbPassword = new secretsmanager.Secret(this, 'DBPassword', {
      description: 'Password for LibreChat RDS instance',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: 'librechat_admin' }),
        generateStringKey: 'password',
        excludeCharacters: ' %+~`#$&*()|[]{}:;<>?!\'/@"\\',
        passwordLength: 32,
      },
    });

    const dbParameterGroup = new rds.ParameterGroup(this, 'DBParameterGroup', {
      engine: rds.DatabaseEngine.postgres({
        version: rds.PostgresEngineVersion.VER_15_7,
      }),
      description: 'PostgreSQL 15 with pgvector',
      parameters: {
        'shared_preload_libraries': 'pgvector',
      },
    });

    const database = new rds.DatabaseInstance(this, 'Database', {
      engine: rds.DatabaseEngine.postgres({
        version: rds.PostgresEngineVersion.VER_15_7,
      }),
      instanceType: ec2.InstanceType.of(
        ec2.InstanceClass.T3,
        ec2.InstanceSize.MEDIUM
      ),
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      securityGroups: [rdsSecurityGroup],
      databaseName: 'librechat_db',
      credentials: rds.Credentials.fromSecret(dbPassword),
      allocatedStorage: 100,
      storageType: rds.StorageType.GP3,
      storageEncrypted: true,
      parameterGroup: dbParameterGroup,
      backupRetention: cdk.Duration.days(7),
      deleteAutomatedBackups: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For testing only
    });

    // ===== S3 STORAGE =====
    const s3Bucket = new s3.Bucket(this, 'FileStorage', {
      bucketName: `librechat-files-${this.account}-${this.region}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'delete-old-versions',
          noncurrentVersionExpiration: cdk.Duration.days(30),
          enabled: true,
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For testing only
      autoDeleteObjects: true, // For testing only
    });

    // ===== IAM ROLE FOR EC2 =====
    const ec2Role = new iam.Role(this, 'EC2Role', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'Role for LibreChat EC2 instance',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
      ],
      inlinePolicies: {
        LibreChatPolicy: new iam.PolicyDocument({
          statements: [
            // Bedrock permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'bedrock:InvokeModel',
                'bedrock:InvokeModelWithResponseStream',
                'bedrock:ListFoundationModels',
              ],
              resources: ['*'],
            }),
            // S3 permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
              ],
              resources: [s3Bucket.bucketArn, `${s3Bucket.bucketArn}/*`],
            }),
            // Secrets Manager permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['secretsmanager:GetSecretValue'],
              resources: [dbPassword.secretArn],
            }),
          ],
        }),
      },
    });

    // ===== USER DATA SCRIPT =====
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      // Update and install dependencies
      'apt-get update',
      'apt-get install -y docker.io docker-compose-v2 git nginx certbot python3-certbot-nginx postgresql-client jq',
      'usermod -aG docker ubuntu',
      'systemctl enable docker',
      'systemctl start docker',

      // Wait for docker to be ready
      'sleep 10',

      // Clone LibreChat
      'cd /opt',
      'git clone https://github.com/danny-avila/LibreChat.git',
      'cd /opt/LibreChat',

      // Get database credentials from Secrets Manager
      `DB_SECRET=$(aws secretsmanager get-secret-value --secret-id ${dbPassword.secretArn} --region ${this.region} --query SecretString --output text)`,
      'DB_PASSWORD=$(echo $DB_SECRET | jq -r .password)',
      'DB_USERNAME=$(echo $DB_SECRET | jq -r .username)',

      // Create .env file
      `cat > .env << EOL
HOST=0.0.0.0
PORT=3080

# Database
DATABASE_URL=postgresql://\$DB_USERNAME:\$DB_PASSWORD@${database.dbInstanceEndpointAddress}:5432/librechat_db?sslmode=require

# AWS Configuration (Using IAM Role)
ENDPOINTS=bedrock
BEDROCK_AWS_DEFAULT_REGION=${this.region}

# S3
CDN_PROVIDER=s3
S3_BUCKET_NAME=${s3Bucket.bucketName}
S3_REGION=${this.region}

# RAG
RAG_API_URL=http://rag-api:8000
EMBEDDINGS_PROVIDER=bedrock
EMBEDDINGS_MODEL=amazon.titan-embed-text-v2
CHUNK_SIZE=1000
CHUNK_OVERLAP=200

# Security
JWT_SECRET=\$(openssl rand -hex 32)
CREDS_KEY=\$(openssl rand -hex 32)
CREDS_IV=\$(openssl rand -hex 16)
EOL`,

      // Create docker-compose.yml
      `cat > docker-compose.yml << 'EOL'
version: '3.8'

services:
  librechat:
    image: ghcr.io/danny-avila/librechat:latest
    container_name: librechat
    restart: unless-stopped
    env_file: .env
    depends_on:
      - rag-api
    ports:
      - "3080:3080"
    volumes:
      - ./librechat.yaml:/app/librechat.yaml
      - ./logs:/app/logs

  rag-api:
    image: ghcr.io/danny-avila/librechat-rag-api:latest
    container_name: rag-api
    restart: unless-stopped
    env_file: .env
    ports:
      - "8000:8000"
EOL`,

      // Create librechat.yaml
      `cat > librechat.yaml << 'EOL'
version: 1.0.0

endpoints:
  bedrock:
    enabled: true
    titleModel: "anthropic.claude-3-haiku-20240307-v1:0"
    models:
      default:
        - "anthropic.claude-3-haiku-20240307-v1:0"
        - "anthropic.claude-3-5-sonnet-20241022-v2:0"
        - "anthropic.claude-3-opus-20240229-v1:0"

fileConfig:
  endpoints:
    default:
      fileLimit: 20
      fileSizeLimit: 100
      supportedMimeTypes:
        - "application/pdf"
        - "text/plain"
        - "text/csv"

rateLimits:
  messages:
    max: 100
    windowMs: 60000

registration:
  enabled: true
EOL`,

      // Initialize database
      'sleep 30', // Wait for RDS to be ready
      `PGPASSWORD=$DB_PASSWORD psql -h ${database.dbInstanceEndpointAddress} -U $DB_USERNAME -d postgres -c "CREATE DATABASE librechat_db;" || true`,
      `PGPASSWORD=$DB_PASSWORD psql -h ${database.dbInstanceEndpointAddress} -U $DB_USERNAME -d librechat_db -c "CREATE EXTENSION IF NOT EXISTS vector;" || true`,
      `PGPASSWORD=$DB_PASSWORD psql -h ${database.dbInstanceEndpointAddress} -U $DB_USERNAME -d librechat_db -c "CREATE EXTENSION IF NOT EXISTS uuid-ossp;" || true`,

      // Create vector tables
      `PGPASSWORD=$DB_PASSWORD psql -h ${database.dbInstanceEndpointAddress} -U $DB_USERNAME -d librechat_db << 'EOSQL'
CREATE TABLE IF NOT EXISTS langchain_pg_embedding (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    collection_id UUID,
    embedding vector(1536),
    document TEXT,
    cmetadata JSONB,
    custom_id TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS langchain_pg_embedding_vector_idx
ON langchain_pg_embedding
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);
EOSQL`,

      // Set permissions
      'chown -R ubuntu:ubuntu /opt/LibreChat',

      // Start services
      'cd /opt/LibreChat',
      'sudo -u ubuntu docker-compose pull',
      'sudo -u ubuntu docker-compose up -d',

      // Configure Nginx
      `cat > /etc/nginx/sites-available/default << 'EOL'
upstream librechat {
    server localhost:3080;
}

server {
    listen 80 default_server;
    server_name _;

    client_max_body_size 100M;

    location / {
        proxy_pass http://librechat;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
}
EOL`,

      'systemctl restart nginx',

      // Signal completion
      'echo "LibreChat setup complete!" > /opt/setup-complete.txt',
    );

    // Add SharePoint configuration if enabled
    if (props?.enableSharePoint && props?.sharePointConfig) {
      userData.addCommands(
        `echo "" >> /opt/LibreChat/.env`,
        `echo "# SharePoint Configuration" >> /opt/LibreChat/.env`,
        `echo "SHAREPOINT_TENANT_ID=${props.sharePointConfig.tenantId}" >> /opt/LibreChat/.env`,
        `echo "SHAREPOINT_CLIENT_ID=${props.sharePointConfig.clientId}" >> /opt/LibreChat/.env`,
        `echo "SHAREPOINT_CLIENT_SECRET=${props.sharePointConfig.clientSecret}" >> /opt/LibreChat/.env`,
        `echo "SHAREPOINT_SITE_URL=${props.sharePointConfig.siteUrl}" >> /opt/LibreChat/.env`,
        'cd /opt/LibreChat && sudo -u ubuntu docker-compose restart'
      );
    }

    // ===== EC2 INSTANCE =====
    // Use SSM Parameter Store to get the latest Ubuntu 22.04 AMI
    const ubuntuAmiParameter = ec2.MachineImage.fromSsmParameter(
      '/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp3/ami-id',
      {
        os: ec2.OperatingSystemType.LINUX,
        userData: userData,
      }
    );

    const instance = new ec2.Instance(this, 'LibreChatInstance', {
      vpc,
      instanceType: new ec2.InstanceType(props?.instanceType || 't3.xlarge'),
      machineImage: ubuntuAmiParameter,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
      securityGroup: ec2SecurityGroup,
      role: ec2Role,
      keyName: keyNameParam.valueAsString,
      userData,
      blockDevices: [
        {
          deviceName: '/dev/sda1',
          volume: ec2.BlockDeviceVolume.ebs(100, {
            volumeType: ec2.EbsDeviceVolumeType.GP3,
            encrypted: true,
          }),
        },
      ],
    });

    // Add tags
    cdk.Tags.of(instance).add('Name', 'librechat-server');
    cdk.Tags.of(instance).add('Application', 'LibreChat');

    // ===== LOAD BALANCER =====
    const targetGroup = new elbv2.ApplicationTargetGroup(this, 'TargetGroup', {
      vpc,
      port: 3080,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.INSTANCE,
      healthCheck: {
        path: '/health',
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(10),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
    });

    targetGroup.addTarget(
      new elbv2.InstanceTarget(instance, 3080)
    );

    const alb = new elbv2.ApplicationLoadBalancer(this, 'LoadBalancer', {
      vpc,
      internetFacing: true,
      securityGroup: albSecurityGroup,
    });

    const listener = alb.addListener('Listener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [targetGroup],
    });

    // ===== MONITORING =====
    const alarmTopic = new sns.Topic(this, 'AlarmTopic', {
      displayName: 'LibreChat Alarms',
    });

    if (alertEmailParam.valueAsString) {
      alarmTopic.addSubscription(
        new subscriptions.EmailSubscription(alertEmailParam.valueAsString)
      );
    }

    // CPU Alarm
    const cpuAlarm = new cloudwatch.Alarm(this, 'HighCPUAlarm', {
      metric: new cloudwatch.Metric({
        namespace: 'AWS/EC2',
        metricName: 'CPUUtilization',
        dimensionsMap: {
          InstanceId: instance.instanceId,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 80,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'CPU utilization is too high',
    });

    cpuAlarm.addAlarmAction(new actions.SnsAction(alarmTopic));

    // Database connections alarm
    const dbConnectionsAlarm = new cloudwatch.Alarm(this, 'HighDBConnectionsAlarm', {
      metric: new cloudwatch.Metric({
        namespace: 'AWS/RDS',
        metricName: 'DatabaseConnections',
        dimensionsMap: {
          DBInstanceIdentifier: database.instanceIdentifier,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 80,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'Database connections are too high',
    });

    dbConnectionsAlarm.addAlarmAction(new actions.SnsAction(alarmTopic));

    // ===== OUTPUTS =====
    this.loadBalancerDnsName = alb.loadBalancerDnsName;
    this.instanceId = instance.instanceId;
    this.databaseEndpoint = database.dbInstanceEndpointAddress;
    this.s3BucketName = s3Bucket.bucketName;

    new cdk.CfnOutput(this, 'LoadBalancerURL', {
      value: `http://${alb.loadBalancerDnsName}`,
      description: 'URL to access LibreChat',
    });

    new cdk.CfnOutput(this, 'SSHCommand', {
      value: `ssh -i ${keyNameParam.valueAsString}.pem ubuntu@${instance.instancePublicIp}`,
      description: 'SSH command to connect to the instance',
    });

    new cdk.CfnOutput(this, 'InstanceId', {
      value: instance.instanceId,
      description: 'EC2 Instance ID',
    });

    new cdk.CfnOutput(this, 'DatabaseEndpoint', {
      value: database.dbInstanceEndpointAddress,
      description: 'RDS Database endpoint',
    });

    new cdk.CfnOutput(this, 'S3BucketName', {
      value: s3Bucket.bucketName,
      description: 'S3 bucket for file storage',
    });

    new cdk.CfnOutput(this, 'SetupInstructions', {
      value: `
1. Wait 5-10 minutes for the instance to complete setup
2. Access LibreChat at: http://${alb.loadBalancerDnsName}
3. Create your first user account
4. For HTTPS, set up a domain name and SSL certificate
5. Monitor the instance: aws ec2 get-console-output --instance-id ${instance.instanceId}
      `,
      description: 'Next steps after deployment',
    });
  }
}
