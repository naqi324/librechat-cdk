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
import { buildDocumentDBConnectionTemplate } from '../../utils/connection-strings';
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
      'dnf install -y docker git htop amazon-cloudwatch-agent postgresql15 python3-pip',

      // Install Docker Compose
      'curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose',
      'chmod +x /usr/local/bin/docker-compose',

      // Start Docker
      'systemctl start docker',
      'systemctl enable docker',
      'usermod -a -G docker ec2-user',

      // Create app directory
      'mkdir -p /opt/librechat',
      'cd /opt/librechat',
      
      // Create required directories for container volumes
      'mkdir -p logs uploads',
      'chmod 777 logs uploads',

      // Download RDS certificate for SSL connection
      'wget https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -O rds-ca-2019-root.pem',

      // Get secrets - wait for RDS secret to be populated
      `aws secretsmanager get-secret-value --region ${cdk.Stack.of(this).region} --secret-id ${props.appSecrets.secretArn} --query SecretString --output text > /tmp/app-secrets.json`,
      // RDS needs time to populate the secret with actual credentials
      props.database.secrets['postgres']
        ? `until aws secretsmanager get-secret-value --region ${cdk.Stack.of(this).region} --secret-id ${props.database.secrets['postgres'].secretArn} --query SecretString --output text | jq -e '.password' > /dev/null 2>&1; do echo "Waiting for RDS to populate secret..."; sleep 10; done && aws secretsmanager get-secret-value --region ${cdk.Stack.of(this).region} --secret-id ${props.database.secrets['postgres'].secretArn} --query SecretString --output text > /tmp/db-secrets.json`
        : 'echo \'{"username":"postgres","password":"postgres"}\' > /tmp/db-secrets.json',
      props.database.secrets['documentdb']
        ? `aws secretsmanager get-secret-value --region ${cdk.Stack.of(this).region} --secret-id ${props.database.secrets['documentdb'].secretArn} --query SecretString --output text > /tmp/docdb-secrets.json`
        : 'echo "{}" > /tmp/docdb-secrets.json',
      
      // Create environment file with database credentials inline
      'echo "HOST=0.0.0.0" > .env',
      'echo "PORT=3080" >> .env',
      `echo "DOMAIN=${props.domainConfig?.domainName || this.loadBalancer.loadBalancerDnsName}" >> .env`,
      'echo "" >> .env',
      'echo "# Database" >> .env',
      `echo "DATABASE_URL=postgresql://$(cat /tmp/db-secrets.json | jq -r .username):$(cat /tmp/db-secrets.json | jq -r .password | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip(), safe=''))")@${props.database.endpoints['postgres']}:5432/librechat?sslmode=require&sslrootcert=/opt/librechat/rds-ca-2019-root.pem" >> .env`,
      'echo "POSTGRES_DB=librechat" >> .env',
      'echo "POSTGRES_USER=$(cat /tmp/db-secrets.json | jq -r .username)" >> .env',
      'echo "POSTGRES_PASSWORD=$(cat /tmp/db-secrets.json | jq -r .password)" >> .env',
      `echo "DB_HOST=${props.database.endpoints['postgres']}" >> .env`,
      'echo "DB_PORT=5432" >> .env',
      props.database.endpoints['documentdb']
        ? `echo "MONGO_URI=${buildDocumentDBConnectionTemplate(props.database.endpoints['documentdb'])}" >> .env`
        : 'echo "MONGO_URI=mongodb://mongodb:27017/LibreChat" >> .env',
      'echo "" >> .env',
      'echo "# AWS" >> .env',
      `echo "AWS_DEFAULT_REGION=${cdk.Stack.of(this).region}" >> .env`,
      `echo "BEDROCK_AWS_DEFAULT_REGION=${cdk.Stack.of(this).region}" >> .env`,
      'echo "ENDPOINTS=bedrock" >> .env',
      'echo "" >> .env',
      'echo "# S3" >> .env',
      'echo "CDN_PROVIDER=s3" >> .env',
      `echo "S3_BUCKET_NAME=${props.storage.s3Bucket.bucketName}" >> .env`,
      `echo "S3_REGION=${cdk.Stack.of(this).region}" >> .env`,
      'echo "" >> .env',
      'echo "# Security" >> .env',
      'JWT_SECRET=$(cat /tmp/app-secrets.json | jq -r .jwt_secret || echo "fallback-jwt-secret")',
      'echo "JWT_SECRET=$JWT_SECRET" >> .env',
      'JWT_REFRESH_SECRET=$(cat /tmp/app-secrets.json | jq -r .jwt_refresh_secret || openssl rand -hex 32)',
      'echo "JWT_REFRESH_SECRET=$JWT_REFRESH_SECRET" >> .env',
      'CREDS_KEY=$(openssl rand -hex 32)',
      'echo "CREDS_KEY=$CREDS_KEY" >> .env',
      'CREDS_IV=$(openssl rand -hex 16)',
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
      'echo "" >> .env',
      'echo "# Meilisearch" >> .env',
      `echo "MEILISEARCH_ENABLED=${props.enableMeilisearch}" >> .env`,
      'echo "MEILISEARCH_URL=http://meilisearch:7700" >> .env',
      'MEILI_KEY=$(openssl rand -hex 32)',
      'echo "MEILISEARCH_MASTER_KEY=$MEILI_KEY" >> .env',
      'echo "" >> .env',
      'echo "# Web Search (Optional - configure API keys in AWS Secrets Manager)" >> .env',
      'echo "SEARCH_ENABLED=true" >> .env',
      'GOOGLE_API=$(cat /tmp/app-secrets.json | jq -r ".google_search_api_key // empty" || echo "")',
      'echo "GOOGLE_SEARCH_API_KEY=$GOOGLE_API" >> .env',
      'GOOGLE_CSE=$(cat /tmp/app-secrets.json | jq -r ".google_cse_id // empty" || echo "")',
      'echo "GOOGLE_CSE_ID=$GOOGLE_CSE" >> .env',
      'BING_KEY=$(cat /tmp/app-secrets.json | jq -r ".bing_api_key // empty" || echo "")',
      'echo "BING_API_KEY=$BING_KEY" >> .env',

      // Store database credentials in variables for docker-compose
      'DB_USER=$(cat /tmp/db-secrets.json | jq -r .username)',
      'DB_PASS=$(cat /tmp/db-secrets.json | jq -r .password)',
      
      // Create docker-compose.yml with actual values substituted
      'cat > docker-compose.yml << EOF',
      'version: "3.8"',
      '',
      'services:',
      '  librechat:',
      '    image: ghcr.io/danny-avila/librechat:latest',
      '    container_name: librechat',
      '    restart: unless-stopped',
      '    env_file: .env',
      '    ports:',
      '      - "3080:3080"',
      '    volumes:',
      '      - ./librechat.yaml:/app/librechat.yaml',
      '      - ./logs:/app/api/logs',
      '      - ./uploads:/app/client/public/uploads',
      '    depends_on:',
      '      rag-api:',
      '        condition: service_healthy',
      props.enableMeilisearch ? '      - meilisearch' : '',
      '',
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
      '      - POSTGRES_PASSWORD=$DB_PASS',
      '    ports:',
      '      - "8000:8000"',
      '    healthcheck:',
      '      test: ["CMD-SHELL", "python -c \\"import socket; s=socket.socket(); s.connect((\'localhost\', 8000)); s.close()\\" || exit 1"]',
      '      interval: 30s',
      '      timeout: 10s',
      '      retries: 5',
      '      start_period: 60s',
      '',
      props.enableMeilisearch
        ? `  meilisearch:
    image: getmeili/meilisearch:v1.6
    container_name: meilisearch
    restart: unless-stopped
    env_file: .env
    volumes:
      - ./meili_data:/meili_data`
        : '',
      'EOF',

      // Create LibreChat configuration
      'cat > librechat.yaml << "EOL"',
      'version: 1.2.1',
      '',
      'cache: true',
      '',
      'endpoints:',
      '  bedrock:',
      '    titleModel: "anthropic.claude-sonnet-4-20250525-v1:0"',
      '    streamRate: 35',
      '    availableRegions:',
      `      - "${cdk.Stack.of(this).region}"`,
      '',
      '  google:',
      '    enabled: true',
      '    availableTools: ["google_search"]',
      '',
      '  bing:',
      '    enabled: true', 
      '    availableTools: ["bing_search"]',
      '',
      'fileConfig:',
      '  endpoints:',
      '    default:',
      '      fileLimit: 50',
      '      fileSizeLimit: 100',
      '      totalSizeLimit: 500',
      '      supportedMimeTypes:',
      '        - "application/pdf"',
      '        - "text/plain"',
      '        - "text/csv"',
      '        - "text/html"',
      '        - "text/markdown"',
      '        - "application/vnd.openxmlformats-officedocument.wordprocessingml.document"',
      '        - "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"',
      '        - "application/vnd.openxmlformats-officedocument.presentationml.presentation"',
      '',
      'registration:',
      `  enabled: ${props.environment !== 'production'}`,
      'EOL',

      // Install CloudWatch agent
      'wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm',
      'rpm -U ./amazon-cloudwatch-agent.rpm',

      // Configure CloudWatch agent
      'cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << "EOL"',
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
      'docker compose pull',
      // Start with new docker compose syntax and proper health checks
      'docker compose up -d --wait',
      // Wait for containers to start
      'sleep 30',
      // Check container status
      'docker ps -a >> /var/log/cloud-init-output.log',
      'docker logs rag-api >> /var/log/cloud-init-output.log 2>&1 || true',

      // Create systemd service
      'cat > /etc/systemd/system/librechat.service << "EOL"',
      '[Unit]',
      'Description=LibreChat Docker Compose Application',
      'Requires=docker.service',
      'After=docker.service',
      '',
      '[Service]',
      'Type=simple',
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

      // Clean up
      'rm -f /tmp/app-secrets.json /tmp/db-secrets.json',

      // Signal will be handled by cfn-init
      'echo "User data script completed successfully" >> /var/log/cloud-init-output.log'
    );

    const instance = new ec2.Instance(this, 'Instance', {
      vpc: props.vpc,
      instanceType: new ec2.InstanceType(props.instanceType),
      machineImage: ami,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
      securityGroup: this.securityGroup,
      role: role,
      keyName: props.keyPairName,
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
