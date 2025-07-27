import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as docdb from 'aws-cdk-lib/aws-docdb';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cr from 'aws-cdk-lib/custom-resources';
import { Construct } from 'constructs';
import * as path from 'path';

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
  
  constructor(scope: Construct, id: string, props: DatabaseConstructProps) {
    super(scope, id);
    
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
    // Create security group
    const securityGroup = new ec2.SecurityGroup(this, 'PostgresSecurityGroup', {
      vpc: props.vpc,
      description: 'Security group for Aurora PostgreSQL',
      allowAllOutbound: false,
    });
    this.securityGroups['postgres'] = securityGroup;
    
    // Create parameter group for pgvector
    const parameterGroup = new rds.ParameterGroup(this, 'PostgresParameterGroup', {
      engine: rds.DatabaseClusterEngine.auroraPostgres({
        version: rds.AuroraPostgresEngineVersion.VER_15_5,
      }),
      description: 'Parameter group for LibreChat',
      parameters: {
        'max_connections': '200',
        'shared_buffers': '{DBInstanceClassMemory/10922}',
        'effective_cache_size': '{DBInstanceClassMemory/10922*3}',
        'maintenance_work_mem': '512MB',
        'checkpoint_completion_target': '0.9',
        'wal_buffers': '16MB',
        'default_statistics_target': '100',
        'random_page_cost': '1.1',
        'effective_io_concurrency': '200',
        'work_mem': '256MB',
        'min_wal_size': '1GB',
        'max_wal_size': '4GB',
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
      readers: props.environment === 'production' ? [
        rds.ClusterInstance.serverlessV2('ReaderInstance', {
          scaleWithWriter: false,
        }),
      ] : [],
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
      cloudwatchLogsExports: ['postgresql'],
      cloudwatchLogsRetention: logs.RetentionDays.ONE_MONTH,
      defaultDatabaseName: 'librechat',
      credentials: rds.Credentials.fromGeneratedSecret('postgres', {
        secretName: `librechat-${props.environment}-postgres-secret`,
      }),
    });
    
    this.endpoints['postgres'] = this.postgresCluster.clusterEndpoint.hostname;
    this.secrets['postgres'] = this.postgresCluster.secret!;
  }
  
  private createRdsPostgres(props: DatabaseConstructProps): void {
    // Create security group
    const securityGroup = new ec2.SecurityGroup(this, 'PostgresSecurityGroup', {
      vpc: props.vpc,
      description: 'Security group for RDS PostgreSQL',
      allowAllOutbound: false,
    });
    this.securityGroups['postgres'] = securityGroup;
    
    // Create parameter group for pgvector
    const parameterGroup = new rds.ParameterGroup(this, 'PostgresParameterGroup', {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_15_7,
      }),
      description: 'Parameter group for LibreChat',
      parameters: {
        'max_connections': '100',
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
        props.instanceClass?.includes('micro') ? ec2.InstanceSize.MICRO : ec2.InstanceSize.SMALL,
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
      backupRetention: cdk.Duration.days(props.backupRetentionDays || 1),
      deleteAutomatedBackups: true,
      deletionProtection: false,
      databaseName: 'librechat',
      credentials: rds.Credentials.fromGeneratedSecret('postgres', {
        secretName: `librechat-${props.environment}-postgres-secret`,
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
    // Create security group
    const securityGroup = new ec2.SecurityGroup(this, 'DocumentDbSecurityGroup', {
      vpc: props.vpc,
      description: 'Security group for DocumentDB',
      allowAllOutbound: false,
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
        props.environment === 'production' ? ec2.InstanceSize.MEDIUM : ec2.InstanceSize.SMALL,
      ),
      instances: props.environment === 'production' ? 2 : 1,
      backup: {
        retention: cdk.Duration.days(props.backupRetentionDays || 7),
      },
      deletionProtection: props.environment === 'production',
      storageEncrypted: true,
      removalPolicy: props.environment === 'production' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
      cloudWatchLogsRetention: logs.RetentionDays.ONE_MONTH,
      masterUser: {
        username: 'docdbadmin',
        secretName: `librechat-${props.environment}-documentdb-secret`,
      },
    });
    
    this.endpoints['documentdb'] = this.documentDbCluster.clusterEndpoint.hostname;
    this.secrets['documentdb'] = this.documentDbCluster.secret!;
  }
  
  private initializeDatabases(props: DatabaseConstructProps): void {
    // Initialize PostgreSQL with pgvector
    if ((this.postgresCluster || this.postgresInstance) && this.secrets['postgres'] && this.securityGroups['postgres']) {
      // Create Lambda layer for psycopg2
      const psycopg2Layer = new lambda.LayerVersion(this, 'Psycopg2Layer', {
        code: lambda.Code.fromAsset(path.join(__dirname, '../../../lambda/layers/psycopg2/psycopg2-layer.zip')),
        compatibleRuntimes: [lambda.Runtime.PYTHON_3_11],
        description: 'psycopg2-binary for PostgreSQL access',
      });
      
      const initPostgresFunction = new lambda.Function(this, 'InitPostgresFunction', {
        runtime: lambda.Runtime.PYTHON_3_11,
        handler: 'init_postgres.handler',
        code: lambda.Code.fromAsset(path.join(__dirname, '../../../lambda/init-postgres')),
        layers: [psycopg2Layer],
        vpc: props.vpc,
        vpcSubnets: {
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        environment: {
          POSTGRES_SECRET_ARN: this.secrets['postgres'].secretArn,
          ENABLE_PGVECTOR: String(props.enablePgVector !== false),
          DB_HOST: this.endpoints['postgres'] || '',
          DB_PORT: '5432',
          DB_NAME: 'librechat',
          DB_SECRET_ID: this.secrets['postgres'].secretArn,
        },
        timeout: cdk.Duration.minutes(5),
        memorySize: 256,
        logRetention: logs.RetentionDays.ONE_WEEK,
      });
      
      // Grant permissions
      this.secrets['postgres'].grantRead(initPostgresFunction);
      if (initPostgresFunction.connections.securityGroups.length > 0) {
        this.securityGroups['postgres'].addIngressRule(
          initPostgresFunction.connections.securityGroups[0]!,
          ec2.Port.tcp(5432),
          'Allow Lambda to initialize database'
        );
      }
      
      // Create custom resource to trigger initialization
      const provider = new cr.Provider(this, 'InitPostgresProvider', {
        onEventHandler: initPostgresFunction,
        logRetention: logs.RetentionDays.ONE_DAY,
      });
      
      new cdk.CustomResource(this, 'InitPostgresResource', {
        serviceToken: provider.serviceToken,
        properties: {
          Version: '1.0', // Change this to trigger reinitialization
        },
      });
    }
    
    // Initialize DocumentDB
    if (this.documentDbCluster && this.secrets['documentdb'] && this.securityGroups['documentdb'] && this.endpoints['documentdb']) {
      const initDocdbFunction = new lambda.Function(this, 'InitDocdbFunction', {
        runtime: lambda.Runtime.PYTHON_3_11,
        handler: 'init_docdb.handler',
        code: lambda.Code.fromAsset(path.join(__dirname, '../../../lambda/init-docdb')),
        vpc: props.vpc,
        vpcSubnets: {
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        environment: {
          DOCDB_SECRET_ARN: this.secrets['documentdb'].secretArn,
          DOCDB_ENDPOINT: this.endpoints['documentdb'],
        },
        timeout: cdk.Duration.minutes(5),
        memorySize: 256,
        logRetention: logs.RetentionDays.ONE_WEEK,
        layers: [
          lambda.LayerVersion.fromLayerVersionArn(
            this,
            'PyMongoLayer',
            `arn:aws:lambda:${cdk.Stack.of(this).region}:770693421928:layer:Klayers-p311-pymongo:1`
          ),
        ],
      });
      
      // Grant permissions
      this.secrets['documentdb'].grantRead(initDocdbFunction);
      if (initDocdbFunction.connections.securityGroups.length > 0) {
        this.securityGroups['documentdb'].addIngressRule(
          initDocdbFunction.connections.securityGroups[0]!,
          ec2.Port.tcp(27017),
          'Allow Lambda to initialize database'
        );
      }
      
      // Create custom resource to trigger initialization
      const provider = new cr.Provider(this, 'InitDocdbProvider', {
        onEventHandler: initDocdbFunction,
        logRetention: logs.RetentionDays.ONE_DAY,
      });
      
      new cdk.CustomResource(this, 'InitDocdbResource', {
        serviceToken: provider.serviceToken,
        properties: {
          Version: '1.0', // Change this to trigger reinitialization
        },
      });
    }
  }
}
