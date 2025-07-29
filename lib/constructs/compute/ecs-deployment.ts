import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as route53_targets from 'aws-cdk-lib/aws-route53-targets';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

import { DatabaseConstruct } from '../database/database-construct';
import { StorageConstruct } from '../storage/storage-construct';
import { buildDocumentDBConnectionTemplateECS } from '../../utils/connection-strings';

export interface ECSDeploymentProps {
  vpc: ec2.IVpc;
  cluster: ecs.ICluster;
  cpu?: number;
  memory?: number;
  desiredCount?: number;
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

export class ECSDeployment extends Construct {
  public readonly service: ecs.FargateService;
  public readonly loadBalancer: elbv2.ApplicationLoadBalancer;
  public readonly loadBalancerUrl: string;
  public readonly cluster: ecs.ICluster;

  constructor(scope: Construct, id: string, props: ECSDeploymentProps) {
    super(scope, id);

    this.cluster = props.cluster;

    // Create shared security group
    const serviceSecurityGroup = new ec2.SecurityGroup(this, 'ServiceSecurityGroup', {
      vpc: props.vpc,
      description: 'Security group for LibreChat ECS services',
      allowAllOutbound: true,
    });

    // Allow internal communication
    serviceSecurityGroup.addIngressRule(
      serviceSecurityGroup,
      ec2.Port.allTraffic(),
      'Allow internal service communication'
    );

    // Allow EFS mount for services that need it
    props.storage.allowEfsMount(serviceSecurityGroup);

    // Deploy supporting services first
    if (props.enableMeilisearch) {
      this.createMeilisearchService(props, serviceSecurityGroup);
    }

    if (props.enableRag) {
      this.createRagService(props, serviceSecurityGroup);
    }

    // Create main LibreChat service
    this.service = this.createLibreChatService(props, serviceSecurityGroup);

    // Create Application Load Balancer
    const albSecurityGroup = this.createLoadBalancerSecurityGroup(props);
    this.loadBalancer = this.createLoadBalancer(props, albSecurityGroup);

    // Allow ALB to communicate with service
    serviceSecurityGroup.addIngressRule(
      albSecurityGroup,
      ec2.Port.tcp(3080),
      'Allow traffic from ALB'
    );

    // Configure target groups and listeners
    const targetGroup = this.createTargetGroup(props);
    this.configureListener(props, targetGroup);

    // Register service with target group
    targetGroup.addTarget(this.service);

    // Set up auto-scaling
    this.configureAutoScaling(props);

    // Set up domain if configured
    if (props.domainConfig?.hostedZoneId) {
      this.configureDomain(props);
      this.loadBalancerUrl = `https://${props.domainConfig.domainName}`;
    } else {
      this.loadBalancerUrl = `http://${this.loadBalancer.loadBalancerDnsName}`;
    }
  }

  private createMeilisearchService(
    props: ECSDeploymentProps,
    securityGroup: ec2.SecurityGroup
  ): ecs.FargateService {
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'MeilisearchTaskDef', {
      memoryLimitMiB: 2048,
      cpu: 1024,
    });

