import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
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
  public fileSystem?: efs.FileSystem;
  public readonly accessPoints: { [key: string]: efs.AccessPoint } = {};
  private efsSecurityGroup?: ec2.SecurityGroup;
  
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
    // Generate a unique bucket name using stack name and account/region
    const stackName = cdk.Stack.of(this).stackName.toLowerCase();
    const account = cdk.Stack.of(this).account;
    const region = cdk.Stack.of(this).region;
    
    const bucket = new s3.Bucket(this, 'DocumentBucket', {
      bucketName: `${stackName}-docs-${account}-${region}`,
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
    new s3deploy.BucketDeployment(this, 'CreateFolders', {
      sources: [s3deploy.Source.data('uploads/.keep', ''), s3deploy.Source.data('documents/.keep', '')],
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
    
    // Create security group for EFS
    this.efsSecurityGroup = new ec2.SecurityGroup(this, 'EfsSecurityGroup', {
      vpc: props.vpc,
      description: 'Security group for EFS mount targets',
      allowAllOutbound: true,  // Allow outbound for EFS to communicate with AWS services
    });
    
    // Create EFS file system
    this.fileSystem = new efs.FileSystem(this, 'SharedFileSystem', {
      vpc: props.vpc,
      securityGroup: this.efsSecurityGroup,
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
  
  /**
   * Allow an ECS service to mount the EFS file system
   */
  public allowEfsMount(securityGroup: ec2.ISecurityGroup): void {
    if (this.efsSecurityGroup) {
      this.efsSecurityGroup.addIngressRule(
        securityGroup,
        ec2.Port.tcp(2049),
        'Allow NFS traffic from ECS service'
      );
    }
  }
}
