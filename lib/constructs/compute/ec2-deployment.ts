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

      // Install Docker Compose
      'curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose',
      'chmod +x /usr/local/bin/docker-compose',
      'ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose',


      // Start Docker
      'systemctl start docker',
      'systemctl enable docker',
      'usermod -a -G docker ec2-user',

      // Create app directory
      'mkdir -p /opt/librechat',
      'chown -R ec2-user:ec2-user /opt/librechat',
      'cd /opt/librechat',
      
      // Create required directories for container volumes
      'mkdir -p logs uploads meili_data mongodb_data',
      'chown -R ec2-user:ec2-user logs uploads meili_data mongodb_data',

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
      'echo "HOST=0.0.0.0" > .env',
      'echo "PORT=3080" >> .env',
      `echo "DOMAIN_SERVER=${props.domainConfig?.domainName || this.loadBalancer.loadBalancerDnsName}" >> .env`,
      `echo "DOMAIN_CLIENT=${props.domainConfig?.domainName || this.loadBalancer.loadBalancerDnsName}" >> .env`,
      'echo "" >> .env',
      'echo "# Database" >> .env',
      // PostgreSQL configuration - provide defaults when not provisioned
      ...(props.database.endpoints && props.database.endpoints['postgres'] 
        ? [
            // Use actual PostgreSQL database when provisioned
            `echo "DATABASE_URL=postgresql://\$DB_USER:\$(python3 -c "import sys, urllib.parse; print(urllib.parse.quote('\$DB_PASSWORD', safe=''))")@${props.database.endpoints['postgres']}:5432/librechat?sslmode=require&sslrootcert=/opt/librechat/rds-ca-2019-root.pem" >> .env`,
            'echo "POSTGRES_DB=librechat" >> .env',
            'echo "POSTGRES_USER=$DB_USER" >> .env',
            'echo "POSTGRES_PASSWORD=$DB_PASSWORD" >> .env',
            `echo "DB_HOST=${props.database.endpoints['postgres']}" >> .env`,
            'echo "DB_PORT=5432" >> .env',
          ]
        : [
            // Provide placeholder values when PostgreSQL not provisioned (RAG disabled)
            'echo "# PostgreSQL not enabled (RAG disabled) - using placeholder values" >> .env',
            'echo "DATABASE_URL=" >> .env',
            'echo "POSTGRES_DB=" >> .env',
            'echo "POSTGRES_USER=" >> .env',
            'echo "POSTGRES_PASSWORD=" >> .env',
            'echo "DB_HOST=" >> .env',
            'echo "DB_PORT=" >> .env',
          ]),
      props.database.endpoints['documentdb']
        ? `echo "MONGO_URI=mongodb://\$DOCDB_USER:\$DOCDB_PASSWORD@${props.database.endpoints['documentdb']}:27017/LibreChat?replicaSet=rs0&tls=true&tlsCAFile=/opt/librechat/rds-ca-2019-root.pem&retryWrites=false" >> .env`
        : 'echo "MONGO_URI=mongodb://mongodb:27017/LibreChat" >> .env',
      'echo "" >> .env',
      'echo "# AWS" >> .env',
      `echo "AWS_REGION=${cdk.Stack.of(this).region}" >> .env`,
      `echo "BEDROCK_AWS_REGION=${cdk.Stack.of(this).region}" >> .env`,
      'echo "ENDPOINTS=bedrock" >> .env',
      'echo "" >> .env',
      'echo "# S3" >> .env',
      'echo "S3_PROVIDER=s3" >> .env',
      `echo "S3_BUCKET=${props.storage.s3Bucket.bucketName}" >> .env`,
      `echo "S3_REGION=${cdk.Stack.of(this).region}" >> .env`,
      'echo "" >> .env',
      'echo "# Security" >> .env',
      'echo "JWT_SECRET=$JWT_SECRET" >> .env',
      'echo "JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET:-$(openssl rand -hex 32)}" >> .env',
      'echo "CREDS_KEY=$CREDS_KEY" >> .env',
      'echo "CREDS_IV=$CREDS_IV" >> .env',
      'echo "" >> .env',
      'echo "# Features" >> .env',
      `echo "ALLOW_REGISTRATION=${props.environment === 'production' ? 'false' : 'true'}" >> .env`,
      'echo "ALLOW_SOCIAL_LOGIN=false" >> .env',
      'echo "LIMIT_CONCURRENT_MESSAGES=true" >> .env',
      'echo "LIMIT_MESSAGE_IP=true" >> .env',
      'echo "LIMIT_MESSAGE_USER=true" >> .env',
      'echo "" >> .env',
      'echo "# RAG Configuration" >> .env',
      `echo "RAG_ENABLED=${props.enableRag}" >> .env`,
      'echo "RAG_API_URL=http://rag-api:8000" >> .env',
      'echo "EMBEDDINGS_PROVIDER=bedrock" >> .env',
      'echo "EMBEDDINGS_MODEL=amazon.titan-embed-text-v2:0" >> .env',
      'echo "CHUNK_SIZE=1500" >> .env',
      'echo "CHUNK_OVERLAP=200" >> .env',
      'echo "RAG_TOP_K_RESULTS=5" >> .env',
      'echo "RAG_SIMILARITY_THRESHOLD=0.7" >> .env',
      'echo "VECTOR_DB_TYPE=pgvector" >> .env',
      'echo "COLLECTION_NAME=librechat_docs" >> .env',
      'echo "RAG_USE_FULL_CONTEXT=false" >> .env',
      'echo "BEDROCK_AWS_DEFAULT_REGION=${cdk.Stack.of(this).region}" >> .env',
      'echo "" >> .env',
      'echo "# Meilisearch" >> .env',
      `echo "SEARCH_ENABLED=${props.enableMeilisearch}" >> .env`,
      'echo "MEILI_HOST=http://meilisearch:7700" >> .env',
      'MEILI_KEY=$(openssl rand -hex 32)',
      'echo "MEILI_MASTER_KEY=$MEILI_KEY" >> .env',
      'echo "" >> .env',
      'echo "# Web Search (Optional - configure API keys in AWS Secrets Manager)" >> .env',
      'echo "SEARCH=true" >> .env',
      '# Web search API keys from app secrets',
      'GOOGLE_API_KEY=$(echo "$APP_SECRETS" | jq -r ".google_search_api_key // empty" || echo "")',
      'echo "GOOGLE_API_KEY=$GOOGLE_API_KEY" >> .env',
      'GOOGLE_CSE_ID=$(echo "$APP_SECRETS" | jq -r ".google_cse_id // empty" || echo "")',
      'echo "GOOGLE_CSE_ID=$GOOGLE_CSE_ID" >> .env',
      'BING_API_KEY=$(echo "$APP_SECRETS" | jq -r ".bing_api_key // empty" || echo "")',
      'echo "BING_API_KEY=$BING_API_KEY" >> .env',
      
      // Create docker-compose.yml with actual values substituted
      'cat > docker-compose.yml << EOF',
      'version: "3.8"',
      '',
      'services:',
      '  api:',
      '    image: ghcr.io/danny-avila/librechat:latest',
      '    container_name: librechat-api',
      '    restart: unless-stopped',
      '    user: "node"',
      '    env_file: .env',
      '    ports:',
      '      - "3080:3080"',
      '    volumes:',
      '      - ./librechat.yaml:/app/librechat.yaml',
      '      - ./logs:/app/api/logs',
      '      - ./uploads:/app/client/public/uploads',
      '    healthcheck:',
      '      test: ["CMD", "curl", "-f", "http://localhost:3080/health"]',
      '      interval: 30s',
      '      timeout: 10s',
      '      retries: 3',
      '      start_period: 40s',
      '    depends_on:',
      '      mongodb:',
      '        condition: service_started',
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
      '  client:',
      '    image: ghcr.io/danny-avila/librechat:latest',
      '    container_name: librechat-client',
      '    restart: unless-stopped',
      '    user: "node"',
      '    env_file: .env',
      '    ports:',
      '      - "3090:80"',
      '    depends_on:',
      '      - api',
      '',
      '  mongodb:',
      '    image: mongo:latest',
      '    container_name: mongodb',
      '    restart: unless-stopped',
      '    volumes:',
      '      - ./mongodb_data:/data/db',
      '    healthcheck:',
      '      test: ["CMD", "mongosh", "--eval", "db.adminCommand(\'ping\')" ]',
      '      interval: 10s',
      '      timeout: 5s',
      '      retries: 5',
      '      start_period: 20s',
      '',
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
      'cat > librechat.yaml << EOL',
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
      // Debug: Log credentials (without password value) and verify .env file
      'echo "DEBUG: DB_USER=$DB_USER" >> /var/log/cloud-init-output.log',
      'echo "DEBUG: DB_PASS is $([ -n "$DB_PASS" ] && echo "set" || echo "NOT SET")" >> /var/log/cloud-init-output.log',
      'echo "DEBUG: Checking .env file database credentials:" >> /var/log/cloud-init-output.log',
      'grep -E "^(DB_HOST|DB_PORT|POSTGRES_USER|POSTGRES_DB)" .env >> /var/log/cloud-init-output.log',
      'echo "DEBUG: POSTGRES_PASSWORD line exists: $(grep -c "^POSTGRES_PASSWORD=" .env)" >> /var/log/cloud-init-output.log',
      '/usr/local/bin/docker-compose pull',
      // Start with docker-compose using the correct path
      '/usr/local/bin/docker-compose up -d',
      // Wait for containers to start
      'sleep 30',
      // Check container status
      'docker ps -a >> /var/log/cloud-init-output.log',
      'docker logs librechat-api >> /var/log/cloud-init-output.log 2>&1 || true',

      // Create systemd service
      'cat > /etc/systemd/system/librechat.service << EOL',
      '[Unit]',
      'Description=LibreChat Docker Compose Application',
      'Requires=docker.service',
      'After=docker.service',
      '',
      '[Service]',
      'Type=simple',
      'User=ec2-user',
      'WorkingDirectory=/opt/librechat',
      'ExecStart=/usr/local/bin/docker-compose up',
      'ExecStop=/usr/local/bin/docker-compose down',
      'Restart=always',
      'RestartSec=10',
      '',
      '[Install]',
      'WantedBy=multi-user.target',
      'EOL',

      'systemctl daemon-reload',
      'systemctl enable librechat.service',
      'systemctl start librechat.service',

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
