/**
 * Predefined resource size configurations for LibreChat deployment
 */

export interface ResourceSize {
  name: string;
  description: string;
  ec2: {
    instanceType: string;
    volumeSize: number;
  };
  ecs: {
    cpu: number;
    memory: number;
    desiredCount: number;
    minCount: number;
    maxCount: number;
  };
  rds: {
    instanceClass: string;
    allocatedStorage: number;
    maxAllocatedStorage?: number;
    multiAz: boolean;
  };
  documentdb?: {
    instanceClass: string;
    instanceCount: number;
  };
  estimatedMonthlyCost: number;
}

type ResourceSizeKey = 'xs' | 'small' | 'medium' | 'large' | 'xl' | 'fast-deploy';

export const RESOURCE_SIZES: Record<ResourceSizeKey, ResourceSize> = {
  // Minimal - for testing and development
  xs: {
    name: 'Extra Small',
    description: 'Minimal resources for testing (1-5 users)',
    ec2: {
      instanceType: 't3.micro',
      volumeSize: 20,
    },
    ecs: {
      cpu: 256,
      memory: 512,
      desiredCount: 1,
      minCount: 1,
      maxCount: 2,
    },
    rds: {
      instanceClass: 'db.t3.micro',
      allocatedStorage: 20,
      multiAz: false,
    },
    documentdb: {
      instanceClass: 'db.t3.medium', // Minimum supported for DocumentDB
      instanceCount: 1,
    },
    estimatedMonthlyCost: 50,
  },

  // Small - for small teams
  small: {
    name: 'Small',
    description: 'Light workloads (5-20 users)',
    ec2: {
      instanceType: 't3.small',
      volumeSize: 50,
    },
    ecs: {
      cpu: 512,
      memory: 1024,
      desiredCount: 1,
      minCount: 1,
      maxCount: 3,
    },
    rds: {
      instanceClass: 'db.t3.small', // For RDS PostgreSQL
      allocatedStorage: 50,
      maxAllocatedStorage: 100,
      multiAz: false,
    },
    documentdb: {
      instanceClass: 'db.t3.medium', // Minimum supported for DocumentDB
      instanceCount: 1,
    },
    estimatedMonthlyCost: 120,
  },

  // Medium - default for most deployments
  medium: {
    name: 'Medium',
    description: 'Standard workloads (20-100 users)',
    ec2: {
      instanceType: 't3.large',
      volumeSize: 100,
    },
    ecs: {
      cpu: 1024,
      memory: 2048,
      desiredCount: 2,
      minCount: 1,
      maxCount: 5,
    },
    rds: {
      instanceClass: 'db.t3.medium',
      allocatedStorage: 100,
      maxAllocatedStorage: 200,
      multiAz: false,
    },
    documentdb: {
      instanceClass: 'db.t3.medium',
      instanceCount: 1,
    },
    estimatedMonthlyCost: 300,
  },

  // Large - for bigger teams
  large: {
    name: 'Large',
    description: 'Heavy workloads (100-500 users)',
    ec2: {
      instanceType: 't3.xlarge',
      volumeSize: 200,
    },
    ecs: {
      cpu: 2048,
      memory: 4096,
      desiredCount: 3,
      minCount: 2,
      maxCount: 10,
    },
    rds: {
      instanceClass: 'db.r6g.large',
      allocatedStorage: 200,
      maxAllocatedStorage: 500,
      multiAz: true,
    },
    documentdb: {
      instanceClass: 'db.r5.large',
      instanceCount: 2,
    },
    estimatedMonthlyCost: 800,
  },

  // Extra Large - for enterprise
  xl: {
    name: 'Extra Large',
    description: 'Enterprise workloads (500+ users)',
    ec2: {
      instanceType: 't3.2xlarge',
      volumeSize: 500,
    },
    ecs: {
      cpu: 4096,
      memory: 8192,
      desiredCount: 5,
      minCount: 3,
      maxCount: 20,
    },
    rds: {
      instanceClass: 'db.r6g.xlarge',
      allocatedStorage: 500,
      maxAllocatedStorage: 1000,
      multiAz: true,
    },
    documentdb: {
      instanceClass: 'db.r5.xlarge',
      instanceCount: 3,
    },
    estimatedMonthlyCost: 2000,
  },

  // Custom preset for fastest deployment
  'fast-deploy': {
    name: 'Fast Deploy',
    description: 'Optimized for quickest deployment time',
    ec2: {
      instanceType: 't3.micro',
      volumeSize: 20,
    },
    ecs: {
      cpu: 256,
      memory: 512,
      desiredCount: 1,
      minCount: 1,
      maxCount: 1,
    },
    rds: {
      instanceClass: 'db.t3.micro',
      allocatedStorage: 20,
      multiAz: false,
    },
    documentdb: {
      instanceClass: 'db.t3.medium', // Minimum supported for DocumentDB
      instanceCount: 1,
    },
    estimatedMonthlyCost: 40,
  },
};

/**
 * Get resource size configuration
 */
export function getResourceSize(size: string): ResourceSize {
  // Check if the size is a valid key
  if (size in RESOURCE_SIZES) {
    return RESOURCE_SIZES[size as ResourceSizeKey];
  }

  // Fallback to medium
  return RESOURCE_SIZES['medium'];
}

/**
 * Get resource size from environment
 */
export function getResourceSizeFromEnv(): ResourceSize {
  const size = process.env.RESOURCE_SIZE || 'medium';
  const fastDeploy = process.env.FAST_DEPLOY === 'true';

  if (fastDeploy) {
    return RESOURCE_SIZES['fast-deploy'];
  }

  return getResourceSize(size);
}
