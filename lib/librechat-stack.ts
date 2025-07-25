import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as certificatemanager from 'aws-cdk-lib/aws-certificatemanager';
import { Construct } from 'constructs';

// Import custom constructs
import { VpcConstruct } from './constructs/network/network-construct';
import { DatabaseConstruct } from './constructs/database/database-construct';
import { EC2Deployment } from './constructs/compute/ec2-deployment';
import { ECSDeployment } from './constructs/compute/ecs-deployment';
import { StorageConstruct } from './constructs/storage/storage-construct';
import { MonitoringConstruct } from './constructs/monitoring/monitoring-construct';

export interface LibreChatStackProps extends cdk.StackProps {
  // Deployment Configuration
  deploymentMode: 'EC2' | 'ECS';
  environment: 'development' | 'staging' | 'production';
  
  // Network Configuration
  vpcConfig?: {
    useExisting?: boolean;
    existingVpcId?: string;
    cidr?: string;
    maxAzs?: number;
    natGateways?: number;
  };
  
  // Domain Configuration (optional)
  domainConfig?: {
    domainName: string;
    certificateArn?: string;
    hostedZoneId?: string;
  };
  
  // Database Configuration
  databaseConfig?: {
    engine: 'postgres' | 'postgres-and-documentdb';
    instanceClass?: string;
    allocatedStorage?: number;
    backupRetentionDays?: number;
  };
  
  // Compute Configuration
  computeConfig?: {
    instanceType?: string; // For EC2
    desiredCount?: number; // For ECS
    cpu?: number; // For ECS
    memory?: number; // For ECS
  };
  
  // Monitoring Configuration
  alertEmail?: string;
  enableEnhancedMonitoring?: boolean;
  
  // Feature Flags
  enableRag?: boolean;
  enableMeilisearch?: boolean;
  enableSharePoint?: boolean;
  
  // Security
  allowedIps?: string[];
  keyPairName?: string;
}

export class LibreChatStack extends cdk.Stack {
  public readonly vpc: ec2.IVpc;
  public readonly loadBalancerUrl: string;
  public readonly databaseEndpoints: { [key: string]: string };
  
  constructor(scope: Construct, id: string, props: LibreChatStackProps) {
    super(scope, id, props);
    
    // Validate required properties
    this.validateProps(props);
    
    // Create or import VPC
    const vpcConstructProps: any = {
      useExisting: props.vpcConfig?.useExisting || false,
      cidr: props.vpcConfig?.cidr || '10.0.0.0/16',
      maxAzs: props.vpcConfig?.maxAzs || 2,
      natGateways: props.vpcConfig?.natGateways || (props.environment === 'production' ? 2 : 1),
      environment: props.environment,
    };
    
    if (props.vpcConfig?.existingVpcId) {
      vpcConstructProps.existingVpcId = props.vpcConfig.existingVpcId;
    }
    
    const vpcConstruct = new VpcConstruct(this, 'Network', vpcConstructProps);
    this.vpc = vpcConstruct.vpc;
    
    // Create storage resources
    const storage = new StorageConstruct(this, 'Storage', {
      environment: props.environment,
      enableEfs: props.deploymentMode === 'ECS',
      vpc: this.vpc,
    });
    
    // Create database resources
    const database = new DatabaseConstruct(this, 'Database', {
      vpc: this.vpc,
      engine: props.databaseConfig?.engine || 'postgres',
      instanceClass: props.databaseConfig?.instanceClass || this.getDefaultInstanceClass(props.environment),
      allocatedStorage: props.databaseConfig?.allocatedStorage || 100,
      backupRetentionDays: props.databaseConfig?.backupRetentionDays || (props.environment === 'production' ? 7 : 1),
      enablePgVector: true,
      environment: props.environment,
    });
    this.databaseEndpoints = database.endpoints;
    
    // Create secrets for application
    const appSecrets = this.createApplicationSecrets();
    
    // Deploy based on selected mode
    let deployment: EC2Deployment | ECSDeployment;
    
    if (props.deploymentMode === 'EC2') {
      const ec2Props: any = {
        vpc: this.vpc,
        instanceType: props.computeConfig?.instanceType || 't3.xlarge',
        keyPairName: props.keyPairName!,
        allowedIps: props.allowedIps || ['0.0.0.0/0'],
        storage: storage,
        database: database,
        appSecrets: appSecrets,
        environment: props.environment,
        enableRag: props.enableRag || false,
        enableMeilisearch: props.enableMeilisearch || false,
      };
      
      if (props.domainConfig) {
        ec2Props.domainConfig = props.domainConfig;
      }
      
      deployment = new EC2Deployment(this, 'EC2Deployment', ec2Props);
    } else {
      // Create ECS cluster
      const cluster = new ecs.Cluster(this, 'ECSCluster', {
        vpc: this.vpc,
        containerInsights: props.environment === 'production',
      });
      
      const ecsProps: any = {
        vpc: this.vpc,
        cluster: cluster,
        cpu: props.computeConfig?.cpu || 2048,
        memory: props.computeConfig?.memory || 4096,
        desiredCount: props.computeConfig?.desiredCount || 2,
        storage: storage,
        database: database,
        appSecrets: appSecrets,
        environment: props.environment,
        enableRag: props.enableRag || false,
        enableMeilisearch: props.enableMeilisearch || false,
      };
      
      if (props.domainConfig) {
        ecsProps.domainConfig = props.domainConfig;
      }
      
      deployment = new ECSDeployment(this, 'ECSDeployment', ecsProps);
    }
    
    this.loadBalancerUrl = deployment.loadBalancerUrl;
    
    // Create monitoring resources
    if (props.alertEmail || props.enableEnhancedMonitoring) {
      const monitoringProps: any = {
        deployment: deployment,
        database: database,
        environment: props.environment,
        enableEnhancedMonitoring: props.enableEnhancedMonitoring || false,
      };
      
      if (props.alertEmail) {
        monitoringProps.alertEmail = props.alertEmail;
      }
      
      new MonitoringConstruct(this, 'Monitoring', monitoringProps);
    }
    
    // Create outputs
    this.createOutputs(deployment, database);
    
    // Apply tags
    this.applyTags(props);
  }
  
