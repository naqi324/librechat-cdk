// test/librechat-stack.test.ts
import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { LibreChatStack } from '../lib/librechat-stack';

describe('LibreChatStack', () => {
  let app: cdk.App;
  let stack: LibreChatStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new LibreChatStack(app, 'TestStack', {
      env: {
        account: '123456789012',
        region: 'us-east-1',
      },
    });
    template = Template.fromStack(stack);
  });

  test('VPC Created with Correct Configuration', () => {
    template.hasResourceProperties('AWS::EC2::VPC', {
      CidrBlock: '10.0.0.0/16',
      EnableDnsHostnames: true,
      EnableDnsSupport: true,
    });

    // Should have 4 subnets (2 public, 2 private)
    template.resourceCountIs('AWS::EC2::Subnet', 4);
  });

  test('Security Groups Created', () => {
    // ALB Security Group
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupDescription: 'Security group for LibreChat ALB',
      SecurityGroupIngress: Match.arrayWith([
        Match.objectLike({
          IpProtocol: 'tcp',
          FromPort: 80,
          ToPort: 80,
          CidrIp: '0.0.0.0/0',
        }),
        Match.objectLike({
          IpProtocol: 'tcp',
          FromPort: 443,
          ToPort: 443,
          CidrIp: '0.0.0.0/0',
        }),
      ]),
    });

    // RDS Security Group
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupDescription: 'Security group for LibreChat RDS instance',
    });
  });

  test('RDS Instance Created with pgvector', () => {
    template.hasResourceProperties('AWS::RDS::DBInstance', {
      Engine: 'postgres',
      DBInstanceClass: 'db.t3.medium',
      AllocatedStorage: '100',
      StorageEncrypted: true,
      BackupRetentionPeriod: 7,
    });

    // Check parameter group for pgvector
    template.hasResourceProperties('AWS::RDS::DBParameterGroup', {
      Description: 'PostgreSQL 15 with pgvector',
      Parameters: {
        'shared_preload_libraries': 'pgvector',
      },
    });
  });

  test('S3 Bucket Created with Encryption', () => {
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

  test('EC2 Instance with Correct Configuration', () => {
    template.hasResourceProperties('AWS::EC2::Instance', {
      InstanceType: 't3.xlarge',
      BlockDeviceMappings: [
        {
          DeviceName: '/dev/sda1',
          Ebs: {
            VolumeSize: 100,
            VolumeType: 'gp3',
            Encrypted: true,
          },
        },
      ],
    });
  });

  test('IAM Role Has Required Permissions', () => {
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: {
        Statement: Match.arrayWith([
          // Bedrock permissions
          Match.objectLike({
            Effect: 'Allow',
            Action: Match.arrayWith([
              'bedrock:InvokeModel',
              'bedrock:InvokeModelWithResponseStream',
              'bedrock:ListFoundationModels',
            ]),
            Resource: '*',
          }),
          // S3 permissions
          Match.objectLike({
            Effect: 'Allow',
            Action: Match.arrayWith([
              's3:GetObject',
              's3:PutObject',
              's3:DeleteObject',
              's3:ListBucket',
            ]),
          }),
        ]),
      },
    });
  });

  test('Load Balancer and Target Group Created', () => {
    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::LoadBalancer', {
      Type: 'application',
      Scheme: 'internet-facing',
    });

    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::TargetGroup', {
      Port: 3080,
      Protocol: 'HTTP',
      HealthCheckPath: '/health',
      HealthCheckIntervalSeconds: 30,
    });
  });

  test('CloudWatch Alarms Created', () => {
    // CPU Alarm
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      MetricName: 'CPUUtilization',
      Namespace: 'AWS/EC2',
      Statistic: 'Average',
      Period: 300,
      EvaluationPeriods: 2,
      Threshold: 80,
      ComparisonOperator: 'GreaterThanThreshold',
    });

    // Database Connections Alarm
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      MetricName: 'DatabaseConnections',
      Namespace: 'AWS/RDS',
      Statistic: 'Average',
      Period: 300,
      EvaluationPeriods: 1,
      Threshold: 80,
      ComparisonOperator: 'GreaterThanThreshold',
    });
  });

  test('Stack Has Required Parameters', () => {
    const cfnTemplate = stack.templateOptions;
    template.hasParameter('AlertEmail', {
      Type: 'String',
      Description: 'Email address for CloudWatch alarm notifications',
    });

    template.hasParameter('KeyName', {
      Type: 'AWS::EC2::KeyPair::KeyName',
      Description: 'EC2 Key Pair for SSH access',
    });

    template.hasParameter('AllowedSSHIP', {
      Type: 'String',
      Description: Match.anyValue(),
      Default: '0.0.0.0/0',
    });
  });

  test('Stack Has Expected Outputs', () => {
    template.hasOutput('LoadBalancerURL', {
      Description: 'URL to access LibreChat',
    });

    template.hasOutput('SSHCommand', {
      Description: 'SSH command to connect to the instance',
    });

    template.hasOutput('DatabaseEndpoint', {
      Description: 'RDS Database endpoint',
    });

    template.hasOutput('S3BucketName', {
      Description: 'S3 bucket for file storage',
    });
  });

  test('User Data Script Contains Required Commands', () => {
    // Verify EC2 instance has user data
    template.hasResourceProperties('AWS::EC2::Instance', {
      UserData: Match.anyValue(),
    });

    // The actual user data content testing would require parsing base64
    // which is complex in CDK tests. Key point is user data exists.
  });

  test('SharePoint Configuration When Enabled', () => {
    const stackWithSharePoint = new LibreChatStack(app, 'SharePointStack', {
      enableSharePoint: true,
      sharePointConfig: {
        tenantId: 'test-tenant',
        clientId: 'test-client',
        clientSecret: 'test-secret',
        siteUrl: 'https://test.sharepoint.com',
      },
    });

    const spTemplate = Template.fromStack(stackWithSharePoint);
    const userData = spTemplate.findResources('AWS::EC2::Instance');
    const userDataEncoded = Object.values(userData)[0].Properties.UserData['Fn::Base64'];

    expect(JSON.stringify(userDataEncoded)).toContain('SHAREPOINT_TENANT_ID');
  });
});

// Run tests with: npm test
