import * as cdk from 'aws-cdk-lib';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatch_actions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as sns_subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';
import { EC2Deployment } from '../compute/ec2-deployment';
import { ECSDeployment } from '../compute/ecs-deployment';
import { DatabaseConstruct } from '../database/database-construct';

export interface MonitoringConstructProps {
  alertEmail?: string;
  deployment: EC2Deployment | ECSDeployment;
  database: DatabaseConstruct;
  environment: string;
  enableEnhancedMonitoring?: boolean;
}

export class MonitoringConstruct extends Construct {
  public readonly alarmTopic: sns.Topic;
  public readonly dashboard: cloudwatch.Dashboard;
  
  constructor(scope: Construct, id: string, props: MonitoringConstructProps) {
    super(scope, id);
    
    // Create SNS topic for alarms
    this.alarmTopic = new sns.Topic(this, 'AlarmTopic', {
      displayName: `LibreChat ${props.environment} Alarms`,
    });
    
    // Add email subscription if provided
    if (props.alertEmail) {
      this.alarmTopic.addSubscription(
        new sns_subscriptions.EmailSubscription(props.alertEmail)
      );
    }
    
    // Create dashboard
    this.dashboard = new cloudwatch.Dashboard(this, 'Dashboard', {
      dashboardName: `LibreChat-${props.environment}-Dashboard`,
      defaultInterval: cdk.Duration.hours(1),
    });
    
    // Add deployment-specific monitoring
    if (props.deployment instanceof EC2Deployment) {
      this.addEC2Monitoring(props.deployment, props);
    } else {
      this.addECSMonitoring(props.deployment as ECSDeployment, props);
    }
    
    // Add database monitoring
    this.addDatabaseMonitoring(props);
    
    // Add application-level monitoring
    this.addApplicationMonitoring(props);
    
    // Add cost monitoring
    if (props.environment === 'production') {
      this.addCostMonitoring(props);
    }
  }
  
