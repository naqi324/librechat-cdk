import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * Utility functions for creating least-privilege IAM policies
 */

export interface BedrockPolicyOptions {
  /**
   * AWS region for the resources
   */
  region: string;
  /**
   * List of model families to allow access to
   * @default ['anthropic.claude-*', 'amazon.titan-*', 'meta.llama*', 'mistral.*']
   */
  modelFamilies?: string[];
}

/**
 * Create least-privilege IAM policy statements for Bedrock access
 */
export function createBedrockPolicyStatements(
  options: BedrockPolicyOptions
): iam.PolicyStatement[] {
  const {
    region,
    modelFamilies = ['anthropic.claude-*', 'amazon.titan-*', 'meta.llama*', 'mistral.*'],
  } = options;

  const statements: iam.PolicyStatement[] = [];

  // Model invocation permissions - restricted to specific model families
  statements.push(
    new iam.PolicyStatement({
      sid: 'BedrockModelInvocation',
      effect: iam.Effect.ALLOW,
      actions: ['bedrock:InvokeModel', 'bedrock:InvokeModelWithResponseStream'],
      resources: modelFamilies.map(
        (family) => `arn:aws:bedrock:${region}::foundation-model/${family}`
      ),
      conditions: {
        StringEquals: {
          'aws:RequestedRegion': region,
        },
      },
    })
  );

  // Read-only operations that require wildcard but are low risk
  statements.push(
    new iam.PolicyStatement({
      sid: 'BedrockReadOnly',
      effect: iam.Effect.ALLOW,
      actions: ['bedrock:ListFoundationModels', 'bedrock:GetFoundationModel'],
      resources: ['*'], // These actions don't support resource restrictions
      conditions: {
        StringEquals: {
          'aws:RequestedRegion': region,
        },
      },
    })
  );

  return statements;
}

export interface S3PolicyOptions {
  /**
   * S3 bucket ARN
   */
  bucketArn: string;
  /**
   * Whether to allow delete operations
   * @default false
   */
  allowDelete?: boolean;
  /**
   * Whether to require encryption
   * @default true
   */
  requireEncryption?: boolean;
}

/**
 * Create least-privilege IAM policy statements for S3 access
 */
export function createS3PolicyStatements(options: S3PolicyOptions): iam.PolicyStatement[] {
  const { bucketArn, allowDelete = false, requireEncryption = true } = options;

  const statements: iam.PolicyStatement[] = [];

  // Object operations
  const objectActions = ['s3:GetObject', 's3:GetObjectVersion', 's3:PutObject'];

  if (allowDelete) {
    objectActions.push('s3:DeleteObject', 's3:DeleteObjectVersion');
  }

  const objectStatement = new iam.PolicyStatement({
    sid: 'S3ObjectAccess',
    effect: iam.Effect.ALLOW,
    actions: objectActions,
    resources: [`${bucketArn}/*`],
  });

  if (requireEncryption) {
    objectStatement.addConditions({
      StringEquals: {
        's3:x-amz-server-side-encryption': 'AES256',
      },
    });
  }

  statements.push(objectStatement);

  // Bucket operations
  statements.push(
    new iam.PolicyStatement({
      sid: 'S3BucketAccess',
      effect: iam.Effect.ALLOW,
      actions: [
        's3:ListBucket',
        's3:GetBucketLocation',
        's3:GetBucketVersioning',
        's3:ListBucketVersions',
      ],
      resources: [bucketArn],
    })
  );

  return statements;
}

export interface SecretsPolicyOptions {
  /**
   * List of secret ARNs to grant access to
   */
  secretArns: string[];
  /**
   * Whether to allow updating secrets
   * @default false
   */
  allowUpdate?: boolean;
}

/**
 * Create least-privilege IAM policy statements for Secrets Manager access
 */
export function createSecretsManagerPolicyStatements(
  options: SecretsPolicyOptions
): iam.PolicyStatement[] {
  const { secretArns, allowUpdate = false } = options;

  const actions = ['secretsmanager:GetSecretValue', 'secretsmanager:DescribeSecret'];

  if (allowUpdate) {
    actions.push('secretsmanager:UpdateSecret', 'secretsmanager:PutSecretValue');
  }

  return [
    new iam.PolicyStatement({
      sid: 'SecretsManagerAccess',
      effect: iam.Effect.ALLOW,
      actions,
      resources: secretArns,
      conditions: {
        StringEquals: {
          'secretsmanager:VersionStage': 'AWSCURRENT',
        },
      },
    }),
  ];
}

/**
 * Create a condition that restricts access to specific source IPs
 */
export function createIpRestrictionCondition(allowedIps: string[]): Record<string, unknown> {
  return {
    IpAddress: {
      'aws:SourceIp': allowedIps,
    },
  };
}

/**
 * Create a condition that requires MFA
 */
export function createMfaCondition(): Record<string, unknown> {
  return {
    Bool: {
      'aws:MultiFactorAuthPresent': 'true',
    },
  };
}

/**
 * Create a condition that restricts access to specific VPC endpoints
 */
export function createVpcEndpointCondition(vpcEndpointIds: string[]): Record<string, unknown> {
  return {
    StringEquals: {
      'aws:SourceVpce': vpcEndpointIds,
    },
  };
}
