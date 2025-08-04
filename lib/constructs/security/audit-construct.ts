import * as cdk from 'aws-cdk-lib';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

export interface AuditConstructProps {
  environment: string;
  enableHipaaCompliance?: boolean;
  auditRetentionDays?: number;
  enableDataEvents?: boolean;
}

export class AuditConstruct extends Construct {
  public readonly auditBucket: s3.Bucket;
  public readonly encryptionKey: kms.Key;
  public readonly trail: cloudtrail.Trail;

  constructor(scope: Construct, id: string, props: AuditConstructProps) {
    super(scope, id);

    // Master encryption key with automatic rotation
    this.encryptionKey = new kms.Key(this, 'AuditEncryptionKey', {
      enableKeyRotation: true,
      description: `LibreChat Audit Encryption Key - ${props.environment}`,
      alias: `alias/librechat-audit-${props.environment}`,
      removalPolicy:
        props.environment === 'production' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
      pendingWindow: cdk.Duration.days(30),
    });

    // Grant CloudTrail service access to the key
    this.encryptionKey.grant(
      new iam.ServicePrincipal('cloudtrail.amazonaws.com'),
      'kms:GenerateDataKey',
      'kms:DescribeKey'
    );

    // Grant CloudWatch Logs service access to the key
    this.encryptionKey.grant(
      new iam.ServicePrincipal('logs.amazonaws.com'),
      'kms:Encrypt',
      'kms:Decrypt',
      'kms:ReEncrypt*',
      'kms:GenerateDataKey*',
      'kms:DescribeKey'
    );

    // Audit bucket with encryption and lifecycle
    this.auditBucket = new s3.Bucket(this, 'AuditBucket', {
      bucketName: `librechat-audit-${cdk.Stack.of(this).account}-${props.environment}-${cdk.Stack.of(this).region}`,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: this.encryptionKey,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      lifecycleRules: [
        {
          id: 'ArchiveOldLogs',
          transitions: [
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
          expiration: props.enableHipaaCompliance
            ? cdk.Duration.days(2555) // 7 years for HIPAA
            : cdk.Duration.days(props.auditRetentionDays || 365),
        },
      ],
      serverAccessLogsPrefix: 'access-logs/',
      removalPolicy: 
        props.environment === 'production' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: props.environment !== 'production',
    });

    // Create CloudWatch log group for CloudTrail
    const logGroup = new logs.LogGroup(this, 'AuditLogGroup', {
      logGroupName: `/aws/cloudtrail/librechat-${props.environment}`,
      retention: props.enableHipaaCompliance
        ? logs.RetentionDays.TWO_YEARS
        : logs.RetentionDays.ONE_YEAR,
      encryptionKey: this.encryptionKey,
      removalPolicy:
        props.environment === 'production' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
    });

    // Create IAM role for CloudTrail
    const cloudTrailRole = new iam.Role(this, 'CloudTrailRole', {
      assumedBy: new iam.ServicePrincipal('cloudtrail.amazonaws.com'),
      description: 'Role for CloudTrail to write to CloudWatch Logs',
    });

    // Grant CloudTrail permissions to write to CloudWatch Logs
    cloudTrailRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['logs:CreateLogStream', 'logs:PutLogEvents'],
        resources: [logGroup.logGroupArn],
      })
    );

    // CloudTrail with data events
    this.trail = new cloudtrail.Trail(this, 'AuditTrail', {
      bucket: this.auditBucket,
      encryptionKey: this.encryptionKey,
      sendToCloudWatchLogs: true,
      cloudWatchLogGroup: logGroup,
      cloudWatchLogsRetention: props.enableHipaaCompliance
        ? logs.RetentionDays.TWO_YEARS
        : logs.RetentionDays.ONE_YEAR,
      includeGlobalServiceEvents: true,
      isMultiRegionTrail: true,
      enableFileValidation: true,
      trailName: `librechat-audit-trail-${props.environment}`,
      insightTypes: [cloudtrail.InsightType.API_CALL_RATE, cloudtrail.InsightType.API_ERROR_RATE],
    });

    // Log S3 data events for HIPAA compliance
    if (props.enableDataEvents || props.enableHipaaCompliance) {
      // Add S3 data events
      this.trail.addEventSelector(
        cloudtrail.DataResourceType.S3_OBJECT,
        ['arn:aws:s3:::librechat-*/*'], // Monitor all LibreChat buckets
        {
          readWriteType: cloudtrail.ReadWriteType.ALL,
          includeManagementEvents: true,
        }
      );

      // Add Lambda function invocations
      this.trail.addEventSelector(
        cloudtrail.DataResourceType.LAMBDA_FUNCTION,
        ['arn:aws:lambda:*:*:function/LibreChat*'],
        {
          readWriteType: cloudtrail.ReadWriteType.ALL,
          includeManagementEvents: false,
        }
      );
    }

    // Add tags for compliance
    cdk.Tags.of(this).add('Compliance', 'Audit');
    cdk.Tags.of(this).add('Purpose', 'Security-Monitoring');
    cdk.Tags.of(this).add('DataClassification', 'Sensitive');

    // Output trail ARN for compliance reporting
    new cdk.CfnOutput(this, 'CloudTrailArn', {
      value: this.trail.trailArn,
      description: 'CloudTrail ARN for compliance reporting',
      exportName: `${cdk.Stack.of(this).stackName}-CloudTrailArn`,
    });

    // Output audit bucket ARN
    new cdk.CfnOutput(this, 'AuditBucketArn', {
      value: this.auditBucket.bucketArn,
      description: 'Audit bucket ARN for compliance reporting',
      exportName: `${cdk.Stack.of(this).stackName}-AuditBucketArn`,
    });
  }
}
