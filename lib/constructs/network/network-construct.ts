import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

export interface VpcConstructProps {
  useExisting: boolean;
  existingVpcId?: string;
  cidr?: string;
  maxAzs?: number;
  natGateways?: number;
  environment: string;
}

export class VpcConstruct extends Construct {
  public readonly vpc: ec2.IVpc;
  public readonly publicSubnets: ec2.ISubnet[];
  public readonly privateSubnets: ec2.ISubnet[];
  public readonly isolatedSubnets: ec2.ISubnet[];

  constructor(scope: Construct, id: string, props: VpcConstructProps) {
    super(scope, id);

    if (props.useExisting && props.existingVpcId) {
      // Import existing VPC
      this.vpc = ec2.Vpc.fromLookup(this, 'ImportedVpc', {
        vpcId: props.existingVpcId,
      });

      // Get subnets from imported VPC
      this.publicSubnets = this.vpc.publicSubnets;
      this.privateSubnets = this.vpc.privateSubnets;
      this.isolatedSubnets = this.vpc.isolatedSubnets;
    } else {
      // Create new VPC
      const vpc = new ec2.Vpc(this, 'VPC', {
        ipAddresses: ec2.IpAddresses.cidr(props.cidr || '10.0.0.0/16'),
        maxAzs: props.maxAzs || 2,
        natGateways: props.natGateways || 1,
        subnetConfiguration: this.getSubnetConfiguration(props),
        enableDnsHostnames: true,
        enableDnsSupport: true,
      });

      this.vpc = vpc;
      this.publicSubnets = vpc.publicSubnets;
      this.privateSubnets = vpc.privateSubnets;
      this.isolatedSubnets = vpc.isolatedSubnets;

      // Add VPC endpoints for AWS services to reduce costs and improve security
      this.addVpcEndpoints(vpc, props.environment);

      // Add flow logs for all environments (security best practice)
      this.addFlowLogs(vpc, props.environment);

      // Tag subnets for better identification
      this.tagSubnets();
    }
  }

  private getSubnetConfiguration(props: VpcConstructProps): ec2.SubnetConfiguration[] {
    const configs: ec2.SubnetConfiguration[] = [
      {
        name: 'Public',
        subnetType: ec2.SubnetType.PUBLIC,
        cidrMask: 24,
      },
    ];

    // Add private subnets if NAT gateways are configured
    if (props.natGateways && props.natGateways > 0) {
      configs.push({
        name: 'Private',
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        cidrMask: 24,
      });
    }

    // Always add isolated subnets for databases
    configs.push({
      name: 'Isolated',
      subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      cidrMask: 24,
    });

    return configs;
  }

