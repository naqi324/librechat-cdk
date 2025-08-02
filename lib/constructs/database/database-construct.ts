import * as path from 'path';

import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as docdb from 'aws-cdk-lib/aws-docdb';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cr from 'aws-cdk-lib/custom-resources';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

export interface DatabaseConstructProps {
  vpc: ec2.IVpc;
  engine: 'postgres' | 'postgres-and-documentdb';
  instanceClass?: string;
  allocatedStorage?: number;
  backupRetentionDays?: number;
  enablePgVector?: boolean;
  environment: string;
}

export class DatabaseConstruct extends Construct {
  public postgresCluster?: rds.DatabaseCluster;
  public postgresInstance?: rds.DatabaseInstance;
  public documentDbCluster?: docdb.DatabaseCluster;
  public readonly endpoints: { [key: string]: string } = {};
  public readonly secrets: { [key: string]: secretsmanager.ISecret } = {};
  public readonly securityGroups: { [key: string]: ec2.ISecurityGroup } = {};

  // Generate unique suffix for resource names to avoid conflicts
  private readonly uniqueSuffix: string;

  constructor(scope: Construct, id: string, props: DatabaseConstructProps) {
    super(scope, id);

    // Generate unique suffix using environment and a short hash
    this.uniqueSuffix = `${props.environment}-${Date.now().toString(36).slice(-4)}`;

    // Create PostgreSQL database
    if (props.environment === 'production') {
      this.createAuroraPostgres(props);
    } else {
      this.createRdsPostgres(props);
    }

    // Create DocumentDB if requested
    if (props.engine === 'postgres-and-documentdb') {
      this.createDocumentDb(props);
    }

    // Initialize databases
    this.initializeDatabases(props);
  }

  private createAuroraPostgres(props: DatabaseConstructProps): void {
    // Create KMS key for database encryption
    const dbEncryptionKey = new kms.Key(this, 'PostgresEncryptionKey', {
      description: `LibreChat PostgreSQL encryption key - ${props.environment}`,
      enableKeyRotation: true,
      alias: `alias/librechat-postgres-${props.environment}`,
      removalPolicy: props.environment === 'production' 
        ? cdk.RemovalPolicy.RETAIN 
        : cdk.RemovalPolicy.DESTROY,
      pendingWindow: cdk.Duration.days(30),
    });

    // Grant RDS service access to the key
    dbEncryptionKey.grant(new iam.ServicePrincipal('rds.amazonaws.com'), 'kms:*');

    // Create security group
    const securityGroup = new ec2.SecurityGroup(this, 'PostgresSecurityGroup', {
      vpc: props.vpc,
      description: 'Security group for Aurora PostgreSQL',
      allowAllOutbound: true, // Allow outbound for RDS to communicate with AWS services
    });
    this.securityGroups['postgres'] = securityGroup;

    // Create parameter group for pgvector
    const parameterGroup = new rds.ParameterGroup(this, 'PostgresParameterGroup', {
      engine: rds.DatabaseClusterEngine.auroraPostgres({
        version: rds.AuroraPostgresEngineVersion.VER_15_5,
      }),
      description: 'Parameter group for LibreChat',
      parameters: {
        max_connections: '200',
        shared_buffers: '{DBInstanceClassMemory/10922}',
        effective_cache_size: '{DBInstanceClassMemory/10922*3}',
        maintenance_work_mem: '512MB',
        checkpoint_completion_target: '0.9',
        wal_buffers: '16MB',
        default_statistics_target: '100',
        random_page_cost: '1.1',
        effective_io_concurrency: '200',
        work_mem: '256MB',
        min_wal_size: '1GB',
        max_wal_size: '4GB',
        'rds.force_ssl': '1',
      },
    });

    // Create database cluster
    this.postgresCluster = new rds.DatabaseCluster(this, 'PostgresCluster', {
      engine: rds.DatabaseClusterEngine.auroraPostgres({
        version: rds.AuroraPostgresEngineVersion.VER_15_5,
      }),
      vpc: props.vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      securityGroups: [securityGroup],
      writer: rds.ClusterInstance.serverlessV2('WriterInstance', {
        scaleWithWriter: true,
        autoMinorVersionUpgrade: true,
        enablePerformanceInsights: props.environment === 'production',
      }),
      readers:
        props.environment === 'production'
          ? [
              rds.ClusterInstance.serverlessV2('ReaderInstance', {
                scaleWithWriter: false,
              }),
            ]
          : [],
      serverlessV2MinCapacity: props.environment === 'production' ? 0.5 : 0.5,
      serverlessV2MaxCapacity: props.environment === 'production' ? 16 : 2,
      parameterGroup: parameterGroup,
      backup: {
        retention: cdk.Duration.days(props.backupRetentionDays || 7),
        preferredWindow: '03:00-04:00',
      },
      preferredMaintenanceWindow: 'sun:04:00-sun:05:00',
      deletionProtection: props.environment === 'production',
      storageEncrypted: true,
      storageEncryptionKey: dbEncryptionKey,
      cloudwatchLogsExports: ['postgresql'],
      cloudwatchLogsRetention: logs.RetentionDays.ONE_MONTH,
      defaultDatabaseName: 'librechat',
      credentials: rds.Credentials.fromGeneratedSecret('postgres', {
        secretName: `${cdk.Stack.of(this).stackName}-postgres-secret-${this.uniqueSuffix}`,
      }),
      removalPolicy:
        props.environment === 'production' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
    });

    this.endpoints['postgres'] = this.postgresCluster.clusterEndpoint.hostname;
    this.secrets['postgres'] = this.postgresCluster.secret!;
  }

