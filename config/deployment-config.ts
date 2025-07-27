import { LibreChatStackProps } from '../lib/librechat-stack';
import { getResourceSizeFromEnv, ResourceSize } from './resource-sizes';

// Environment-specific configurations
export const environmentConfigs = {
  development: {
    deploymentMode: 'EC2' as const,
    vpcConfig: {
      useExisting: false,
      cidr: '10.0.0.0/16',
      maxAzs: 2,
      natGateways: 0, // Cost savings for dev
    },
    databaseConfig: {
      engine: 'postgres' as const,
      instanceClass: 'db.t3.small',
      allocatedStorage: 20,
      backupRetentionDays: 1,
    },
    computeConfig: {
      instanceType: 't3.large',
      desiredCount: 1,
      cpu: 1024,
      memory: 2048,
    },
    enableRag: true,
    enableMeilisearch: false,
    enableSharePoint: false,
    enableEnhancedMonitoring: false,
  },
  
  staging: {
    deploymentMode: 'EC2' as const,
    vpcConfig: {
      useExisting: false,
      cidr: '10.1.0.0/16',
      maxAzs: 2,
      natGateways: 1,
    },
    databaseConfig: {
      engine: 'postgres' as const,
      instanceClass: 'db.t3.medium',
      allocatedStorage: 50,
      backupRetentionDays: 7,
    },
    computeConfig: {
      instanceType: 't3.xlarge',
      desiredCount: 1,
      cpu: 2048,
      memory: 4096,
    },
    enableRag: true,
    enableMeilisearch: true,
    enableSharePoint: false,
    enableEnhancedMonitoring: true,
  },
  
  production: {
    deploymentMode: 'ECS' as const,
    vpcConfig: {
      useExisting: false,
      cidr: '10.2.0.0/16',
      maxAzs: 3,
      natGateways: 2,
    },
    databaseConfig: {
      engine: 'postgres-and-documentdb' as const,
      instanceClass: 'db.r6g.large',
      allocatedStorage: 100,
      backupRetentionDays: 30,
    },
    computeConfig: {
      instanceType: 't3.2xlarge',
      desiredCount: 3,
      cpu: 4096,
      memory: 8192,
    },
    enableRag: true,
    enableMeilisearch: true,
    enableSharePoint: true,
    enableEnhancedMonitoring: true,
  },
};

// Default configuration
export const defaultConfig: Partial<LibreChatStackProps> = {
  environment: 'development',
  deploymentMode: 'EC2',
  allowedIps: ['0.0.0.0/0'],
};

// Configuration builder
export class DeploymentConfigBuilder {
  private config: Partial<LibreChatStackProps>;
  
  constructor(environment: keyof typeof environmentConfigs = 'development') {
    this.config = {
      ...defaultConfig,
      ...environmentConfigs[environment],
      environment,
    };
  }
  
  withDeploymentMode(mode: 'EC2' | 'ECS'): this {
    this.config.deploymentMode = mode;
    return this;
  }
  
  withVpc(vpcConfig: LibreChatStackProps['vpcConfig']): this {
    if (vpcConfig) {
      this.config.vpcConfig = vpcConfig;
    }
    return this;
  }
  
  withExistingVpc(vpcId: string): this {
    this.config.vpcConfig = {
      useExisting: true,
      existingVpcId: vpcId,
    };
    return this;
  }
  
  withDomain(domainName: string, certificateArn?: string, hostedZoneId?: string): this {
    const domainConfig: NonNullable<LibreChatStackProps['domainConfig']> = { domainName };
    if (certificateArn !== undefined) {
      domainConfig.certificateArn = certificateArn;
    }
    if (hostedZoneId !== undefined) {
      domainConfig.hostedZoneId = hostedZoneId;
    }
    this.config.domainConfig = domainConfig;
    return this;
  }
  
  withDatabase(databaseConfig: LibreChatStackProps['databaseConfig']): this {
    if (databaseConfig) {
      this.config.databaseConfig = databaseConfig;
    }
    return this;
  }
  
  withCompute(computeConfig: LibreChatStackProps['computeConfig']): this {
    if (computeConfig) {
      this.config.computeConfig = computeConfig;
    }
    return this;
  }
  
  withKeyPair(keyPairName: string): this {
    this.config.keyPairName = keyPairName;
    return this;
  }
  
  withAllowedIps(ips: string[]): this {
    this.config.allowedIps = ips;
    return this;
  }
  
  withAlertEmail(email: string): this {
    this.config.alertEmail = email;
    return this;
  }
  
  withFeatures(features: {
    rag?: boolean;
    meilisearch?: boolean;
    sharePoint?: boolean;
  }): this {
    if (features.rag !== undefined) {
      this.config.enableRag = features.rag;
    }
    if (features.meilisearch !== undefined) {
      this.config.enableMeilisearch = features.meilisearch;
    }
    if (features.sharePoint !== undefined) {
      this.config.enableSharePoint = features.sharePoint;
    }
    return this;
  }
  
  withEnhancedMonitoring(enabled: boolean): this {
    this.config.enableEnhancedMonitoring = enabled;
    return this;
  }
  