  private addVpcEndpoints(vpc: ec2.Vpc, environment: string): void {
    // S3 Gateway endpoint (free)
    vpc.addGatewayEndpoint('S3Endpoint', {
      service: ec2.GatewayVpcEndpointAwsService.S3,
      subnets: [
        { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
        { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
      ],
    });

    // DynamoDB Gateway endpoint (free)
    vpc.addGatewayEndpoint('DynamoDBEndpoint', {
      service: ec2.GatewayVpcEndpointAwsService.DYNAMODB,
      subnets: [
        { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
        { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
      ],
    });

    // Secrets Manager endpoint is required for Lambda functions without NAT gateway
    vpc.addInterfaceEndpoint('SecretsManagerEndpoint', {
      service: ec2.InterfaceVpcEndpointAwsService.SECRETS_MANAGER,
      privateDnsEnabled: true,
    });
    
    // CloudWatch Logs endpoint for Lambda logging
    vpc.addInterfaceEndpoint('CloudWatchLogsEndpoint', {
      service: ec2.InterfaceVpcEndpointAwsService.CLOUDWATCH_LOGS,
      privateDnsEnabled: true,
    });

    // Lambda endpoint for function execution
    vpc.addInterfaceEndpoint('LambdaEndpoint', {
      service: ec2.InterfaceVpcEndpointAwsService.LAMBDA,
      privateDnsEnabled: true,
    });

    // KMS endpoint for secret decryption
    vpc.addInterfaceEndpoint('KmsEndpoint', {
      service: ec2.InterfaceVpcEndpointAwsService.KMS,
      privateDnsEnabled: true,
    });

    // Interface endpoints for production (these have costs)
    if (environment === 'production') {
      // ECR endpoints for container pulls
      vpc.addInterfaceEndpoint('EcrEndpoint', {
        service: ec2.InterfaceVpcEndpointAwsService.ECR,
        privateDnsEnabled: true,
      });

      vpc.addInterfaceEndpoint('EcrDockerEndpoint', {
        service: ec2.InterfaceVpcEndpointAwsService.ECR_DOCKER,
        privateDnsEnabled: true,
      });


      // Bedrock endpoints for AI services
      vpc.addInterfaceEndpoint('BedrockEndpoint', {
        service: new ec2.InterfaceVpcEndpointService(
          `com.amazonaws.${cdk.Stack.of(this).region}.bedrock`
        ),
        privateDnsEnabled: true,
      });

      vpc.addInterfaceEndpoint('BedrockRuntimeEndpoint', {
        service: new ec2.InterfaceVpcEndpointService(
          `com.amazonaws.${cdk.Stack.of(this).region}.bedrock-runtime`
        ),
        privateDnsEnabled: true,
      });
    }
  }

  private addFlowLogs(vpc: ec2.Vpc, environment: string): void {
    // Create a log group with appropriate retention
    const logGroup = new logs.LogGroup(this, 'VPCFlowLogGroup', {
      logGroupName: `/aws/vpc/flowlogs/${cdk.Stack.of(this).stackName}`,
      retention: environment === 'production' 
        ? logs.RetentionDays.ONE_YEAR 
        : logs.RetentionDays.ONE_MONTH,
      removalPolicy: environment === 'production' 
        ? cdk.RemovalPolicy.RETAIN 
        : cdk.RemovalPolicy.DESTROY,
    });

    // Create IAM role for VPC Flow Logs
    const flowLogRole = new iam.Role(this, 'VPCFlowLogRole', {
      assumedBy: new iam.ServicePrincipal('vpc-flow-logs.amazonaws.com'),
      description: 'Role for VPC Flow Logs to write to CloudWatch',
    });

    // Grant permissions to write logs
    logGroup.grantWrite(flowLogRole);

    // Create flow log with enhanced configuration
    new ec2.FlowLog(this, 'VPCFlowLog', {
      resourceType: ec2.FlowLogResourceType.fromVpc(vpc),
      destination: ec2.FlowLogDestination.toCloudWatchLogs(logGroup, flowLogRole),
      trafficType: ec2.FlowLogTrafficType.ALL,
      maxAggregationInterval: ec2.FlowLogMaxAggregationInterval.ONE_MINUTE,
      // Use custom log format for comprehensive logging
      logFormat: undefined, // Will use default AWS format which includes all necessary fields
    });

    // Add tags for compliance
    cdk.Tags.of(logGroup).add('Purpose', 'VPC-Flow-Logs');
    cdk.Tags.of(logGroup).add('Compliance', 'Security-Monitoring');
  }

  private tagSubnets(): void {
    // Tag public subnets
    this.publicSubnets.forEach((subnet, index) => {
      cdk.Tags.of(subnet).add('Name', `Public-Subnet-${index + 1}`);
      cdk.Tags.of(subnet).add('Type', 'Public');
    });

    // Tag private subnets
    this.privateSubnets.forEach((subnet, index) => {
      cdk.Tags.of(subnet).add('Name', `Private-Subnet-${index + 1}`);
      cdk.Tags.of(subnet).add('Type', 'Private');
    });

    // Tag isolated subnets
    this.isolatedSubnets.forEach((subnet, index) => {
      cdk.Tags.of(subnet).add('Name', `Isolated-Subnet-${index + 1}`);
      cdk.Tags.of(subnet).add('Type', 'Isolated');
    });
  }
}