  private createRdsPostgres(props: DatabaseConstructProps): void {
    // Create KMS key for database encryption
    const dbEncryptionKey = new kms.Key(this, 'PostgresEncryptionKey', {
      description: `LibreChat PostgreSQL encryption key - ${props.environment}`,
      enableKeyRotation: true,
      alias: `alias/librechat-postgres-${props.environment}`,
      removalPolicy: props.environment === 'production' 
        ? cdk.RemovalPolicy.RETAIN 
        : cdk.RemovalPolicy.DESTROY,
      pendingWindow: cdk.Duration.days(30),
    });

    // Grant RDS service access to the key
    dbEncryptionKey.grant(new iam.ServicePrincipal('rds.amazonaws.com'), 'kms:*');

    // Create security group
    const securityGroup = new ec2.SecurityGroup(this, 'PostgresSecurityGroup', {
      vpc: props.vpc,
      description: 'Security group for RDS PostgreSQL',
      allowAllOutbound: true, // Allow outbound for RDS to communicate with AWS services
    });
    this.securityGroups['postgres'] = securityGroup;

    // Create parameter group for pgvector
    const parameterGroup = new rds.ParameterGroup(this, 'PostgresParameterGroup', {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_15_7,
      }),
      description: 'Parameter group for LibreChat',
      parameters: {
        max_connections: '100',
        'rds.force_ssl': '1',
      },
    });

    // Create database instance
    this.postgresInstance = new rds.DatabaseInstance(this, 'PostgresInstance', {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_15_7,
      }),
      instanceType: ec2.InstanceType.of(
        ec2.InstanceClass.T3,
        props.instanceClass?.includes('micro') ? ec2.InstanceSize.MICRO : ec2.InstanceSize.SMALL
      ),
      vpc: props.vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      securityGroups: [securityGroup],
      parameterGroup: parameterGroup,
      allocatedStorage: props.allocatedStorage || 20,
      storageType: rds.StorageType.GP3,
      storageEncrypted: true,
      storageEncryptionKey: dbEncryptionKey,
      backupRetention: cdk.Duration.days(props.backupRetentionDays || 1),
      deleteAutomatedBackups: props.environment !== 'production',
      deletionProtection: props.environment === 'production',
      databaseName: 'librechat',
      removalPolicy:
        props.environment === 'production' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
      credentials: rds.Credentials.fromGeneratedSecret('postgres', {
        secretName: `${cdk.Stack.of(this).stackName}-postgres-secret-${this.uniqueSuffix}`,
      }),
      multiAz: false,
      publiclyAccessible: false,
      autoMinorVersionUpgrade: true,
      cloudwatchLogsExports: ['postgresql'],
      cloudwatchLogsRetention: logs.RetentionDays.ONE_WEEK,
    });

    this.endpoints['postgres'] = this.postgresInstance.dbInstanceEndpointAddress;
    this.secrets['postgres'] = this.postgresInstance.secret!;
  }

  private createDocumentDb(props: DatabaseConstructProps): void {
    // Create KMS key for DocumentDB encryption
    const docdbEncryptionKey = new kms.Key(this, 'DocumentDbEncryptionKey', {
      description: `LibreChat DocumentDB encryption key - ${props.environment}`,
      enableKeyRotation: true,
      alias: `alias/librechat-docdb-${props.environment}`,
      removalPolicy: props.environment === 'production' 
        ? cdk.RemovalPolicy.RETAIN 
        : cdk.RemovalPolicy.DESTROY,
      pendingWindow: cdk.Duration.days(30),
    });

    // Grant DocumentDB service access to the key
    docdbEncryptionKey.grant(new iam.ServicePrincipal('rds.amazonaws.com'), 'kms:*');

    // Create security group
    const securityGroup = new ec2.SecurityGroup(this, 'DocumentDbSecurityGroup', {
      vpc: props.vpc,
      description: 'Security group for DocumentDB',
      allowAllOutbound: true, // Allow outbound for DocumentDB to communicate with AWS services
    });
    this.securityGroups['documentdb'] = securityGroup;

    // Create DocumentDB cluster
    this.documentDbCluster = new docdb.DatabaseCluster(this, 'DocumentDbCluster', {
      vpc: props.vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      securityGroup: securityGroup,
      instanceType: ec2.InstanceType.of(
        ec2.InstanceClass.T3,
        ec2.InstanceSize.MEDIUM // DocumentDB minimum supported T3 size
      ),
      instances: props.environment === 'production' ? 2 : 1,
      backup: {
        retention: cdk.Duration.days(props.backupRetentionDays || 7),
      },
      deletionProtection: props.environment === 'production',
      storageEncrypted: true,
      kmsKey: docdbEncryptionKey,
      removalPolicy:
        props.environment === 'production' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
      cloudWatchLogsRetention: logs.RetentionDays.ONE_MONTH,
      masterUser: {
        username: 'docdbadmin',
        secretName: `${cdk.Stack.of(this).stackName}-documentdb-secret-${this.uniqueSuffix}`,
      },
    });

    this.endpoints['documentdb'] = this.documentDbCluster.clusterEndpoint.hostname;
    this.secrets['documentdb'] = this.documentDbCluster.secret!;
  }

  private initializeDatabases(props: DatabaseConstructProps): void {
    // Initialize PostgreSQL with pgvector
    if (
      (this.postgresCluster || this.postgresInstance) &&
      this.secrets['postgres'] &&
      this.securityGroups['postgres']
    ) {
      // Create Lambda layer for psycopg2
      const psycopg2Layer = new lambda.LayerVersion(this, 'Psycopg2Layer', {
        code: lambda.Code.fromAsset(
          path.join(__dirname, '../../../lambda/layers/psycopg2/psycopg2-layer.zip')
        ),
        compatibleRuntimes: [lambda.Runtime.PYTHON_3_11],
        description: 'psycopg2-binary for PostgreSQL access',
      });

      const initPostgresFunction = new lambda.Function(this, 'InitPgFn', {
        runtime: lambda.Runtime.PYTHON_3_11,
        handler: 'init_postgres.handler',
        code: lambda.Code.fromAsset(path.join(__dirname, '../../../lambda/init-postgres')),
        layers: [psycopg2Layer],
        vpc: props.vpc,
        vpcSubnets: {
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        securityGroups: [
          new ec2.SecurityGroup(this, 'InitPostgresLambdaSG', {
            vpc: props.vpc,
            description: 'Security group for PostgreSQL initialization Lambda',
            allowAllOutbound: true,
          }),
        ],
        environment: {
          POSTGRES_SECRET_ARN: this.secrets['postgres'].secretArn,
          ENABLE_PGVECTOR: String(props.enablePgVector !== false),
          DB_HOST: this.endpoints['postgres'] || '',
          DB_PORT: '5432',
          DB_NAME: 'librechat',
          DB_SECRET_ID: this.secrets['postgres'].secretArn,
          MAX_RETRIES: '30', // Reduced from 90 for faster deployment
          RETRY_DELAY: '5',  // Reduced from 10 seconds
        },
        timeout: cdk.Duration.minutes(10), // Reduced from 15 to 10 minutes for faster failures
        memorySize: 256,
        logRetention: logs.RetentionDays.ONE_WEEK,
      });

      // Grant permissions
      this.secrets['postgres'].grantRead(initPostgresFunction);
      // Always add the ingress rule using the Lambda's security group
      const lambdaSecurityGroup = initPostgresFunction.connections.securityGroups[0];
      if (lambdaSecurityGroup) {
        this.securityGroups['postgres'].addIngressRule(
          lambdaSecurityGroup,
          ec2.Port.tcp(5432),
          'Allow Lambda to initialize database'
        );
      }

      // Create custom resource to trigger initialization
      const provider = new cr.Provider(this, 'InitPgProvider', {
        onEventHandler: initPostgresFunction,
        logRetention: logs.RetentionDays.ONE_DAY,
      });

      const initResource = new cdk.CustomResource(this, 'InitPgResource', {
        serviceToken: provider.serviceToken,
        properties: {
          Version: '1.0', // Change this to trigger reinitialization
          DBHost: this.endpoints['postgres'],
          DBPort: '5432',
          DBName: 'librechat',
          SecretId: this.secrets['postgres'].secretArn,
        },
      });

      // Ensure the custom resource waits for the database to be created
      if (this.postgresInstance) {
        initResource.node.addDependency(this.postgresInstance);
      } else if (this.postgresCluster) {
        initResource.node.addDependency(this.postgresCluster);
      }
    }

    // Initialize DocumentDB with improved retry logic
    if (
      this.documentDbCluster &&
      this.secrets['documentdb'] &&
      this.securityGroups['documentdb'] &&
      this.endpoints['documentdb']
    ) {
      const initDocdbFunction = new lambda.Function(this, 'InitDocFn', {
        runtime: lambda.Runtime.PYTHON_3_11,
        handler: 'init_docdb.handler',
        code: lambda.Code.fromAsset(path.join(__dirname, '../../../lambda/init-docdb')),
        vpc: props.vpc,
        vpcSubnets: {
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        securityGroups: [
          new ec2.SecurityGroup(this, 'InitDocSG', {
            vpc: props.vpc,
            description: 'Security group for DocumentDB initialization Lambda',
            allowAllOutbound: true,
          }),
        ],
        environment: {
          DB_SECRET_ID: this.secrets['documentdb'].secretArn,
          DB_HOST: this.endpoints['documentdb'],
          DB_PORT: '27017',
          DB_NAME: 'librechat',
          // Reduced retries for faster deployment
          MAX_RETRIES: '20', // 20 attempts (reduced from 60)
          RETRY_DELAY: '5', // 5 seconds between attempts = ~2 minutes max
        },
        timeout: cdk.Duration.minutes(10), // Reduced from 15 minutes
        memorySize: 256,
        logRetention: logs.RetentionDays.ONE_WEEK,
        layers: [
          new lambda.LayerVersion(this, 'PyMongoLayer', {
            code: lambda.Code.fromAsset(
              path.join(__dirname, '../../../lambda/layers/pymongo/pymongo-layer.zip')
            ),
            compatibleRuntimes: [lambda.Runtime.PYTHON_3_11],
            description: 'pymongo and dnspython for DocumentDB access',
          }),
          new lambda.LayerVersion(this, 'RdsCaLayer', {
            code: lambda.Code.fromAsset(
              path.join(__dirname, '../../../lambda/layers/rds-ca/rds-ca-layer.zip')
            ),
            compatibleRuntimes: [lambda.Runtime.PYTHON_3_11],
            description: 'RDS CA certificates for TLS connections',
          }),
        ],
      });

      // Grant permissions
      this.secrets['documentdb'].grantRead(initDocdbFunction);

      // Allow Lambda to connect to DocumentDB
      const docdbLambdaSecurityGroup = initDocdbFunction.connections.securityGroups[0];
      if (docdbLambdaSecurityGroup) {
        this.securityGroups['documentdb'].addIngressRule(
          docdbLambdaSecurityGroup,
          ec2.Port.tcp(27017),
          'Allow Lambda to initialize database'
        );
      }

      // Create custom resource provider
      const provider = new cr.Provider(this, 'InitDocProvider', {
        onEventHandler: initDocdbFunction,
        logRetention: logs.RetentionDays.ONE_DAY,
      });

      const initResource = new cdk.CustomResource(this, 'InitDocResource', {
        serviceToken: provider.serviceToken,
        properties: {
          Version: '1.0',
          DBHost: this.endpoints['documentdb'],
          DBPort: '27017',
          DBName: 'librechat',
          SecretId: this.secrets['documentdb'].secretArn,
        },
      });

      // Ensure the custom resource waits for the database to be created
      initResource.node.addDependency(this.documentDbCluster);

      // Add output for connection info
      new cdk.CfnOutput(this, 'DocumentDBInitStatus', {
        value: 'DocumentDB will be initialized automatically during deployment',
        description: 'DocumentDB initialization status',
      });
    }
  }
}