  withResourceSize(size: string | ResourceSize): this {
    const resourceSize = typeof size === 'string' ? getResourceSizeFromEnv() : size;
    
    // Apply resource sizes based on deployment mode
    if (this.config.deploymentMode === 'EC2' && this.config.computeConfig) {
      this.config.computeConfig.instanceType = resourceSize.ec2.instanceType;
    } else if (this.config.deploymentMode === 'ECS' && this.config.computeConfig) {
      this.config.computeConfig.cpu = resourceSize.ecs.cpu;
      this.config.computeConfig.memory = resourceSize.ecs.memory;
      this.config.computeConfig.desiredCount = resourceSize.ecs.desiredCount;
    }
    
    // Apply database sizes
    if (this.config.databaseConfig) {
      this.config.databaseConfig.instanceClass = resourceSize.rds.instanceClass;
      this.config.databaseConfig.allocatedStorage = resourceSize.rds.allocatedStorage;
    }
    
    return this;
  }
  
  build(): LibreChatStackProps {
    // Validate required fields
    if (!this.config.environment) {
      throw new Error('Environment is required');
    }
    
    if (!this.config.deploymentMode) {
      throw new Error('Deployment mode is required');
    }
    
    if (this.config.deploymentMode === 'EC2' && !this.config.keyPairName) {
      throw new Error(`
Key pair name is required for EC2 deployment.

To fix this error, you can:

1. Create an EC2 key pair in AWS Console:
   - Go to EC2 > Key Pairs
   - Click "Create key pair"
   - Save the private key file securely

2. Then provide the key pair name using one of these methods:

   a) Using environment variable:
      export KEY_PAIR_NAME=your-key-pair-name
      npm run deploy

   b) Using CDK context:
      npm run deploy -- -c keyPairName=your-key-pair-name

   c) Using .env file:
      echo "KEY_PAIR_NAME=your-key-pair-name" >> .env
      npm run deploy

3. Or switch to ECS deployment mode (no key pair required):
      export DEPLOYMENT_MODE=ECS
      npm run deploy

For examples, see config/development.env.example or config/ecs-deployment.env.example
`);
    }
    
    return this.config as LibreChatStackProps;
  }
}

// Preset configurations for common scenarios
export const presetConfigs = {
  // Minimal development setup
  minimalDev: new DeploymentConfigBuilder('development')
    .withFeatures({ rag: false, meilisearch: false })
    .withCompute({ instanceType: 't3.medium' }),
  
  // Standard development setup
  standardDev: new DeploymentConfigBuilder('development')
    .withFeatures({ rag: true, meilisearch: false }),
  
  // Full-featured development
  fullDev: new DeploymentConfigBuilder('development')
    .withFeatures({ rag: true, meilisearch: true })
    .withCompute({ instanceType: 't3.xlarge' }),
  
  // Production EC2 (cost-optimized)
  productionEC2: new DeploymentConfigBuilder('production')
    .withDeploymentMode('EC2')
    .withCompute({ instanceType: 't3.xlarge' })
    .withDatabase({
      engine: 'postgres',
      instanceClass: 'db.t3.medium',
      allocatedStorage: 100,
      backupRetentionDays: 7,
    }),
  
  // Production ECS (scalable)
  productionECS: new DeploymentConfigBuilder('production')
    .withDeploymentMode('ECS')
    .withCompute({
      desiredCount: 3,
      cpu: 4096,
      memory: 8192,
    }),
  
  // Enterprise production
  enterprise: new DeploymentConfigBuilder('production')
    .withDeploymentMode('ECS')
    .withDatabase({
      engine: 'postgres-and-documentdb',
      instanceClass: 'db.r6g.xlarge',
      allocatedStorage: 500,
      backupRetentionDays: 30,
    })
    .withCompute({
      desiredCount: 5,
      cpu: 8192,
      memory: 16384,
    })
    .withFeatures({
      rag: true,
      meilisearch: true,
      sharePoint: true,
    })
    .withEnhancedMonitoring(true),
};

// Export helper function to get config from environment
export function getConfigFromEnvironment(): LibreChatStackProps {
  const env = process.env.DEPLOYMENT_ENV || 'development';
  const mode = process.env.DEPLOYMENT_MODE as 'EC2' | 'ECS' | undefined;
  
  const builder = new DeploymentConfigBuilder(env as keyof typeof environmentConfigs);
  
  // Override deployment mode if specified in environment
  if (mode) {
    builder.withDeploymentMode(mode);
  }
  
  // Apply resource size if specified
  if (process.env.RESOURCE_SIZE || process.env.FAST_DEPLOY) {
    builder.withResourceSize(process.env.RESOURCE_SIZE || 'medium');
  }
  
  // Apply environment variables
  if (process.env.KEY_PAIR_NAME) {
    builder.withKeyPair(process.env.KEY_PAIR_NAME);
  }
  
  if (process.env.ALERT_EMAIL) {
    builder.withAlertEmail(process.env.ALERT_EMAIL);
  }
  
  if (process.env.ALLOWED_IPS) {
    builder.withAllowedIps(process.env.ALLOWED_IPs.split(','));
  }
  
  if (process.env.DOMAIN_NAME) {
    builder.withDomain(
      process.env.DOMAIN_NAME,
      process.env.CERTIFICATE_ARN,
      process.env.HOSTED_ZONE_ID
    );
  }
  
  if (process.env.EXISTING_VPC_ID) {
    builder.withExistingVpc(process.env.EXISTING_VPC_ID);
  }
  
  return builder.build();
}