  private addEC2Monitoring(deployment: EC2Deployment, _props: MonitoringConstructProps): void {
    // CPU utilization alarm
    const cpuAlarm = new cloudwatch.Alarm(this, 'EC2CPUAlarm', {
      metric: new cloudwatch.Metric({
        namespace: 'AWS/EC2',
        metricName: 'CPUUtilization',
        dimensionsMap: {
          InstanceId: deployment.instance.instanceId,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 80,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
      alarmDescription: 'EC2 instance CPU utilization is too high',
    });
    cpuAlarm.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));
    
    // Disk usage alarm
    const diskAlarm = new cloudwatch.Alarm(this, 'EC2DiskAlarm', {
      metric: new cloudwatch.Metric({
        namespace: 'LibreChat',
        metricName: 'DISK_USED_PERCENT',
        dimensionsMap: {
          InstanceId: deployment.instance.instanceId,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 85,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
      alarmDescription: 'EC2 instance disk usage is too high',
    });
    diskAlarm.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));
    
    // Memory usage alarm
    const memoryAlarm = new cloudwatch.Alarm(this, 'EC2MemoryAlarm', {
      metric: new cloudwatch.Metric({
        namespace: 'LibreChat',
        metricName: 'MEM_USED_PERCENT',
        dimensionsMap: {
          InstanceId: deployment.instance.instanceId,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 85,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
      alarmDescription: 'EC2 instance memory usage is too high',
    });
    memoryAlarm.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));
    
    // Status check alarm
    const statusAlarm = new cloudwatch.Alarm(this, 'EC2StatusAlarm', {
      metric: new cloudwatch.Metric({
        namespace: 'AWS/EC2',
        metricName: 'StatusCheckFailed',
        dimensionsMap: {
          InstanceId: deployment.instance.instanceId,
        },
        statistic: 'Maximum',
        period: cdk.Duration.minutes(1),
      }),
      threshold: 1,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
      alarmDescription: 'EC2 instance status check failed',
    });
    statusAlarm.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));
    
    // Add EC2 widgets to dashboard
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'EC2 Metrics',
        left: [cpuAlarm.metric],
        right: [memoryAlarm.metric],
        width: 12,
        height: 6,
      }),
      new cloudwatch.SingleValueWidget({
        title: 'Instance Status',
        metrics: [statusAlarm.metric],
        width: 6,
        height: 3,
      }),
      new cloudwatch.SingleValueWidget({
        title: 'Disk Usage',
        metrics: [diskAlarm.metric],
        width: 6,
        height: 3,
      }),
    );
  }
  
  private addECSMonitoring(deployment: ECSDeployment, _props: MonitoringConstructProps): void {
    // Service CPU utilization
    const serviceCpuMetric = new cloudwatch.Metric({
      namespace: 'AWS/ECS',
      metricName: 'CPUUtilization',
      dimensionsMap: {
        ClusterName: deployment.cluster.clusterName,
        ServiceName: deployment.service.serviceName,
      },
      statistic: 'Average',
      period: cdk.Duration.minutes(5),
    });
    
    const cpuAlarm = new cloudwatch.Alarm(this, 'ECSCPUAlarm', {
      metric: serviceCpuMetric,
      threshold: 75,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
      alarmDescription: 'ECS service CPU utilization is too high',
    });
    cpuAlarm.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));
    
    // Service memory utilization
    const serviceMemoryMetric = new cloudwatch.Metric({
      namespace: 'AWS/ECS',
      metricName: 'MemoryUtilization',
      dimensionsMap: {
        ClusterName: deployment.cluster.clusterName,
        ServiceName: deployment.service.serviceName,
      },
      statistic: 'Average',
      period: cdk.Duration.minutes(5),
    });
    
    const memoryAlarm = new cloudwatch.Alarm(this, 'ECSMemoryAlarm', {
      metric: serviceMemoryMetric,
      threshold: 80,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
      alarmDescription: 'ECS service memory utilization is too high',
    });
    memoryAlarm.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));
    
    // Running task count
    const runningTasksMetric = new cloudwatch.Metric({
      namespace: 'ECS/ContainerInsights',
      metricName: 'RunningTaskCount',
      dimensionsMap: {
        ClusterName: deployment.cluster.clusterName,
        ServiceName: deployment.service.serviceName,
      },
      statistic: 'Average',
      period: cdk.Duration.minutes(1),
    });
    
    const taskAlarm = new cloudwatch.Alarm(this, 'ECSTaskAlarm', {
      metric: runningTasksMetric,
      threshold: 1, // Alert if less than 1 task is running
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
      alarmDescription: 'ECS service has insufficient running tasks',
    });
    taskAlarm.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));
    
    // Add ECS widgets to dashboard
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'ECS Service Metrics',
        left: [serviceCpuMetric, serviceMemoryMetric],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Running Tasks',
        left: [runningTasksMetric],
        width: 12,
        height: 6,
      }),
    );
  }
  
  private addDatabaseMonitoring(props: MonitoringConstructProps): void {
    // PostgreSQL monitoring
    if (props.database.postgresCluster) {
      // Aurora ServerlessV2 capacity
      const capacityMetric = new cloudwatch.Metric({
        namespace: 'AWS/RDS',
        metricName: 'ServerlessV2Capacity',
        dimensionsMap: {
          DBClusterIdentifier: props.database.postgresCluster.clusterIdentifier,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      });
      
      // Database connections
      const connectionsMetric = new cloudwatch.Metric({
        namespace: 'AWS/RDS',
        metricName: 'DatabaseConnections',
        dimensionsMap: {
          DBClusterIdentifier: props.database.postgresCluster.clusterIdentifier,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      });
      
      const connectionAlarm = new cloudwatch.Alarm(this, 'DBConnectionAlarm', {
        metric: connectionsMetric,
        threshold: 80,
        evaluationPeriods: 2,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
        alarmDescription: 'Database connection count is too high',
      });
      connectionAlarm.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));
      
      this.dashboard.addWidgets(
        new cloudwatch.GraphWidget({
          title: 'Aurora PostgreSQL Metrics',
          left: [capacityMetric],
          right: [connectionsMetric],
          width: 12,
          height: 6,
        }),
      );
    } else if (props.database.postgresInstance) {
      // RDS instance monitoring
      const cpuMetric = new cloudwatch.Metric({
        namespace: 'AWS/RDS',
        metricName: 'CPUUtilization',
        dimensionsMap: {
          DBInstanceIdentifier: props.database.postgresInstance.instanceIdentifier,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      });
      
      const connectionMetric = new cloudwatch.Metric({
        namespace: 'AWS/RDS',
        metricName: 'DatabaseConnections',
        dimensionsMap: {
          DBInstanceIdentifier: props.database.postgresInstance.instanceIdentifier,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      });
      
      const cpuAlarm = new cloudwatch.Alarm(this, 'RDSCPUAlarm', {
        metric: cpuMetric,
        threshold: 75,
        evaluationPeriods: 2,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
        alarmDescription: 'RDS CPU utilization is too high',
      });
      cpuAlarm.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));
      
      this.dashboard.addWidgets(
        new cloudwatch.GraphWidget({
          title: 'RDS PostgreSQL Metrics',
          left: [cpuMetric],
          right: [connectionMetric],
          width: 12,
          height: 6,
        }),
      );
    }
    
    // DocumentDB monitoring
    if (props.database.documentDbCluster) {
      const docdbCpuMetric = new cloudwatch.Metric({
        namespace: 'AWS/DocDB',
        metricName: 'CPUUtilization',
        dimensionsMap: {
          DBClusterIdentifier: props.database.documentDbCluster.clusterIdentifier,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      });
      
      const docdbConnectionMetric = new cloudwatch.Metric({
        namespace: 'AWS/DocDB',
        metricName: 'DatabaseConnections',
        dimensionsMap: {
          DBClusterIdentifier: props.database.documentDbCluster.clusterIdentifier,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      });
      
      this.dashboard.addWidgets(
        new cloudwatch.GraphWidget({
          title: 'DocumentDB Metrics',
          left: [docdbCpuMetric],
          right: [docdbConnectionMetric],
          width: 12,
          height: 6,
        }),
      );
    }
  }
  
  private addApplicationMonitoring(props: MonitoringConstructProps): void {
    // ALB metrics
    const deployment = props.deployment as any;
    if (deployment.loadBalancer) {
      const requestCountMetric = new cloudwatch.Metric({
        namespace: 'AWS/ApplicationELB',
        metricName: 'RequestCount',
        dimensionsMap: {
          LoadBalancer: deployment.loadBalancer.loadBalancerFullName,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      });
      
      const targetResponseTimeMetric = new cloudwatch.Metric({
        namespace: 'AWS/ApplicationELB',
        metricName: 'TargetResponseTime',
        dimensionsMap: {
          LoadBalancer: deployment.loadBalancer.loadBalancerFullName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      });
      
      const healthyHostCountMetric = new cloudwatch.Metric({
        namespace: 'AWS/ApplicationELB',
        metricName: 'HealthyHostCount',
        dimensionsMap: {
          LoadBalancer: deployment.loadBalancer.loadBalancerFullName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(1),
      });
      
      const unhealthyHostAlarm = new cloudwatch.Alarm(this, 'UnhealthyHostAlarm', {
        metric: healthyHostCountMetric,
        threshold: 1,
        comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
        evaluationPeriods: 2,
        treatMissingData: cloudwatch.TreatMissingData.BREACHING,
        alarmDescription: 'No healthy targets behind load balancer',
      });
      unhealthyHostAlarm.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));
      
      const responseTimeAlarm = new cloudwatch.Alarm(this, 'ResponseTimeAlarm', {
        metric: targetResponseTimeMetric,
        threshold: 3000, // 3 seconds
        evaluationPeriods: 2,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
        alarmDescription: 'Application response time is too high',
      });
      responseTimeAlarm.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));
      
      this.dashboard.addWidgets(
        new cloudwatch.GraphWidget({
          title: 'Application Load Balancer',
          left: [requestCountMetric],
          right: [targetResponseTimeMetric],
          width: 12,
          height: 6,
        }),
        new cloudwatch.SingleValueWidget({
          title: 'Healthy Targets',
          metrics: [healthyHostCountMetric],
          width: 6,
          height: 3,
        }),
      );
    }
    
    // Application logs insights
    const logGroup = new logs.LogGroup(this, 'ApplicationLogs', {
      logGroupName: `/aws/librechat/${props.environment}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: props.environment === 'production' 
        ? cdk.RemovalPolicy.RETAIN 
        : cdk.RemovalPolicy.DESTROY,
    });
    
    // Error log metric filter
    const errorMetricFilter = new logs.MetricFilter(this, 'ErrorLogMetric', {
      logGroup: logGroup,
      metricNamespace: 'LibreChat/Application',
      metricName: 'ErrorCount',
      filterPattern: logs.FilterPattern.anyTerm('ERROR', 'Error', 'error', 'FATAL', 'Fatal', 'fatal'),
      metricValue: '1',
      defaultValue: 0,
    });
    
    const errorAlarm = new cloudwatch.Alarm(this, 'ErrorLogAlarm', {
      metric: errorMetricFilter.metric({
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 10,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'High error rate in application logs',
    });
    errorAlarm.addAlarmAction(new cloudwatch_actions.SnsAction(this.alarmTopic));
  }
  
  private addCostMonitoring(_props: MonitoringConstructProps): void {
    // Cost monitoring would be implemented here with AWS Cost Explorer API
    
    // Add cost widget to dashboard
    this.dashboard.addWidgets(
      new cloudwatch.TextWidget({
        markdown: `## Cost Monitoring

**Note**: Enable AWS Cost Explorer and configure cost allocation tags for accurate cost tracking.

### Estimated Monthly Costs:
- EC2: ~$120 (t3.xlarge)
- RDS: ~$70 (db.t3.medium)
- ALB: ~$20
- S3: ~$5-20
- **Total**: ~$220-250/month

### Cost Optimization Tips:
1. Use Savings Plans for EC2
2. Enable RDS auto-stop for dev/staging
3. Set up S3 lifecycle policies
4. Monitor unused resources`,
        width: 24,
        height: 6,
      }),
    );
  }
}
