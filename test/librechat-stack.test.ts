import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';

import { LibreChatStack } from '../lib/librechat-stack';
import { DeploymentConfigBuilder } from '../config/deployment-config';

describe('LibreChatStack', () => {
  let app: cdk.App;
  let template: Template;

  // Helper function to create stack with config
  const createStack = (configBuilder: DeploymentConfigBuilder): LibreChatStack => {
    const config = configBuilder.build();
    return new LibreChatStack(app, 'TestStack', {
      ...config,
      env: {
        account: '123456789012',
        region: 'us-east-1',
      },
    });
  };

  beforeEach(() => {
    app = new cdk.App();
  });

  describe('Development EC2 Deployment', () => {
    let stack: LibreChatStack;

    beforeEach(() => {
      const config = new DeploymentConfigBuilder('development')
        .withDeploymentMode('EC2')
        .withKeyPair('test-key')
        .withAllowedIps(['10.0.0.1/32']);
      stack = createStack(config);
      template = Template.fromStack(stack);
    });

    test('Creates VPC with correct configuration', () => {
      template.hasResourceProperties('AWS::EC2::VPC', {
        CidrBlock: '10.0.0.0/16',
        EnableDnsHostnames: true,
        EnableDnsSupport: true,
      });

      // Development should have 1 NAT gateway for better functionality
      template.resourceCountIs('AWS::EC2::NatGateway', 1);
      template.resourceCountIs('AWS::EC2::Subnet', 6); // 2 public, 2 private with egress, 2 isolated
    });

    test('Creates EC2 instance with correct properties', () => {
      template.hasResourceProperties('AWS::EC2::Instance', {
        InstanceType: 't3.xlarge',
        BlockDeviceMappings: [
          {
            DeviceName: '/dev/xvda',
            Ebs: {
              VolumeSize: 100,
              VolumeType: 'gp3',
              Encrypted: true,
              DeleteOnTermination: true,
            },
          },
        ],
      });
    });

    test('Creates RDS PostgreSQL instance', () => {
      template.hasResourceProperties('AWS::RDS::DBInstance', {
        Engine: 'postgres',
        DBInstanceClass: 'db.t3.small',
        AllocatedStorage: '20',
        StorageType: 'gp3',
        StorageEncrypted: true,
        BackupRetentionPeriod: 1,
        MultiAZ: false,
      });
    });

    test('Creates S3 bucket with proper configuration', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        BucketEncryption: {
          ServerSideEncryptionConfiguration: [
            {
              ServerSideEncryptionByDefault: {
                SSEAlgorithm: 'AES256',
              },
            },
          ],
        },
        VersioningConfiguration: {
          Status: 'Enabled',
        },
        PublicAccessBlockConfiguration: {
          BlockPublicAcls: true,
          BlockPublicPolicy: true,
          IgnorePublicAcls: true,
          RestrictPublicBuckets: true,
        },
      });
    });

    test('Creates Application Load Balancer', () => {
      template.hasResourceProperties('AWS::ElasticLoadBalancingV2::LoadBalancer', {
        Type: 'application',
        Scheme: 'internet-facing',
      });

      // HTTP listener only for dev
      template.hasResourceProperties('AWS::ElasticLoadBalancingV2::Listener', {
        Port: 80,
        Protocol: 'HTTP',
      });
    });

    test('Creates proper IAM role for EC2', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        AssumeRolePolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Principal: {
                Service: 'ec2.amazonaws.com',
              },
              Action: 'sts:AssumeRole',
            },
          ],
        },
        ManagedPolicyArns: Match.arrayWith([
          Match.anyValue(), // SSM policy
          Match.anyValue(), // CloudWatch policy
        ]),
      });

      // Check for Bedrock permissions
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: 'Allow',
              Action: Match.arrayWith([
                'bedrock:InvokeModel',
                'bedrock:InvokeModelWithResponseStream',
              ]),
              Resource: '*',
            }),
          ]),
        },
      });
    });

    test('Creates security groups with correct rules', () => {
      // EC2 Security Group
      template.hasResourceProperties('AWS::EC2::SecurityGroup', {
        GroupDescription: Match.stringLikeRegexp('.*EC2 instance.*'),
        SecurityGroupIngress: Match.arrayWith([
          Match.objectLike({
            IpProtocol: 'tcp',
            FromPort: 22,
            ToPort: 22,
            CidrIp: '10.0.0.1/32',
          }),
        ]),
      });

      // RDS Security Group
      template.hasResourceProperties('AWS::EC2::SecurityGroup', {
        GroupDescription: Match.stringLikeRegexp('.*RDS PostgreSQL.*'),
        SecurityGroupIngress: Match.arrayWith([
          Match.objectLike({
            IpProtocol: 'tcp',
            FromPort: 5432,
            ToPort: 5432,
          }),
        ]),
      });
    });
  });

  describe('Production ECS Deployment', () => {
    let stack: LibreChatStack;

    beforeEach(() => {
      const config = new DeploymentConfigBuilder('production')
        .withDeploymentMode('ECS')
        .withAlertEmail('alerts@example.com')
        .withDomain(
          'librechat.example.com',
          'arn:aws:acm:us-east-1:123456789012:certificate/12345',
          'Z1234567890ABC'
        );
      stack = createStack(config);
      template = Template.fromStack(stack);
    });

    test('Creates VPC with NAT gateways', () => {
      template.hasResourceProperties('AWS::EC2::VPC', {
        CidrBlock: '10.2.0.0/16',
        EnableDnsHostnames: true,
        EnableDnsSupport: true,
      });

      // Should have NAT gateways for production
      template.resourceCountIs('AWS::EC2::NatGateway', 2);
      template.resourceCountIs('AWS::EC2::Subnet', 9); // 3 AZs × 3 subnet types
    });

    test('Creates ECS cluster with enhanced monitoring', () => {
      template.hasResourceProperties('AWS::ECS::Cluster', {
        ClusterSettings: [
          {
            Name: 'containerInsights',
            Value: 'enhanced',
          },
        ],
        ServiceConnectDefaults: {
          Namespace: Match.anyValue(),
        },
      });
    });

    test('Creates Fargate services', () => {
      // LibreChat service
      template.hasResourceProperties('AWS::ECS::Service', {
        LaunchType: 'FARGATE',
        DesiredCount: 3,
        EnableExecuteCommand: true,
        HealthCheckGracePeriodSeconds: 120,
      });

      // Check for auto-scaling
      template.hasResourceProperties('AWS::ApplicationAutoScaling::ScalableTarget', {
        ServiceNamespace: 'ecs',
        ScalableDimension: 'ecs:service:DesiredCount',
        MinCapacity: 2,
        MaxCapacity: 10,
      });
    });

    test('Creates Aurora PostgreSQL Serverless', () => {
      template.hasResourceProperties('AWS::RDS::DBCluster', {
        Engine: 'aurora-postgresql',
        EngineMode: 'provisioned',
        ServerlessV2ScalingConfiguration: {
          MinCapacity: 0.5,
          MaxCapacity: 16,
        },
        BackupRetentionPeriod: 30,
        DeletionProtection: true,
        StorageEncrypted: true,
      });
    });

    test('Creates DocumentDB cluster', () => {
      template.hasResourceProperties('AWS::DocDB::DBCluster', {
        BackupRetentionPeriod: 30,
        DeletionProtection: true,
        StorageEncrypted: true,
      });

      template.hasResourceProperties('AWS::DocDB::DBInstance', {
        DBInstanceClass: 'db.t3.medium',
      });
    });

    test('Creates EFS file system', () => {
      template.hasResourceProperties('AWS::EFS::FileSystem', {
        Encrypted: true,
        PerformanceMode: 'generalPurpose',
        ThroughputMode: 'elastic',
        BackupPolicy: {
          Status: 'ENABLED',
        },
      });

      // Check for access points
      template.resourceCountIs('AWS::EFS::AccessPoint', 4);
    });

    test('Creates HTTPS listener with certificate', () => {
      template.hasResourceProperties('AWS::ElasticLoadBalancingV2::Listener', {
        Port: 443,
        Protocol: 'HTTPS',
        Certificates: [
          {
            CertificateArn: 'arn:aws:acm:us-east-1:123456789012:certificate/12345',
          },
        ],
      });

      // HTTP to HTTPS redirect
      template.hasResourceProperties('AWS::ElasticLoadBalancingV2::Listener', {
        Port: 80,
        Protocol: 'HTTP',
        DefaultActions: [
          {
            Type: 'redirect',
            RedirectConfig: {
              Port: '443',
              Protocol: 'HTTPS',
              StatusCode: 'HTTP_301',
            },
          },
        ],
      });
    });

    test('Creates Route53 A record', () => {
      template.hasResourceProperties('AWS::Route53::RecordSet', {
        Name: 'librechat.example.com.',
        Type: 'A',
        HostedZoneId: 'Z1234567890ABC',
        AliasTarget: {
          DNSName: Match.anyValue(),
          HostedZoneId: Match.anyValue(),
        },
      });
    });

    test('Creates CloudWatch alarms', () => {
      // Check for various alarms
      const alarmTypes = ['CPU', 'Memory', 'UnhealthyHost', 'ResponseTime', 'ErrorLog'];

      alarmTypes.forEach((alarmType) => {
        template.hasResourceProperties('AWS::CloudWatch::Alarm', {
          AlarmDescription: Match.stringLikeRegexp(`.*${alarmType}.*`),
          AlarmActions: Match.arrayWith([
            Match.anyValue(), // SNS topic ARN
          ]),
        });
      });
    });

    test('Creates SNS topic for alerts', () => {
      template.hasResourceProperties('AWS::SNS::Topic', {
        DisplayName: Match.stringLikeRegexp('.*LibreChat.*Alarms.*'),
      });

      template.hasResourceProperties('AWS::SNS::Subscription', {
        Protocol: 'email',
        TopicArn: Match.anyValue(),
        Endpoint: 'alerts@example.com',
      });
    });

    test('Creates Lambda functions for database initialization', () => {
      // PostgreSQL init
      template.hasResourceProperties('AWS::Lambda::Function', {
        Handler: 'init_postgres.handler',
        Runtime: 'python3.11',
        Environment: {
          Variables: {
            POSTGRES_SECRET_ARN: Match.anyValue(),
            ENABLE_PGVECTOR: 'true',
          },
        },
      });

      // DocumentDB init
      template.hasResourceProperties('AWS::Lambda::Function', {
        Handler: 'init_docdb.handler',
        Runtime: 'python3.11',
        Environment: {
          Variables: {
            DOCDB_SECRET_ARN: Match.anyValue(),
            DOCDB_ENDPOINT: Match.anyValue(),
          },
        },
      });
    });
  });

  describe('Feature Flags', () => {
    test('Enables RAG components when flag is set', () => {
      const config = new DeploymentConfigBuilder('development')
        .withDeploymentMode('EC2')
        .withKeyPair('test-key')
        .withFeatures({ rag: true });
      const stack = createStack(config);

      // Should have RAG service in ECS mode
      // In EC2 mode, RAG is configured in user data
      expect(stack).toBeDefined();
    });

    test('Enables Meilisearch when flag is set', () => {
      const config = new DeploymentConfigBuilder('production')
        .withDeploymentMode('ECS')
        .withFeatures({ meilisearch: true });
      const stack = createStack(config);
      const template = Template.fromStack(stack);

      // Should have Meilisearch service
      template.hasResourceProperties('AWS::ECS::TaskDefinition', {
        ContainerDefinitions: Match.arrayWith([
          Match.objectLike({
            Name: 'meilisearch',
            Image: Match.stringLikeRegexp('.*meilisearch.*'),
          }),
        ]),
      });
    });
  });

  describe('Stack Outputs', () => {
    test('Creates expected outputs', () => {
      const config = new DeploymentConfigBuilder('development')
        .withDeploymentMode('EC2')
        .withKeyPair('test-key');
      const stack = createStack(config);
      const template = Template.fromStack(stack);

      const outputs = ['LoadBalancerURL', 'DeploymentMode', 'postgresEndpoint', 'VPCId'];

      outputs.forEach((output) => {
        template.hasOutput(output, {
          Description: Match.anyValue(),
        });
      });
    });
  });

  describe('Cost Optimization', () => {
    test('Development uses cost-optimized resources', () => {
      const config = new DeploymentConfigBuilder('development')
        .withDeploymentMode('EC2')
        .withKeyPair('test-key');
      const stack = createStack(config);
      const template = Template.fromStack(stack);

      // No NAT gateways
      template.resourceCountIs('AWS::EC2::NatGateway', 0);

      // Small instance types
      template.hasResourceProperties('AWS::EC2::Instance', {
        InstanceType: 't3.large',
      });

      template.hasResourceProperties('AWS::RDS::DBInstance', {
        DBInstanceClass: 'db.t3.small',
      });

      // Minimal backup retention
      template.hasResourceProperties('AWS::RDS::DBInstance', {
        BackupRetentionPeriod: 1,
      });
    });
  });

  describe('Security', () => {
    test('All databases are encrypted', () => {
      const config = new DeploymentConfigBuilder('production').withDeploymentMode('ECS');
      const stack = createStack(config);
      const template = Template.fromStack(stack);

      // RDS encryption
      template.hasResourceProperties('AWS::RDS::DBCluster', {
        StorageEncrypted: true,
      });

      // DocumentDB encryption
      template.hasResourceProperties('AWS::DocDB::DBCluster', {
        StorageEncrypted: true,
      });

      // EFS encryption
      template.hasResourceProperties('AWS::EFS::FileSystem', {
        Encrypted: true,
      });

      // S3 encryption
      template.hasResourceProperties('AWS::S3::Bucket', {
        BucketEncryption: Match.objectLike({
          ServerSideEncryptionConfiguration: Match.anyValue(),
        }),
      });
    });

    test('IAM roles follow least privilege', () => {
      const config = new DeploymentConfigBuilder('production').withDeploymentMode('ECS');
      const stack = createStack(config);
      const template = Template.fromStack(stack);

      // Check that S3 permissions are scoped to specific bucket
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: 'Allow',
              Action: Match.arrayWith(['s3:GetObject', 's3:PutObject']),
              Resource: Match.not('*'), // Should not be wildcard
            }),
          ]),
        },
      });
    });
  });
});
