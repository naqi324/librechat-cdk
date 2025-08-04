import * as cdk from 'aws-cdk-lib';
import * as config from 'aws-cdk-lib/aws-config';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as kms from 'aws-cdk-lib/aws-kms';
import { Construct } from 'constructs';

export interface ComplianceConstructProps {
  environment: string;
  enableHipaaCompliance: boolean;
  encryptionKey?: kms.IKey;
}

export class ComplianceConstruct extends Construct {
  public readonly configBucket?: s3.Bucket;
  public readonly configRecorder?: config.CfnConfigurationRecorder;

  constructor(scope: Construct, id: string, props: ComplianceConstructProps) {
    super(scope, id);

    if (!props.enableHipaaCompliance) {
      return;
    }

    // S3 bucket for AWS Config
    const uniqueSuffix = Date.now().toString(36).slice(-4);
    this.configBucket = new s3.Bucket(this, 'ConfigBucket', {
      bucketName: `lc-config-${cdk.Stack.of(this).account}-${props.environment.slice(0, 3)}-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: props.encryptionKey,
      versioned: props.environment === 'production',
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'delete-old-configs',
          transitions: [
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
          expiration: cdk.Duration.days(2555), // 7 years for HIPAA
        },
      ],
      removalPolicy:
        props.environment === 'production' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: props.environment !== 'production',
    });

    // AWS Config delivery channel
    const deliveryChannel = new config.CfnDeliveryChannel(this, 'ConfigDeliveryChannel', {
      name: `librechat-config-${props.environment}`,
      s3BucketName: this.configBucket.bucketName,
      configSnapshotDeliveryProperties: {
        deliveryFrequency: 'TwentyFour_Hours',
      },
    });

    // AWS Config service role
    const configRole = new iam.Role(this, 'ConfigRole', {
      assumedBy: new iam.ServicePrincipal('config.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/ConfigRole'),
      ],
    });

    // Allow Config to write to S3 bucket
    this.configBucket.grantWrite(configRole);

    // Configuration recorder
    this.configRecorder = new config.CfnConfigurationRecorder(this, 'ConfigRecorder', {
      name: `librechat-recorder-${props.environment}`,
      roleArn: configRole.roleArn,
      recordingGroup: {
        allSupported: true,
        includeGlobalResourceTypes: true,
      },
    });

    this.configRecorder.node.addDependency(deliveryChannel);

    // HIPAA-specific Config rules
    this.createHipaaConfigRules();

    // Add compliance tags
    cdk.Tags.of(this).add('Purpose', 'HIPAA-Eligible');
    cdk.Tags.of(this).add('DataClassification', 'PHI');
    cdk.Tags.of(this).add('Compliance', 'HIPAA');
  }

  private createHipaaConfigRules(): void {
    // Encryption at rest rules
    new config.ManagedRule(this, 'S3BucketServerSideEncryptionEnabled', {
      identifier: config.ManagedRuleIdentifiers.S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED,
      description: 'Ensure S3 buckets have encryption enabled',
    });

    new config.ManagedRule(this, 'RdsStorageEncrypted', {
      identifier: config.ManagedRuleIdentifiers.RDS_STORAGE_ENCRYPTED,
      description: 'Ensure RDS instances have encryption enabled',
    });

    new config.ManagedRule(this, 'EbsEncryptedVolumes', {
      identifier: config.ManagedRuleIdentifiers.EBS_ENCRYPTED_VOLUMES,
      description: 'Ensure EBS volumes are encrypted',
    });

    // Access control rules
    new config.ManagedRule(this, 'IamPasswordPolicy', {
      identifier: config.ManagedRuleIdentifiers.IAM_PASSWORD_POLICY,
      description: 'Ensure IAM password policy meets requirements',
      inputParameters: {
        RequireUppercaseCharacters: 'true',
        RequireLowercaseCharacters: 'true',
        RequireSymbols: 'true',
        RequireNumbers: 'true',
        MinimumPasswordLength: '14',
      },
    });

    new config.ManagedRule(this, 'IamUserMfaEnabled', {
      identifier: config.ManagedRuleIdentifiers.IAM_USER_MFA_ENABLED,
      description: 'Ensure IAM users have MFA enabled',
    });

    // Network security rules
    new config.ManagedRule(this, 'SecurityGroupSshRestricted', {
      identifier: 'INCOMING_SSH_DISABLED',
      description: 'Ensure security groups restrict SSH access',
    });

    new config.ManagedRule(this, 'VpcFlowLogsEnabled', {
      identifier: config.ManagedRuleIdentifiers.VPC_FLOW_LOGS_ENABLED,
      description: 'Ensure VPC Flow Logs are enabled',
    });

    // Audit and logging rules
    new config.ManagedRule(this, 'CloudTrailEnabled', {
      identifier: config.ManagedRuleIdentifiers.CLOUD_TRAIL_ENABLED,
      description: 'Ensure CloudTrail is enabled',
    });

    new config.ManagedRule(this, 'CloudWatchLogGroupEncrypted', {
      identifier: config.ManagedRuleIdentifiers.CLOUDWATCH_LOG_GROUP_ENCRYPTED,
      description: 'Ensure CloudWatch Log Groups are encrypted',
    });
  }
}