    const container = taskDefinition.addContainer('meilisearch', {
      image: ecs.ContainerImage.fromRegistry('getmeili/meilisearch:v1.6'),
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'meilisearch',
        logRetention: logs.RetentionDays.ONE_MONTH,
      }),
      environment: {
        MEILI_ENV: props.environment === 'production' ? 'production' : 'development',
        MEILI_NO_ANALYTICS: 'true',
      },
      secrets: {
        MEILI_MASTER_KEY: ecs.Secret.fromSecretsManager(props.appSecrets, 'meilisearch_master_key'),
      },
    });

    container.addPortMappings({
      containerPort: 7700,
      protocol: ecs.Protocol.TCP,
    });

    // Mount EFS for persistent data
    if (props.storage.fileSystem && props.storage.accessPoints['meilisearch']) {
      const volumeName = 'meilisearch-data';

      taskDefinition.addVolume({
        name: volumeName,
        efsVolumeConfiguration: {
          fileSystemId: props.storage.fileSystem.fileSystemId,
          transitEncryption: 'ENABLED',
          authorizationConfig: {
            accessPointId: props.storage.accessPoints['meilisearch'].accessPointId,
            iam: 'ENABLED',
          },
        },
      });

      container.addMountPoints({
        containerPath: '/meili_data',
        sourceVolume: volumeName,
        readOnly: false,
      });
    }

    const service = new ecs.FargateService(this, 'MeilisearchService', {
      cluster: this.cluster,
      taskDefinition,
      desiredCount: 1,
      securityGroups: [securityGroup],
      cloudMapOptions: {
        name: 'meilisearch',
        containerPort: 7700,
      },
      enableExecuteCommand: true,
      platformVersion: ecs.FargatePlatformVersion.LATEST,
    });

    return service;
  }

  private createRagService(
    props: ECSDeploymentProps,
    securityGroup: ec2.SecurityGroup
  ): ecs.FargateService {
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'RagTaskDef', {
      memoryLimitMiB: 4096,
      cpu: 2048,
    });

    // Grant database access
    if (props.database.secrets['postgres']) {
      props.database.secrets['postgres'].grantRead(taskDefinition.taskRole);
    }

    // Grant Bedrock access
    taskDefinition.taskRole.addToPrincipalPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['bedrock:InvokeModel', 'bedrock:InvokeModelWithResponseStream'],
        resources: ['*'],
      })
    );

    const container = taskDefinition.addContainer('rag-api', {
      image: ecs.ContainerImage.fromRegistry('ghcr.io/danny-avila/librechat-rag-api-dev:latest'),
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'rag-api',
        logRetention: logs.RetentionDays.ONE_MONTH,
      }),
      environment: {
        POSTGRES_DB: 'librechat',
        DB_HOST: props.database.endpoints['postgres'] || '',
        DB_PORT: '5432',
        AWS_DEFAULT_REGION: cdk.Stack.of(this).region,
        EMBEDDINGS_PROVIDER: 'bedrock',
        EMBEDDINGS_MODEL: 'amazon.titan-embed-text-v2:0',
        CHUNK_SIZE: '1500',
        CHUNK_OVERLAP: '200',
      },
      secrets: {
        ...(props.database.secrets['postgres']
          ? {
              POSTGRES_USER: ecs.Secret.fromSecretsManager(
                props.database.secrets['postgres'],
                'username'
              ),
              POSTGRES_PASSWORD: ecs.Secret.fromSecretsManager(
                props.database.secrets['postgres'],
                'password'
              ),
            }
          : {}),
        JWT_SECRET: ecs.Secret.fromSecretsManager(props.appSecrets, 'jwt_secret'),
      },
    });

    container.addPortMappings({
      containerPort: 8000,
      protocol: ecs.Protocol.TCP,
    });

    const service = new ecs.FargateService(this, 'RagService', {
      cluster: this.cluster,
      taskDefinition,
      desiredCount: 2,
      securityGroups: [securityGroup],
      cloudMapOptions: {
        name: 'rag-api',
        containerPort: 8000,
      },
      enableExecuteCommand: true,
      platformVersion: ecs.FargatePlatformVersion.LATEST,
    });

    // Allow database access
    if (props.database.securityGroups['postgres']) {
      props.database.securityGroups['postgres'].addIngressRule(
        securityGroup,
        ec2.Port.tcp(5432),
        'Allow PostgreSQL from RAG service'
      );
    }

    return service;
  }

  private createLibreChatService(
    props: ECSDeploymentProps,
    securityGroup: ec2.SecurityGroup
  ): ecs.FargateService {
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'LibreChatTaskDef', {
      memoryLimitMiB: props.memory || 4096,
      cpu: props.cpu || 2048,
    });

    // Grant permissions
    props.storage.grantReadWrite(taskDefinition.taskRole);
    if (props.database.secrets['postgres']) {
      props.database.secrets['postgres'].grantRead(taskDefinition.taskRole);
    }
    if (props.database.secrets['documentdb']) {
      props.database.secrets['documentdb'].grantRead(taskDefinition.taskRole);
    }
    props.appSecrets.grantRead(taskDefinition.taskRole);

    // Grant Bedrock access
    taskDefinition.taskRole.addToPrincipalPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'bedrock:InvokeModel',
          'bedrock:InvokeModelWithResponseStream',
          'bedrock:ListFoundationModels',
          'bedrock:GetFoundationModel',
        ],
        resources: ['*'],
      })
    );

    // Build environment variables
    const environment: { [key: string]: string } = {
      HOST: '0.0.0.0',
      PORT: '3080',
      DOMAIN: props.domainConfig?.domainName || 'localhost',

      // Database
      DATABASE_URL: this.buildDatabaseUrl(props),

      // AWS
      AWS_DEFAULT_REGION: cdk.Stack.of(this).region,
      ENDPOINTS: 'bedrock',

      // S3
      CDN_PROVIDER: 's3',
      S3_BUCKET_NAME: props.storage.s3Bucket.bucketName,
      S3_REGION: cdk.Stack.of(this).region,

      // Features
      ALLOW_REGISTRATION: props.environment === 'production' ? 'false' : 'true',
      ALLOW_SOCIAL_LOGIN: 'false',

      // RAG Configuration
      RAG_ENABLED: String(props.enableRag),
      RAG_API_URL: props.enableRag ? 'http://rag-api.librechat.local:8000' : '',

      // Meilisearch
      MEILISEARCH_ENABLED: String(props.enableMeilisearch),
      MEILISEARCH_URL: props.enableMeilisearch ? 'http://meilisearch.librechat.local:7700' : '',
    };

    // Add DocumentDB if enabled
    if (props.database.documentDbCluster) {
      environment.MONGO_URI = this.buildMongoUri(props);
    }

    const container = taskDefinition.addContainer('librechat', {
      image: ecs.ContainerImage.fromRegistry('ghcr.io/danny-avila/librechat:latest'),
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'librechat',
        logRetention: logs.RetentionDays.ONE_MONTH,
      }),
      environment,
      secrets: {
        JWT_SECRET: ecs.Secret.fromSecretsManager(props.appSecrets, 'jwt_secret'),
        CREDS_KEY: ecs.Secret.fromSecretsManager(props.appSecrets, 'creds_key'),
        CREDS_IV: ecs.Secret.fromSecretsManager(props.appSecrets, 'creds_iv'),
        ...(props.enableMeilisearch
          ? {
              MEILISEARCH_MASTER_KEY: ecs.Secret.fromSecretsManager(
                props.appSecrets,
                'meilisearch_master_key'
              ),
            }
          : {}),
        ...(props.database.secrets['postgres']
          ? {
              POSTGRES_USER: ecs.Secret.fromSecretsManager(
                props.database.secrets['postgres'],
                'username'
              ),
              POSTGRES_PASSWORD: ecs.Secret.fromSecretsManager(
                props.database.secrets['postgres'],
                'password'
              ),
            }
          : {}),
        ...(props.database.secrets['documentdb']
          ? {
              MONGO_USER: ecs.Secret.fromSecretsManager(
                props.database.secrets['documentdb'],
                'username'
              ),
              MONGO_PASSWORD: ecs.Secret.fromSecretsManager(
                props.database.secrets['documentdb'],
                'password'
              ),
            }
          : {}),
      },
      healthCheck: {
        command: ['CMD-SHELL', 'curl -f http://localhost:3080/health || exit 1'],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(10),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60),
      },
    });

    container.addPortMappings({
      containerPort: 3080,
      protocol: ecs.Protocol.TCP,
    });

    // Mount EFS for uploads if available
    if (props.storage.fileSystem && props.storage.accessPoints['librechat-uploads']) {
      const volumeName = 'uploads';

      taskDefinition.addVolume({
        name: volumeName,
        efsVolumeConfiguration: {
          fileSystemId: props.storage.fileSystem.fileSystemId,
          transitEncryption: 'ENABLED',
          authorizationConfig: {
            accessPointId: props.storage.accessPoints['librechat-uploads'].accessPointId,
            iam: 'ENABLED',
          },
        },
      });

      container.addMountPoints({
        containerPath: '/app/client/public/uploads',
        sourceVolume: volumeName,
        readOnly: false,
      });
    }

    const service = new ecs.FargateService(this, 'LibreChatService', {
      cluster: this.cluster,
      taskDefinition,
      desiredCount: props.desiredCount || 2,
      securityGroups: [securityGroup],
      healthCheckGracePeriod: cdk.Duration.seconds(120),
      enableExecuteCommand: true,
      platformVersion: ecs.FargatePlatformVersion.LATEST,
    });

    // Allow database access
    if (props.database.securityGroups['postgres']) {
      props.database.securityGroups['postgres'].addIngressRule(
        securityGroup,
        ec2.Port.tcp(5432),
        'Allow PostgreSQL from LibreChat service'
      );
    }

    if (props.database.securityGroups['documentdb']) {
      props.database.securityGroups['documentdb'].addIngressRule(
        securityGroup,
        ec2.Port.tcp(27017),
        'Allow DocumentDB from LibreChat service'
      );
    }

    return service;
  }

  private createLoadBalancerSecurityGroup(props: ECSDeploymentProps): ec2.SecurityGroup {
    const albSecurityGroup = new ec2.SecurityGroup(this, 'ALBSecurityGroup', {
      vpc: props.vpc,
      description: 'Security group for LibreChat ALB',
      allowAllOutbound: true,
    });

    albSecurityGroup.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(80), 'Allow HTTP traffic');

    if (props.domainConfig) {
      albSecurityGroup.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(443), 'Allow HTTPS traffic');
    }

    return albSecurityGroup;
  }

  private createLoadBalancer(
    props: ECSDeploymentProps,
    securityGroup: ec2.SecurityGroup
  ): elbv2.ApplicationLoadBalancer {
    const alb = new elbv2.ApplicationLoadBalancer(this, 'LoadBalancer', {
      vpc: props.vpc,
      internetFacing: true,
      securityGroup: securityGroup,
      deletionProtection: props.environment === 'production',
    });

    return alb;
  }

  private createTargetGroup(props: ECSDeploymentProps): elbv2.ApplicationTargetGroup {
    return new elbv2.ApplicationTargetGroup(this, 'TargetGroup', {
      vpc: props.vpc,
      port: 3080,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
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
    props: ECSDeploymentProps,
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

  private configureAutoScaling(props: ECSDeploymentProps): void {
    const scaling = this.service.autoScaleTaskCount({
      minCapacity: props.environment === 'production' ? 2 : 1,
      maxCapacity: props.environment === 'production' ? 10 : 3,
    });

    // CPU-based scaling
    scaling.scaleOnCpuUtilization('CpuScaling', {
      targetUtilizationPercent: 70,
      scaleInCooldown: cdk.Duration.minutes(2),
      scaleOutCooldown: cdk.Duration.minutes(1),
    });

    // Memory-based scaling
    scaling.scaleOnMemoryUtilization('MemoryScaling', {
      targetUtilizationPercent: 75,
      scaleInCooldown: cdk.Duration.minutes(2),
      scaleOutCooldown: cdk.Duration.minutes(1),
    });
  }

  private configureDomain(props: ECSDeploymentProps): void {
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

  private buildDatabaseUrl(props: ECSDeploymentProps): string {
    const endpoint = props.database.endpoints['postgres'];
    return `postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@${endpoint}:5432/librechat?sslmode=require`;
  }

  private buildMongoUri(props: ECSDeploymentProps): string {
    const endpoint = props.database.endpoints['documentdb'];
    if (!endpoint) {
      throw new Error('DocumentDB endpoint not found');
    }
    return buildDocumentDBConnectionTemplateECS(endpoint);
  }
}
