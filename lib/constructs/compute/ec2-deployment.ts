import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as elbv2_targets from 'aws-cdk-lib/aws-elasticloadbalancingv2-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as route53_targets from 'aws-cdk-lib/aws-route53-targets';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { Construct } from 'constructs';

import { DatabaseConstruct } from '../database/database-construct';
import { StorageConstruct } from '../storage/storage-construct';
import {
  createBedrockPolicyStatements,
  createS3PolicyStatements,
  createSecretsManagerPolicyStatements,
} from '../../utils/iam-policies';

export interface EC2DeploymentProps {
  vpc: ec2.IVpc;
  instanceType: string;
  keyPairName: string;
  allowedIps: string[];
  storage: StorageConstruct;
  database: DatabaseConstruct;
  appSecrets: secretsmanager.ISecret;
  domainConfig?: {
    domainName: string;
    certificateArn?: string;
    hostedZoneId?: string;
  };
  environment: string;
  enableRag: boolean;
  enableMeilisearch: boolean;
}

export class EC2Deployment extends Construct {
  public readonly instance: ec2.Instance;
  public readonly loadBalancer: elbv2.ApplicationLoadBalancer;
  public readonly loadBalancerUrl: string;
  public readonly securityGroup: ec2.SecurityGroup;
  private targetGroup: elbv2.ApplicationTargetGroup;

  constructor(scope: Construct, id: string, props: EC2DeploymentProps) {
    super(scope, id);

    // Validate required properties
    if (!props.keyPairName || props.keyPairName.trim() === '') {
      throw new Error(
        'EC2Deployment: keyPairName cannot be empty. ' +
        'Please create an EC2 key pair in AWS console and provide its name.'
      );
    }

    // Create security groups
    const albSecurityGroup = this.createAlbSecurityGroup(props);
    this.securityGroup = this.createInstanceSecurityGroup(props, albSecurityGroup);

    // Create IAM role for EC2 instance
    const instanceRole = this.createInstanceRole(props);

    // Create Application Load Balancer first (needed for instance user data)
    this.loadBalancer = this.createLoadBalancer(props, albSecurityGroup);

    // Create EC2 instance (can now reference loadBalancer)
    this.instance = this.createInstance(props, instanceRole);

    // Configure target group and listener
    this.targetGroup = this.createTargetGroup(props);
    this.configureListener(props, this.targetGroup);

    // Register instance with target group
    this.targetGroup.addTarget(new elbv2_targets.InstanceTarget(this.instance, 3080));

    // Set up domain if configured
    if (props.domainConfig?.hostedZoneId) {
      this.configureDomain(props);
      this.loadBalancerUrl = `https://${props.domainConfig.domainName}`;
    } else {
      this.loadBalancerUrl = `http://${this.loadBalancer.loadBalancerDnsName}`;
    }

    // Create CloudWatch dashboard
    this.createDashboard(props);
  }

  private createAlbSecurityGroup(props: EC2DeploymentProps): ec2.SecurityGroup {
    const sg = new ec2.SecurityGroup(this, 'ALBSecurityGroup', {
      vpc: props.vpc,
      description: 'Security group for LibreChat ALB',
      allowAllOutbound: false,
    });

    sg.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(80), 'Allow HTTP traffic');

