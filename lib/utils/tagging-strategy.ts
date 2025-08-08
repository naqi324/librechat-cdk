import * as cdk from 'aws-cdk-lib';
import { IConstruct } from 'constructs';

/**
 * Standard tags for all resources
 */
export interface StandardTags {
  Application: string;
  Environment: string;
  Owner?: string;
  Project?: string;
  DataClassification?: string;
  Compliance?: string;
  ManagedBy?: string;
  DeploymentMode?: string;
  Version?: string;
  BackupPolicy?: string;
  SecurityLevel?: string;
}

/**
 * Tagging configuration for the stack
 */
export interface TaggingConfig {
  standardTags: StandardTags;
  customTags?: { [key: string]: string };
  enableAutomaticTags?: boolean;
}

/**
 * Apply comprehensive tagging strategy to resources
 */
export class TaggingStrategy {
  private readonly config: TaggingConfig;
  private readonly stackName: string;
  private readonly timestamp: string;

  constructor(stackName: string, config: TaggingConfig) {
    this.config = config;
    this.stackName = stackName;
    const isoDate = new Date().toISOString();
    this.timestamp = isoDate.split('T')[0] || ''; // YYYY-MM-DD
  }

  /**
   * Apply standard tags to a construct
   */
  public applyTags(construct: IConstruct, additionalTags?: { [key: string]: string }): void {
    // Apply standard tags
    const standardTags = this.config.standardTags;

    // Required tags
    cdk.Tags.of(construct).add('Application', standardTags.Application);
    cdk.Tags.of(construct).add('Environment', standardTags.Environment);
    cdk.Tags.of(construct).add('ManagedBy', standardTags.ManagedBy || 'CDK');

    // Optional standard tags
    if (standardTags.Owner) {
      cdk.Tags.of(construct).add('Owner', standardTags.Owner);
    }
    if (standardTags.Project) {
      cdk.Tags.of(construct).add('Project', standardTags.Project);
    }
    if (standardTags.DataClassification) {
      cdk.Tags.of(construct).add('DataClassification', standardTags.DataClassification);
    }
    if (standardTags.Compliance) {
      cdk.Tags.of(construct).add('Compliance', standardTags.Compliance);
    }
    if (standardTags.DeploymentMode) {
      cdk.Tags.of(construct).add('DeploymentMode', standardTags.DeploymentMode);
    }
    if (standardTags.Version) {
      cdk.Tags.of(construct).add('Version', standardTags.Version);
    }
    if (standardTags.BackupPolicy) {
      cdk.Tags.of(construct).add('BackupPolicy', standardTags.BackupPolicy);
    }
    if (standardTags.SecurityLevel) {
      cdk.Tags.of(construct).add('SecurityLevel', standardTags.SecurityLevel);
    }

    // Apply automatic tags if enabled
    if (this.config.enableAutomaticTags) {
      cdk.Tags.of(construct).add('StackName', this.stackName);
      cdk.Tags.of(construct).add('CreatedDate', this.timestamp);
      cdk.Tags.of(construct).add('LastModified', this.timestamp);
    }

    // Apply custom tags
    if (this.config.customTags) {
      Object.entries(this.config.customTags).forEach(([key, value]) => {
        cdk.Tags.of(construct).add(key, value);
      });
    }

    // Apply additional tags specific to this construct
    if (additionalTags) {
      Object.entries(additionalTags).forEach(([key, value]) => {
        cdk.Tags.of(construct).add(key, value);
      });
    }
  }

  /**
   * Apply resource-specific tags based on resource type
   */
  public applyResourceSpecificTags(construct: IConstruct, resourceType: string): void {
    const resourceTags: { [key: string]: string } = {
      ResourceType: resourceType,
    };

    // Add specific tags based on resource type
    switch (resourceType) {
      case 'Database':
        resourceTags['BackupRequired'] = 'true';
        resourceTags['EncryptionRequired'] = 'true';
        resourceTags['PHIData'] = this.config.standardTags.Compliance?.includes('HIPAA')
          ? 'true'
          : 'false';
        break;

      case 'Storage':
        resourceTags['EncryptionRequired'] = 'true';
        resourceTags['LifecyclePolicy'] = 'enabled';
        resourceTags['AccessLogging'] = 'enabled';
        break;

      case 'Compute':
        resourceTags['PatchingRequired'] = 'true';
        resourceTags['MonitoringRequired'] = 'true';
        break;

      case 'Network':
        resourceTags['FlowLogsEnabled'] = 'true';
        resourceTags['SecurityGroupRequired'] = 'true';
        break;

      case 'Security':
        resourceTags['AuditRequired'] = 'true';
        resourceTags['ComplianceScope'] = 'all';
        break;
    }

    this.applyTags(construct, resourceTags);
  }

  /**
   * Get all tags as a map for use in CloudFormation outputs or documentation
   */
  public getAllTags(): { [key: string]: string } {
    const allTags: { [key: string]: string } = {
      ...this.config.standardTags,
    };

    if (this.config.enableAutomaticTags) {
      allTags['StackName'] = this.stackName;
      allTags['CreatedDate'] = this.timestamp;
      allTags['LastModified'] = this.timestamp;
    }

    if (this.config.customTags) {
      Object.assign(allTags, this.config.customTags);
    }

    return allTags;
  }

  /**
   * Get resource tracking tags
   */
  public getResourceTrackingTags(): string[] {
    return [
      'Application',
      'Environment',
      'Project',
      'Owner',
      'DeploymentMode',
      'ResourceType',
    ];
  }

  /**
   * Create compliance-specific tags based on the compliance framework
   */
  public static getComplianceTags(framework: 'HIPAA' | 'SOC2' | 'PCI' | 'ISO27001'): {
    [key: string]: string;
  } {
    const complianceTags: { [key: string]: string } = {
      ComplianceFramework: framework,
      ComplianceRequired: 'true',
    };

    switch (framework) {
      case 'HIPAA':
        complianceTags['PHIData'] = 'true';
        complianceTags['EncryptionRequired'] = 'true';
        complianceTags['AuditRequired'] = 'true';
        complianceTags['RetentionYears'] = '7';
        break;

      case 'SOC2':
        complianceTags['SOC2Scope'] = 'true';
        complianceTags['ChangeControlRequired'] = 'true';
        complianceTags['AccessReviewRequired'] = 'true';
        break;

      case 'PCI':
        complianceTags['PCIScope'] = 'true';
        complianceTags['CardholderData'] = 'false'; // Should be explicitly set
        complianceTags['NetworkSegmentation'] = 'required';
        break;

      case 'ISO27001':
        complianceTags['ISO27001Scope'] = 'true';
        complianceTags['RiskAssessmentRequired'] = 'true';
        complianceTags['AssetInventory'] = 'required';
        break;
    }

    return complianceTags;
  }
}