  private validateProps(props: LibreChatStackProps): void {
    if (!props.deploymentMode) {
      throw new Error('deploymentMode is required');
    }
    
    if (!props.environment) {
      throw new Error('environment is required');
    }
    
    if (props.deploymentMode === 'EC2' && !props.keyPairName) {
      throw new Error('keyPairName is required for EC2 deployment');
    }
    
    if (props.domainConfig && !props.domainConfig.domainName) {
      throw new Error('domainName is required when domainConfig is provided');
    }
  }
  
  private getDefaultInstanceClass(environment: string): string {
    switch (environment) {
      case 'production':
        return 'db.r6g.large';
      case 'staging':
        return 'db.t3.medium';
      default:
        return 'db.t3.small';
    }
  }
  
  private createApplicationSecrets(): secretsmanager.ISecret {
    return new secretsmanager.Secret(this, 'AppSecrets', {
      description: 'LibreChat application secrets',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({}),
        generateStringKey: 'jwt_secret',
        excludeCharacters: ' %+~`#$&*()|[]{}:;<>?!\'/@"\\',
        passwordLength: 32,
      },
    });
  }
  
  private createOutputs(deployment: EC2Deployment | ECSDeployment, _database: DatabaseConstruct): void {
    new cdk.CfnOutput(this, 'LoadBalancerURL', {
      value: this.loadBalancerUrl,
      description: 'URL to access LibreChat',
      exportName: `${cdk.Stack.of(this).stackName}-LoadBalancerURL`,
    });
    
    new cdk.CfnOutput(this, 'DeploymentMode', {
      value: deployment instanceof EC2Deployment ? 'EC2' : 'ECS',
      description: 'Deployment mode used',
    });
    
    Object.entries(this.databaseEndpoints).forEach(([name, endpoint]) => {
      new cdk.CfnOutput(this, `${name}Endpoint`, {
        value: endpoint,
        description: `${name} database endpoint`,
        exportName: `${cdk.Stack.of(this).stackName}-${name}Endpoint`,
      });
    });
    
    new cdk.CfnOutput(this, 'VPCId', {
      value: this.vpc.vpcId,
      description: 'VPC ID',
      exportName: `${cdk.Stack.of(this).stackName}-VPCId`,
    });
  }
  
  private applyTags(props: LibreChatStackProps): void {
    cdk.Tags.of(this).add('Application', 'LibreChat');
    cdk.Tags.of(this).add('Environment', props.environment);
    cdk.Tags.of(this).add('DeploymentMode', props.deploymentMode);
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('CostCenter', 'AI-Platform');
  }
}
