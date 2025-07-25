import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as efs from 'aws-cdk-lib/aws-efs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

export interface StorageConstructProps {
  environment: string;
  enableEfs?: boolean;
  vpc?: ec2.IVpc;
}

export class StorageConstruct extends Construct {
  public readonly s3Bucket: s3.Bucket;
  public readonly fileSystem?: efs.FileSystem;
  public readonly accessPoints: { [key: string]: efs.AccessPoint } = {};
  
  constructor(scope: Construct, id: string, props: StorageConstructProps) {
    super(scope, id);
    
    // Create S3 bucket for documents and uploads
    this.s3Bucket = this.createS3Bucket(props);
    
    // Create EFS for container shared storage (if enabled)
    if (props.enableEfs && props.vpc) {
      this.createEfsStorage(props);
    }
  }
  
  private createS3Bucket(props: StorageConstructProps): s3.Bucket {
    const bucket = new s3.Bucket(this, 'DocumentBucket', {
      bucketName: `librechat-${props.environment}-${cdk.Stack.of(this).account}-${cdk.Stack.of(this).region}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      lifecycleRules: [
        {
          id: 'delete-old-versions',
          noncurrentVersionExpiration: cdk.Duration.days(30),
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
        {
          id: 'transition-to-ia',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER_INSTANT_RETRIEVAL,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
        },
      ],
      cors: [
        {
          allowedOrigins: ['*'],
          allowedMethods: [
            s3.HttpMethods.GET,
            s3.HttpMethods.PUT,
            s3.HttpMethods.POST,
            s3.HttpMethods.DELETE,
            s3.HttpMethods.HEAD,
          ],
          allowedHeaders: ['*'],
          exposedHeaders: ['ETag'],
          maxAge: 3000,
        },
      ],
      removalPolicy: props.environment === 'production' 
        ? cdk.RemovalPolicy.RETAIN 
        : cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: props.environment !== 'production',
    });
    
    // Add bucket policy for secure access
    bucket.addToResourcePolicy(new iam.PolicyStatement({
      effect: iam.Effect.DENY,
      principals: [new iam.AnyPrincipal()],
      actions: ['s3:*'],
      resources: [
        bucket.bucketArn,
        `${bucket.bucketArn}/*`,
      ],
      conditions: {
        Bool: {
          'aws:SecureTransport': 'false',
        },
      },
    }));
    
    // Create folder structure
    new s3.BucketDeployment(this, 'CreateFolders', {
      sources: [s3.Source.data('uploads/.keep', ''), s3.Source.data('documents/.keep', '')],
      destinationBucket: bucket,
      retainOnDelete: false,
    });
    
    // Add tags
    cdk.Tags.of(bucket).add('Purpose', 'LibreChat-Storage');
    cdk.Tags.of(bucket).add('Environment', props.environment);
    
    return bucket;
  }
  
  private createEfsStorage(props: StorageConstructProps): void {
    if (!props.vpc) {
      throw new Error('VPC is required for EFS storage');
    }
    
    // Create EFS file system
    this.fileSystem = new efs.FileSystem(this, 'SharedFileSystem', {
      vpc: props.vpc,
      performanceMode: efs.PerformanceMode.GENERAL_PURPOSE,
      throughputMode: efs.ThroughputMode.ELASTIC,
      lifecyclePolicy: efs.LifecyclePolicy.AFTER_30_DAYS,
      outOfInfrequentAccessPolicy: efs.OutOfInfrequentAccessPolicy.AFTER_1_ACCESS,
      encrypted: true,
      enableAutomaticBackups: props.environment === 'production',
      removalPolicy: props.environment === 'production' 
        ? cdk.RemovalPolicy.RETAIN 
        : cdk.RemovalPolicy.DESTROY,
    });
    
    // Create access points for different services
    this.createAccessPoints();
    
    // Add tags
    cdk.Tags.of(this.fileSystem).add('Purpose', 'LibreChat-SharedStorage');
    cdk.Tags.of(this.fileSystem).add('Environment', props.environment);
  }
  
  private createAccessPoints(): void {
    if (!this.fileSystem) {
      return;
    }
    
    // Access point for LibreChat uploads
    this.accessPoints['librechat-uploads'] = this.fileSystem.addAccessPoint('LibreChatUploadsAP', {
      path: '/librechat/uploads',
      createAcl: {
        ownerGid: '1000',
        ownerUid: '1000',
        permissions: '755',
      },
      posixUser: {
        gid: '1000',
        uid: '1000',
      },
    });
    
    // Access point for Meilisearch data
    this.accessPoints['meilisearch'] = this.fileSystem.addAccessPoint('MeilisearchAP', {
      path: '/meilisearch/data',
      createAcl: {
        ownerGid: '1001',
        ownerUid: '1001',
        permissions: '755',
      },
      posixUser: {
        gid: '1001',
        uid: '1001',
      },
    });
    
    // Access point for shared configuration
    this.accessPoints['config'] = this.fileSystem.addAccessPoint('ConfigAP', {
      path: '/shared/config',
      createAcl: {
        ownerGid: '0',
        ownerUid: '0',
        permissions: '755',
      },
      posixUser: {
        gid: '0',
        uid: '0',
      },
    });
    
    // Access point for logs
    this.accessPoints['logs'] = this.fileSystem.addAccessPoint('LogsAP', {
      path: '/shared/logs',
      createAcl: {
        ownerGid: '0',
        ownerUid: '0',
        permissions: '755',
      },
      posixUser: {
        gid: '0',
        uid: '0',
      },
    });
  }
  
  public grantReadWrite(grantee: iam.IGrantable): void {
    // Grant S3 permissions
    this.s3Bucket.grantReadWrite(grantee);
    
    // Grant EFS permissions if enabled
    if (this.fileSystem) {
      this.fileSystem.grant(grantee, 
        'elasticfilesystem:ClientMount',
        'elasticfilesystem:ClientWrite',
        'elasticfilesystem:ClientRootAccess'
      );
    }
  }
}