    if (props.domainConfig) {
      sg.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(443), 'Allow HTTPS traffic');
    }

    // Add outbound rule to allow traffic to EC2 instance
    sg.addEgressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(3080), 'Allow traffic to EC2 instance');

    return sg;
  }

  private createInstanceSecurityGroup(
    props: EC2DeploymentProps,
    albSg: ec2.SecurityGroup
  ): ec2.SecurityGroup {
    const sg = new ec2.SecurityGroup(this, 'InstanceSecurityGroup', {
      vpc: props.vpc,
      description: 'Security group for LibreChat EC2 instance',
      allowAllOutbound: false,
    });

    // Add specific outbound rules
    sg.addEgressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS outbound for package downloads and API calls'
    );

    sg.addEgressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP outbound for package downloads'
    );

    // Allow DNS resolution
    sg.addEgressRule(ec2.Peer.anyIpv4(), ec2.Port.udp(53), 'Allow DNS resolution');

    // Allow outbound PostgreSQL traffic for RAG API
    sg.addEgressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(5432), 'Allow PostgreSQL outbound for containers');

    // Allow SSH from specified IPs
    props.allowedIps.forEach((ip) => {
      sg.addIngressRule(ec2.Peer.ipv4(ip), ec2.Port.tcp(22), `Allow SSH from ${ip}`);
    });

    // Allow traffic from ALB
    sg.addIngressRule(albSg, ec2.Port.tcp(3080), 'Allow traffic from ALB');

    // Allow traffic to databases
    if (props.database.securityGroups['postgres']) {
      props.database.securityGroups['postgres'].addIngressRule(
        sg,
        ec2.Port.tcp(5432),
        'Allow PostgreSQL from EC2 instance'
      );
    }

    if (props.database.securityGroups['documentdb']) {
      props.database.securityGroups['documentdb'].addIngressRule(
        sg,
        ec2.Port.tcp(27017),
        'Allow DocumentDB from EC2 instance'
      );
    }

    return sg;
  }

  private createInstanceRole(props: EC2DeploymentProps): iam.Role {
    const role = new iam.Role(this, 'InstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for LibreChat EC2 instance',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
      ],
    });

    // Add S3 permissions using utility function
    const s3Statements = createS3PolicyStatements({
      bucketArn: props.storage.s3Bucket.bucketArn,
      allowDelete: true, // LibreChat needs to manage uploaded files
      requireEncryption: true,
    });
    s3Statements.forEach((statement) => role.addToPolicy(statement));

    // Add Bedrock permissions using utility function
    const bedrockStatements = createBedrockPolicyStatements({
      region: cdk.Stack.of(this).region,
      modelFamilies: ['anthropic.claude-*', 'amazon.titan-*', 'meta.llama*', 'mistral.*'],
    });
    bedrockStatements.forEach((statement) => role.addToPolicy(statement));

    // Add Secrets Manager permissions using utility function
    const secretArns = [
      props.appSecrets.secretArn,
      ...Object.values(props.database.secrets).map((secret) => secret.secretArn),
    ];
    const secretsStatements = createSecretsManagerPolicyStatements({
      secretArns,
      allowUpdate: false, // Read-only access
    });
    secretsStatements.forEach((statement) => role.addToPolicy(statement));

    // Add CloudWatch Logs permissions with least privilege
    role.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'logs:CreateLogGroup',
          'logs:CreateLogStream',
          'logs:PutLogEvents',
          'logs:DescribeLogStreams',
        ],
        resources: [
          `arn:aws:logs:${cdk.Stack.of(this).region}:${cdk.Stack.of(this).account}:log-group:/aws/ec2/librechat:*`,
          `arn:aws:logs:${cdk.Stack.of(this).region}:${cdk.Stack.of(this).account}:log-group:/aws/ssm/*`,
        ],
      })
    );

    return role;
  }

  private createInstance(props: EC2DeploymentProps, role: iam.Role): ec2.Instance {
    // Get latest Amazon Linux 2023 AMI
    const ami = ec2.MachineImage.latestAmazonLinux2023({
      cpuType: ec2.AmazonLinuxCpuType.X86_64,
    });

    // Create user data script
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      // Update system
      'dnf update -y',
      'dnf install -y docker git htop amazon-cloudwatch-agent postgresql15 python3-pip jq',

      // Install Docker Compose v2 (plugin version)
      'mkdir -p /usr/local/lib/docker/cli-plugins',
      'curl -SL "https://github.com/docker/compose/releases/download/v2.29.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/lib/docker/cli-plugins/docker-compose',
      'chmod +x /usr/local/lib/docker/cli-plugins/docker-compose',
      
      // Also install standalone for compatibility
      'curl -SL "https://github.com/docker/compose/releases/download/v2.29.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose',
      'chmod +x /usr/local/bin/docker-compose',

      // Start Docker and ensure it's ready
      'systemctl start docker',
      'systemctl enable docker',
      'usermod -a -G docker ec2-user',
      
      // Wait for Docker daemon to be ready
      'echo "Waiting for Docker daemon to be ready..." >> /var/log/cloud-init-output.log',
      'for i in {1..30}; do docker info >/dev/null 2>&1 && break || sleep 2; done',
      'docker info >> /var/log/cloud-init-output.log',

      // Clone LibreChat repository for proper setup
      'echo "Cloning LibreChat repository..." >> /var/log/cloud-init-output.log',
      'cd /opt',
      'git clone --depth 1 https://github.com/danny-avila/LibreChat.git librechat',
      'cd /opt/librechat',
      'export LIBRECHAT_DIR=/opt/librechat',  // Set working directory as environment variable
      
      // Create required directories for container volumes with proper permissions
      'mkdir -p logs images uploads meili_data mongodb_data data-node',
      'chmod 755 logs images uploads meili_data mongodb_data data-node',
      'chown -R 1000:1000 logs uploads images',  // UID 1000 for node user in container
      'chown -R 999:999 mongodb_data data-node',    // MongoDB container user

      // Download RDS certificate for SSL connection
      `wget https://truststore.pki.rds.amazonaws.com/${cdk.Stack.of(this).region}/${cdk.Stack.of(this).region}-bundle.pem -O /opt/librechat/rds-ca-2019-root.pem`,

      // Create secure credential retrieval script
      'cat > /opt/librechat/get-credentials.sh << \'SCRIPT_EOF\'',
      '#!/bin/bash',
      'set -e',
      '',
      '# Function to get secret value',
      'get_secret() {',
      '  local secret_id=$1',
      '  local region=$2',
      '  aws secretsmanager get-secret-value --region "$region" --secret-id "$secret_id" --query SecretString --output text',
      '}',
      '',
      '# Export credentials as environment variables',
      `APP_SECRETS=$(get_secret "${props.appSecrets.secretArn}" "${cdk.Stack.of(this).region}")`,
      'export JWT_SECRET=$(echo "$APP_SECRETS" | jq -r .jwt_secret)',
      'export CREDS_KEY=$(echo "$APP_SECRETS" | jq -r .creds_key)',
      'export CREDS_IV=$(echo "$APP_SECRETS" | jq -r .creds_iv)',
      '',
      props.database.secrets['postgres']
        ? [
            '# Wait for RDS credentials to be available',
            'while true; do',
            `  DB_SECRETS=$(get_secret "${props.database.secrets['postgres'].secretArn}" "${cdk.Stack.of(this).region}")`,
            '  if echo "$DB_SECRETS" | jq -e .password > /dev/null 2>&1; then',
            '    export DB_USER=$(echo "$DB_SECRETS" | jq -r .username)',
            '    export DB_PASSWORD=$(echo "$DB_SECRETS" | jq -r .password)',
            '    break',
            '  fi',
            '  echo "Waiting for RDS credentials..."',
            '  sleep 10',
            'done',
          ].join('\n')
        : '# No PostgreSQL configured',
      '',
      props.database.secrets['documentdb']
        ? [
            `DOCDB_SECRETS=$(get_secret "${props.database.secrets['documentdb'].secretArn}" "${cdk.Stack.of(this).region}")`,
            'export DOCDB_USER=$(echo "$DOCDB_SECRETS" | jq -r .username)',
            'export DOCDB_PASSWORD=$(echo "$DOCDB_SECRETS" | jq -r .password)',
          ].join('\n')
        : '# No DocumentDB configured',
      'SCRIPT_EOF',
      'chmod +x /opt/librechat/get-credentials.sh',
      '',
      '# Source credentials',
      'source /opt/librechat/get-credentials.sh',
      
      // Create environment file with database credentials inline
      'cd /opt/librechat',  // Ensure we're in the right directory
      'echo "HOST=0.0.0.0" > /opt/librechat/.env',
      'echo "PORT=3080" >> /opt/librechat/.env',
      `echo "DOMAIN_SERVER=${props.domainConfig?.domainName || this.loadBalancer.loadBalancerDnsName}" >> /opt/librechat/.env`,
      `echo "DOMAIN_CLIENT=${props.domainConfig?.domainName || this.loadBalancer.loadBalancerDnsName}" >> /opt/librechat/.env`,
      'echo "" >> /opt/librechat/.env',
      'echo "# Database" >> /opt/librechat/.env',
      // PostgreSQL configuration - provide defaults when not provisioned
      ...(props.database.endpoints && props.database.endpoints['postgres'] 
        ? [
            // Use actual PostgreSQL database when provisioned
            `echo "DATABASE_URL=postgresql://\$DB_USER:\$(python3 -c "import sys, urllib.parse; print(urllib.parse.quote('\$DB_PASSWORD', safe=''))")@${props.database.endpoints['postgres']}:5432/librechat?sslmode=require&sslrootcert=/opt/librechat/rds-ca-2019-root.pem" >> /opt/librechat/.env`,
            'echo "POSTGRES_DB=librechat" >> /opt/librechat/.env',
            'echo "POSTGRES_USER=$DB_USER" >> /opt/librechat/.env',
            'echo "POSTGRES_PASSWORD=$DB_PASSWORD" >> /opt/librechat/.env',
            `echo "DB_HOST=${props.database.endpoints['postgres']}" >> /opt/librechat/.env`,
            'echo "DB_PORT=5432" >> /opt/librechat/.env',
          ]
        : [
            // Provide placeholder values when PostgreSQL not provisioned (RAG disabled)
            'echo "# PostgreSQL not enabled (RAG disabled) - using placeholder values" >> /opt/librechat/.env',
            'echo "DATABASE_URL=" >> /opt/librechat/.env',
            'echo "POSTGRES_DB=" >> /opt/librechat/.env',
            'echo "POSTGRES_USER=" >> /opt/librechat/.env',
            'echo "POSTGRES_PASSWORD=" >> /opt/librechat/.env',
            'echo "DB_HOST=" >> /opt/librechat/.env',
            'echo "DB_PORT=" >> /opt/librechat/.env',
          ]),
      props.database.endpoints['documentdb']
        ? `echo "MONGO_URI=mongodb://\$DOCDB_USER:\$DOCDB_PASSWORD@${props.database.endpoints['documentdb']}:27017/LibreChat?replicaSet=rs0&tls=true&tlsCAFile=/opt/librechat/rds-ca-2019-root.pem&retryWrites=false" >> /opt/librechat/.env`
        : 'echo "MONGO_URI=mongodb://mongodb:27017/LibreChat" >> /opt/librechat/.env',
      'echo "" >> /opt/librechat/.env',
      'echo "# AWS" >> /opt/librechat/.env',
      `echo "AWS_REGION=${cdk.Stack.of(this).region}" >> /opt/librechat/.env`,
      `echo "BEDROCK_AWS_REGION=${cdk.Stack.of(this).region}" >> /opt/librechat/.env`,
      'echo "ENDPOINTS=bedrock" >> /opt/librechat/.env',
      'echo "" >> /opt/librechat/.env',
      'echo "# S3" >> /opt/librechat/.env',
      'echo "S3_PROVIDER=s3" >> /opt/librechat/.env',
      `echo "S3_BUCKET=${props.storage.s3Bucket.bucketName}" >> /opt/librechat/.env`,
      `echo "S3_REGION=${cdk.Stack.of(this).region}" >> /opt/librechat/.env`,
      'echo "" >> /opt/librechat/.env',
      'echo "# Security" >> /opt/librechat/.env',
      'echo "JWT_SECRET=$JWT_SECRET" >> /opt/librechat/.env',
      'echo "JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET:-$(openssl rand -hex 32)}" >> /opt/librechat/.env',
      'echo "CREDS_KEY=$CREDS_KEY" >> /opt/librechat/.env',
      'echo "CREDS_IV=$CREDS_IV" >> /opt/librechat/.env',
      'echo "" >> /opt/librechat/.env',
      'echo "# Features" >> /opt/librechat/.env',
      `echo "ALLOW_REGISTRATION=${props.environment === 'production' ? 'false' : 'true'}" >> /opt/librechat/.env`,
      'echo "ALLOW_SOCIAL_LOGIN=false" >> /opt/librechat/.env',
      'echo "LIMIT_CONCURRENT_MESSAGES=true" >> /opt/librechat/.env',
      'echo "LIMIT_MESSAGE_IP=true" >> /opt/librechat/.env',
      'echo "LIMIT_MESSAGE_USER=true" >> /opt/librechat/.env',
      'echo "" >> /opt/librechat/.env',
      'echo "# RAG Configuration" >> /opt/librechat/.env',
      `echo "RAG_ENABLED=${props.enableRag}" >> /opt/librechat/.env`,
      'echo "RAG_API_URL=http://rag-api:8000" >> /opt/librechat/.env',
      'echo "EMBEDDINGS_PROVIDER=bedrock" >> /opt/librechat/.env',
      'echo "EMBEDDINGS_MODEL=amazon.titan-embed-text-v2:0" >> /opt/librechat/.env',
      'echo "CHUNK_SIZE=1500" >> /opt/librechat/.env',
      'echo "CHUNK_OVERLAP=200" >> /opt/librechat/.env',
      'echo "RAG_TOP_K_RESULTS=5" >> /opt/librechat/.env',
      'echo "RAG_SIMILARITY_THRESHOLD=0.7" >> /opt/librechat/.env',
      'echo "VECTOR_DB_TYPE=pgvector" >> /opt/librechat/.env',
      'echo "COLLECTION_NAME=librechat_docs" >> /opt/librechat/.env',
      'echo "RAG_USE_FULL_CONTEXT=false" >> /opt/librechat/.env',
      'echo "BEDROCK_AWS_DEFAULT_REGION=${cdk.Stack.of(this).region}" >> /opt/librechat/.env',
      'echo "" >> /opt/librechat/.env',
      'echo "# Meilisearch" >> /opt/librechat/.env',
      `echo "SEARCH_ENABLED=${props.enableMeilisearch}" >> /opt/librechat/.env`,
      'echo "MEILI_HOST=http://meilisearch:7700" >> /opt/librechat/.env',
      'echo "MEILI_MASTER_KEY=$(openssl rand -hex 32)" >> /opt/librechat/.env',
      'echo "" >> /opt/librechat/.env',
      'echo "# Web Search (Optional - configure API keys in AWS Secrets Manager)" >> /opt/librechat/.env',
      'echo "SEARCH=true" >> /opt/librechat/.env',
      '# Web search API keys from app secrets',
      'GOOGLE_API_KEY=$(echo "$APP_SECRETS" | jq -r ".google_search_api_key // empty" || echo "")',
      'echo "GOOGLE_API_KEY=$GOOGLE_API_KEY" >> /opt/librechat/.env',
      'GOOGLE_CSE_ID=$(echo "$APP_SECRETS" | jq -r ".google_cse_id // empty" || echo "")',
      'echo "GOOGLE_CSE_ID=$GOOGLE_CSE_ID" >> /opt/librechat/.env',
      'BING_API_KEY=$(echo "$APP_SECRETS" | jq -r ".bing_api_key // empty" || echo "")',
      'echo "BING_API_KEY=$BING_API_KEY" >> /opt/librechat/.env',
      
      // Create docker-compose.yml with proper configuration
      'cat > /opt/librechat/docker-compose.yml << EOF',
      'version: "3.8"',
      '',
      'services:',
      '  api:',
      '    image: ghcr.io/danny-avila/librechat-dev-api:latest',
      '    container_name: librechat-api',
      '    restart: unless-stopped',
      '    env_file: .env',
      '    ports:',
      '      - "3080:3080"',
      '    volumes:',
      '      - ./librechat.yaml:/app/librechat.yaml',
      '      - ./logs:/app/api/logs',
      '      - ./images:/app/client/public/images',
      '      - ./uploads:/app/client/public/uploads',
      '    environment:',
      '      - NODE_ENV=production',
      '      - HOST=0.0.0.0',
      '      - PORT=3080',
      '      - MONGO_URI=${MONGO_URI:-mongodb://mongodb:27017/LibreChat}',
      '    healthcheck:',
      '      test: ["CMD", "curl", "-f", "http://localhost:3080/health"]',
      '      interval: 30s',
      '      timeout: 10s',
      '      retries: 5',
      '      start_period: 60s',
      '    depends_on:',
      // Only depend on mongodb if it's not using DocumentDB
      ...(props.database.endpoints['documentdb']
        ? []
        : [
            '      mongodb:',
            '        condition: service_started',
          ]),
      // Conditional RAG API dependency
      ...(props.database.endpoints && props.database.endpoints['postgres']
        ? [
            '      rag-api:',
            '        condition: service_healthy',
          ]
        : []),
      // Conditional Meilisearch dependency
      ...(props.enableMeilisearch
        ? [
            '      meilisearch:',
            '        condition: service_started',
          ]
        : []),
      '',
      '',
      // Only include MongoDB container if DocumentDB is NOT provisioned
      ...(props.database.endpoints['documentdb']
        ? [
            '  # Using AWS DocumentDB - no local MongoDB container needed',
            '',
          ]
        : [
            '  mongodb:',
            '    image: mongo:7',
            '    container_name: mongodb',
            '    restart: unless-stopped',
            '    environment:',
            '      - MONGO_INITDB_DATABASE=LibreChat',
            '    volumes:',
            '      - ./data-node:/data/db',
            '    command: mongod --noauth',
            '    healthcheck:',
            '      test: ["CMD", "mongosh", "--eval", "db.adminCommand(\'ping\')" ]',
            '      interval: 10s',
            '      timeout: 5s',
            '      retries: 5',
            '      start_period: 30s',
            '',
          ]),
      // Conditional RAG API service - only when PostgreSQL is available
      ...(props.database.endpoints && props.database.endpoints['postgres']
        ? [
            '  rag-api:',
            '    image: ghcr.io/danny-avila/librechat-rag-api-dev:latest',
            '    container_name: rag-api',
            '    restart: unless-stopped',
            '    env_file: .env',
            '    environment:',
            `      - DB_HOST=${props.database.endpoints['postgres']}`,
            '      - DB_PORT=5432',
            '      - POSTGRES_DB=librechat',
            '      - POSTGRES_USER=$DB_USER',
            '      - POSTGRES_PASSWORD=$DB_PASSWORD',
            `      - EMBEDDINGS_PROVIDER=bedrock`,
            '      - EMBEDDINGS_MODEL=amazon.titan-embed-text-v2:0',
            `      - BEDROCK_AWS_REGION=${cdk.Stack.of(this).region}`,
            '      - VECTOR_DB_TYPE=pgvector',
            '      - COLLECTION_NAME=librechat_docs',
            '      - CHUNK_SIZE=1500',
            '      - CHUNK_OVERLAP=200',
            '    ports:',
            '      - "8000:8000"',
            '    healthcheck:',
            '      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]',
            '      interval: 30s',
            '      timeout: 10s',
            '      retries: 5',
            '      start_period: 60s',
            '',
          ]
        : [
            '  # RAG API service disabled - PostgreSQL not available (enableRag=false)',
            '',
          ]),
      props.enableMeilisearch
        ? `  meilisearch:\n    image: getmeili/meilisearch:v1.6\n    container_name: meilisearch\n    restart: unless-stopped\n    env_file: .env\n    volumes:\n      - ./meili_data:/meili_data\n    healthcheck:\n      test: ["CMD", "curl", "-f", "http://localhost:7700/health"]\n      interval: 30s\n      timeout: 10s\n      retries: 3\n      start_period: 30s`
        : '',
      'EOF',

      // Create LibreChat configuration
      'cat > /opt/librechat/librechat.yaml << EOL',
      'version: 1.2.1',
      '',
      'cache: true',
      '',
      'endpoints:',
      '  bedrock:',
      '    enabled: true',
      '    titleModel: "anthropic.claude-3-5-sonnet-20241022-v2:0"',
      '    defaultModel: "anthropic.claude-3-5-sonnet-20241022-v2:0"',
      '    streamRate: 35',
      '    availableRegions:',
      `      - "${cdk.Stack.of(this).region}"`,
      '    models:',
      '      default:',
      '        # Claude 4 Models',
      '        - "anthropic.claude-sonnet-4-20250514-v1:0"',
      '        - "anthropic.claude-opus-4-1-20250805-v1:0"',
      '        - "anthropic.claude-opus-4-20250514-v1:0"',
      '        # Claude 3.x Models',
      '        - "anthropic.claude-3-7-sonnet-20250219-v1:0"',
      '        - "anthropic.claude-3-5-sonnet-20241022-v2:0"',
      '        - "anthropic.claude-3-5-sonnet-20240620-v1:0"',
      '        - "anthropic.claude-3-5-haiku-20241022-v1:0"',
      '        - "anthropic.claude-3-opus-20240229-v1:0"',
      '        - "anthropic.claude-3-sonnet-20240229-v1:0"',
      '        - "anthropic.claude-3-haiku-20240307-v1:0"',
      '        - "anthropic.claude-instant-v1"',
      '        # Meta Llama Models',
      '        - "meta.llama3-1-70b-instruct-v1:0"',
      '        - "meta.llama3-1-8b-instruct-v1:0"',
      '        - "meta.llama3-70b-instruct-v1:0"',
      '        - "meta.llama3-8b-instruct-v1:0"',
      '        # Mistral Models',
      '        - "mistral.mistral-large-2407-v1:0"',
      '        - "mistral.mistral-large-2402-v1:0"',
      '        - "mistral.mixtral-8x7b-instruct-v0:1"',
      '        - "mistral.mistral-7b-instruct-v0:2"',
      '        # Amazon Titan Models',
      '        - "amazon.titan-text-premier-v1:0"',
      '        - "amazon.titan-text-express-v1"',
      '        - "amazon.titan-text-lite-v1"',
      '        # Cohere Models',
      '        - "cohere.command-r-plus-v1:0"',
      '        - "cohere.command-r-v1:0"',
      '        # AI21 Models',
      '        - "ai21.j2-ultra-v1"',
      '        - "ai21.j2-mid-v1"',
      '',
      'tools:',
      '  - google_search:',
      '      enabled: true',
      '  - bing_search:',
      '      enabled: true',
      '  - web_browser:',
      '      enabled: true',
      '  - calculator:',
      '      enabled: true',
      '',
      'fileConfig:',
      '  endpoints:',
      '    default:',
      '      fileLimit: 100',
      '      fileSizeLimit: 200',
      '      totalSizeLimit: 1000',
      '      supportedMimeTypes:',
      '        - "application/pdf"',
      '        - "text/plain"',
      '        - "text/csv"',
      '        - "text/html"',
      '        - "text/markdown"',
      '        - "application/rtf"',
      '        - "application/vnd.openxmlformats-officedocument.wordprocessingml.document"',
      '        - "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"',
      '        - "application/vnd.openxmlformats-officedocument.presentationml.presentation"',
      '        - "application/msword"',
      '        - "application/vnd.ms-excel"',
      '        - "application/vnd.ms-powerpoint"',
      '        - "image/jpeg"',
      '        - "image/png"',
      '        - "image/gif"',
      '        - "image/webp"',
      '        - "application/json"',
      '        - "application/xml"',
      '',
      // Conditional RAG configuration
      ...(props.database.endpoints && props.database.endpoints['postgres']
        ? [
            'ragConfig:',
            '  enabled: true',
            '  api:',
            '    url: "http://rag-api:8000"',
            '  embedding:',
            '    provider: "bedrock"',
            '    model: "amazon.titan-embed-text-v2:0"',
            '  chunking:',
            '    strategy: "semantic"',
            '    size: 1500',
            '    overlap: 200',
            '  retrieval:',
            '    topK: 5',
            '    similarityThreshold: 0.7',
            '',
          ]
        : [
            '# RAG configuration disabled - PostgreSQL not available (enableRag=false)',
            '',
          ]),
      'registration:',
      `  enabled: ${props.environment !== 'production'}`,
      '  socialLogins:',
      '    - "google"',
      '    - "github"',
      '',
      'interface:',
      '  messageLimit: 40',
      '  maxContextTokens: 8192',
      '  showModelTokenCounts: true',
      '  endpointsMenu: true',
      'EOL',

      // Install CloudWatch agent
      'wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm',
      'rpm -U ./amazon-cloudwatch-agent.rpm',

      // Configure CloudWatch agent
      'cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOL',
      '{',
      '  "agent": {',
      '    "metrics_collection_interval": 60,',
      '    "run_as_user": "cwagent"',
      '  },',
      '  "logs": {',
      '    "logs_collected": {',
      '      "files": {',
      '        "collect_list": [',
      '          {',
      '            "file_path": "/opt/librechat/logs/**/*.log",',
      '            "log_group_name": "/aws/ec2/librechat",',
      '            "log_stream_name": "{instance_id}",',
      '            "retention_in_days": 30',
      '          }',
      '        ]',
      '      }',
      '    }',
      '  },',
      '  "metrics": {',
      '    "namespace": "LibreChat",',
      '    "metrics_collected": {',
      '      "cpu": {',
      '        "measurement": [',
      '          {',
      '            "name": "cpu_usage_idle",',
      '            "rename": "CPU_USAGE_IDLE",',
      '            "unit": "Percent"',
      '          },',
      '          {',
      '            "name": "cpu_usage_iowait",',
      '            "rename": "CPU_USAGE_IOWAIT",',
      '            "unit": "Percent"',
      '          }',
      '        ],',
      '        "totalcpu": false',
      '      },',
      '      "disk": {',
      '        "measurement": [',
      '          {',
      '            "name": "used_percent",',
      '            "rename": "DISK_USED_PERCENT",',
      '            "unit": "Percent"',
      '          }',
      '        ],',
      '        "resources": [',
      '          "*"',
      '        ]',
      '      },',
      '      "mem": {',
      '        "measurement": [',
      '          {',
      '            "name": "mem_used_percent",',
      '            "rename": "MEM_USED_PERCENT",',
      '            "unit": "Percent"',
      '          }',
      '        ]',
      '      }',
      '    }',
      '  }',
      '}',
      'EOL',

      // Start CloudWatch agent
      '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json',

      // Start Docker containers
      'cd /opt/librechat',
      // Debug: Log configuration
      'echo "DEBUG: Starting Docker Compose deployment" >> /var/log/cloud-init-output.log',
      'echo "DEBUG: Docker version:" >> /var/log/cloud-init-output.log',
      'docker --version >> /var/log/cloud-init-output.log',
      'echo "DEBUG: Docker Compose version:" >> /var/log/cloud-init-output.log',
      'docker compose version >> /var/log/cloud-init-output.log 2>&1 || /usr/local/bin/docker-compose version >> /var/log/cloud-init-output.log',
      'echo "DEBUG: Checking configuration files:" >> /var/log/cloud-init-output.log',
      'ls -la /opt/librechat/ >> /var/log/cloud-init-output.log',
      'echo "DEBUG: .env file preview:" >> /var/log/cloud-init-output.log',
      'head -20 /opt/librechat/.env | sed "s/PASSWORD=.*/PASSWORD=***/" >> /var/log/cloud-init-output.log',
      
      // Pull images first (with retry logic)
      'echo "Pulling Docker images..." >> /var/log/cloud-init-output.log',
      'for i in 1 2 3; do',
      '  if docker compose -f /opt/librechat/docker-compose.yml pull 2>/dev/null; then',
      '    echo "Images pulled successfully using docker compose" >> /var/log/cloud-init-output.log',
      '    break',
      '  elif /usr/local/bin/docker-compose -f /opt/librechat/docker-compose.yml pull; then',
      '    echo "Images pulled successfully using docker-compose standalone" >> /var/log/cloud-init-output.log',
      '    break',
      '  else',
      '    echo "Pull attempt $i failed, retrying..." >> /var/log/cloud-init-output.log',
      '    sleep 10',
      '  fi',
      'done',
      
      // Start containers with better error handling
      'echo "Starting Docker containers..." >> /var/log/cloud-init-output.log',
      'if docker compose -f /opt/librechat/docker-compose.yml up -d 2>/dev/null; then',
      '  echo "Containers started with docker compose" >> /var/log/cloud-init-output.log',
      'else',
      '  echo "Trying docker-compose standalone..." >> /var/log/cloud-init-output.log',
      '  /usr/local/bin/docker-compose -f /opt/librechat/docker-compose.yml up -d',
      'fi',
      
      // Wait for containers to fully start
      'sleep 60',
      
      // Comprehensive container status check
      'echo "Container status:" >> /var/log/cloud-init-output.log',
      'docker ps -a >> /var/log/cloud-init-output.log',
      'echo "Docker Compose status:" >> /var/log/cloud-init-output.log',
      '/usr/local/bin/docker-compose -f /opt/librechat/docker-compose.yml ps >> /var/log/cloud-init-output.log',
      
      // Verify MongoDB is ready before checking API (only if using local MongoDB)
      ...(props.database.endpoints['documentdb']
        ? [
            'echo "Using AWS DocumentDB - no local MongoDB to wait for" >> /var/log/cloud-init-output.log',
          ]
        : [
            'echo "Waiting for MongoDB to be ready..." >> /var/log/cloud-init-output.log',
            'for i in {1..30}; do',
            '  if docker exec mongodb mongosh --eval "db.adminCommand(\'ping\')" >/dev/null 2>&1; then',
            '    echo "MongoDB is ready" >> /var/log/cloud-init-output.log',
            '    break',
            '  fi',
            '  sleep 2',
            'done',
          ]),
      
      // Check logs for each service
      ...(props.database.endpoints['documentdb']
        ? []
        : [
            'echo "MongoDB logs:" >> /var/log/cloud-init-output.log',
            'docker logs mongodb 2>&1 | tail -20 >> /var/log/cloud-init-output.log || true',
          ]),
      'echo "LibreChat API logs:" >> /var/log/cloud-init-output.log',
      'docker logs librechat-api 2>&1 | tail -50 >> /var/log/cloud-init-output.log || true',

      // Create systemd service
      'cat > /etc/systemd/system/librechat.service << EOL',
      '[Unit]',
      'Description=LibreChat Docker Compose Application',
      'Requires=docker.service',
      'After=docker.service network-online.target',
      'Wants=network-online.target',
      '',
      '[Service]',
      'Type=oneshot',
      'RemainAfterExit=yes',
      'User=root',
      'WorkingDirectory=/opt/librechat',
      'EnvironmentFile=/opt/librechat/.env',
      'ExecStartPre=-/usr/bin/docker compose -f /opt/librechat/docker-compose.yml down',
      'ExecStartPre=-/usr/local/bin/docker-compose -f /opt/librechat/docker-compose.yml down',
      'ExecStart=/bin/bash -c "docker compose -f /opt/librechat/docker-compose.yml up -d || /usr/local/bin/docker-compose -f /opt/librechat/docker-compose.yml up -d"',
      'ExecStop=/bin/bash -c "docker compose -f /opt/librechat/docker-compose.yml down || /usr/local/bin/docker-compose -f /opt/librechat/docker-compose.yml down"',
      'ExecReload=/bin/bash -c "docker compose -f /opt/librechat/docker-compose.yml restart || /usr/local/bin/docker-compose -f /opt/librechat/docker-compose.yml restart"',
      'Restart=on-failure',
      'RestartSec=30',
      'TimeoutStartSec=300',
      '',
      '[Install]',
      'WantedBy=multi-user.target',
      'EOL',

      'systemctl daemon-reload',
      'systemctl enable librechat.service',
      'systemctl start librechat.service',

      // Verify containers are running
      'echo "Verifying LibreChat deployment..." >> /var/log/cloud-init-output.log',
      'sleep 30',
      'RETRY_COUNT=0',
      'MAX_RETRIES=10',
      'while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do',
      '  echo "Health check attempt $((RETRY_COUNT + 1))/$MAX_RETRIES..." >> /var/log/cloud-init-output.log',
      '  ',
      '  # Check if containers are running',
      '  # Determine expected containers based on configuration',
      ...(props.database.endpoints['documentdb']
        ? [
            '  # Using DocumentDB - expect only librechat-api (and optionally rag-api)',
            '  EXPECTED_PATTERN="librechat-api"',
          ]
        : [
            '  # Using local MongoDB - expect both librechat-api and mongodb',
            '  EXPECTED_PATTERN="librechat-api|mongodb"',
          ]),
      '  RUNNING_CONTAINERS=$(docker ps --format "{{.Names}}" | grep -E "$EXPECTED_PATTERN" | wc -l)',
      '  echo "Running containers: $RUNNING_CONTAINERS" >> /var/log/cloud-init-output.log',
      '  ',
      '  # Try health check',
      '  if curl -f -s -o /dev/null -w "%{http_code}" http://localhost:3080/health | grep -q "200"; then',
      '    echo "SUCCESS: LibreChat is running and healthy!" >> /var/log/cloud-init-output.log',
      '    curl -I http://localhost:3080 >> /var/log/cloud-init-output.log',
      '    break',
      '  else',
      '    echo "LibreChat not ready yet (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)" >> /var/log/cloud-init-output.log',
      '    ',
      '    # Debug information',
      '    echo "Container status:" >> /var/log/cloud-init-output.log',
      '    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" >> /var/log/cloud-init-output.log',
      '    ',
      '    # Check specific container logs if they exist',
      '    if docker ps -a --format "{{.Names}}" | grep -q "librechat-api"; then',
      '      echo "LibreChat API recent logs:" >> /var/log/cloud-init-output.log',
      '      docker logs librechat-api 2>&1 | tail -30 >> /var/log/cloud-init-output.log || true',
      '    fi',
      '    ',
      '    # Restart containers if they are not running after several attempts',
      '    if [ $RETRY_COUNT -eq 5 ]; then',
      '      echo "Attempting container restart..." >> /var/log/cloud-init-output.log',
      '      systemctl restart librechat.service',
      '      sleep 30',
      '    fi',
      '    ',
      '    sleep 30',
      '    RETRY_COUNT=$((RETRY_COUNT + 1))',
      '  fi',
      'done',
      '',
      'if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then',
      '  echo "WARNING: LibreChat health check failed after $MAX_RETRIES attempts" >> /var/log/cloud-init-output.log',
      '  echo "Final container status:" >> /var/log/cloud-init-output.log',
      '  docker ps -a >> /var/log/cloud-init-output.log',
      'fi',
      
      // Clean up - Note: credentials are now only in environment variables
      'unset DB_USER DB_PASSWORD DOCDB_USER DOCDB_PASSWORD JWT_SECRET CREDS_KEY CREDS_IV',

      // Signal will be handled by cfn-init
      'echo "User data script completed successfully" >> /var/log/cloud-init-output.log'
    );

    // Look up the key pair
    const keyPair = ec2.KeyPair.fromKeyPairName(this, 'ImportedKeyPair', props.keyPairName);
    
    const instance = new ec2.Instance(this, 'Instance', {
      vpc: props.vpc,
      instanceType: new ec2.InstanceType(props.instanceType),
      machineImage: ami,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
      securityGroup: this.securityGroup,
      role: role,
      keyPair: keyPair,  // Use keyPair instead of deprecated keyName
      userData: userData,
      userDataCausesReplacement: false, // Prevent instance replacement on user data changes
      blockDevices: [
        {
          deviceName: '/dev/xvda',
          volume: ec2.BlockDeviceVolume.ebs(100, {
            volumeType: ec2.EbsDeviceVolumeType.GP3,
            encrypted: true,
            deleteOnTermination: props.environment !== 'production', // Retain volumes in production
          }),
        },
      ],
    });

    // Add tags
    cdk.Tags.of(instance).add('Name', `LibreChat-${props.environment}`);
    cdk.Tags.of(instance).add('Environment', props.environment);
    cdk.Tags.of(instance).add('Application', 'LibreChat');

    return instance;
  }

  private createLoadBalancer(
    props: EC2DeploymentProps,
    securityGroup: ec2.SecurityGroup
  ): elbv2.ApplicationLoadBalancer {
    const alb = new elbv2.ApplicationLoadBalancer(this, 'LoadBalancer', {
      vpc: props.vpc,
      internetFacing: true,
      securityGroup: securityGroup,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
      deletionProtection: props.environment === 'production',
    });

    // Apply removal policy
    alb.applyRemovalPolicy(
      props.environment === 'production' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY
    );

    // Add tags
    cdk.Tags.of(alb).add('Name', `LibreChat-ALB-${props.environment}`);

    return alb;
  }

  private createTargetGroup(props: EC2DeploymentProps): elbv2.ApplicationTargetGroup {
    return new elbv2.ApplicationTargetGroup(this, 'TargetGroup', {
      vpc: props.vpc,
      port: 3080,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.INSTANCE,
      healthCheck: {
        enabled: true,
        path: '/health',
        protocol: elbv2.Protocol.HTTP,
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(10),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
        healthyHttpCodes: '200-299',
      },
      deregistrationDelay: cdk.Duration.seconds(30),
      stickinessCookieDuration: cdk.Duration.hours(1),
    });
  }

  private configureListener(
    props: EC2DeploymentProps,
    targetGroup: elbv2.ApplicationTargetGroup
  ): void {
    if (props.domainConfig?.certificateArn) {
      // HTTPS listener
      this.loadBalancer.addListener('HTTPSListener', {
        port: 443,
        protocol: elbv2.ApplicationProtocol.HTTPS,
        certificates: [
          {
            certificateArn: props.domainConfig.certificateArn,
          },
        ],
        defaultTargetGroups: [targetGroup],
      });

      // HTTP to HTTPS redirect
      this.loadBalancer.addListener('HTTPListener', {
        port: 80,
        protocol: elbv2.ApplicationProtocol.HTTP,
        defaultAction: elbv2.ListenerAction.redirect({
          port: '443',
          protocol: 'HTTPS',
          permanent: true,
        }),
      });
    } else {
      // HTTP listener only
      this.loadBalancer.addListener('HTTPListener', {
        port: 80,
        protocol: elbv2.ApplicationProtocol.HTTP,
        defaultTargetGroups: [targetGroup],
      });
    }
  }

  private configureDomain(props: EC2DeploymentProps): void {
    if (!props.domainConfig?.hostedZoneId || !props.domainConfig?.domainName) {
      return;
    }

    const hostedZone = route53.HostedZone.fromHostedZoneAttributes(this, 'HostedZone', {
      hostedZoneId: props.domainConfig.hostedZoneId,
      zoneName: props.domainConfig.domainName,
    });

    new route53.ARecord(this, 'DomainRecord', {
      zone: hostedZone,
      recordName: props.domainConfig.domainName,
      target: route53.RecordTarget.fromAlias(
        new route53_targets.LoadBalancerTarget(this.loadBalancer)
      ),
      ttl: cdk.Duration.minutes(5),
    });
  }

  private createDashboard(props: EC2DeploymentProps): void {
    const dashboard = new cloudwatch.Dashboard(this, 'Dashboard', {
      dashboardName: `LibreChat-${props.environment}`,
      defaultInterval: cdk.Duration.hours(1),
    });

    // CPU utilization
    const cpuMetric = new cloudwatch.Metric({
      namespace: 'AWS/EC2',
      metricName: 'CPUUtilization',
      dimensionsMap: {
        InstanceId: this.instance.instanceId,
      },
      statistic: 'Average',
      period: cdk.Duration.minutes(5),
    });

    // Network metrics
    const networkInMetric = new cloudwatch.Metric({
      namespace: 'AWS/EC2',
      metricName: 'NetworkIn',
      dimensionsMap: {
        InstanceId: this.instance.instanceId,
      },
      statistic: 'Sum',
      period: cdk.Duration.minutes(5),
    });

    const networkOutMetric = new cloudwatch.Metric({
      namespace: 'AWS/EC2',
      metricName: 'NetworkOut',
      dimensionsMap: {
        InstanceId: this.instance.instanceId,
      },
      statistic: 'Sum',
      period: cdk.Duration.minutes(5),
    });

    // Target health
    const healthyTargetsMetric = new cloudwatch.Metric({
      namespace: 'AWS/ApplicationELB',
      metricName: 'HealthyHostCount',
      dimensionsMap: {
        LoadBalancer: this.loadBalancer.loadBalancerFullName,
        TargetGroup: this.targetGroup.targetGroupFullName,
      },
      statistic: 'Average',
      period: cdk.Duration.minutes(1),
    });

    // Request count
    const requestCountMetric = new cloudwatch.Metric({
      namespace: 'AWS/ApplicationELB',
      metricName: 'RequestCount',
      dimensionsMap: {
        LoadBalancer: this.loadBalancer.loadBalancerFullName,
      },
      statistic: 'Sum',
      period: cdk.Duration.minutes(5),
    });

    // Add widgets to dashboard
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'EC2 CPU Utilization',
        left: [cpuMetric],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Network Traffic',
        left: [networkInMetric],
        right: [networkOutMetric],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Target Health',
        left: [healthyTargetsMetric],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Request Count',
        left: [requestCountMetric],
        width: 12,
        height: 6,
      })
    );
  }
}
