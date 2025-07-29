#!/usr/bin/env node
import { PricingClient } from '@aws-sdk/client-pricing';
import { EC2Client } from '@aws-sdk/client-ec2';
import Table from 'cli-table3';
import chalk from 'chalk';

import { environmentConfigs } from '../config/deployment-config';

interface CostEstimate {
  service: string;
  resource: string;
  quantity: number;
  unit: string;
  pricePerUnit: number;
  monthlyHours: number;
  monthlyCost: number;
  notes?: string;
}

class CostEstimator {
  private readonly HOURS_PER_MONTH = 730; // Average hours in a month

  constructor(region: string = 'us-east-1') {
    // Clients would be initialized here if needed
    new PricingClient({ region: 'us-east-1' }); // Pricing API only available in us-east-1
    new EC2Client({ region });
  }

  async estimateForEnvironment(
    environment: keyof typeof environmentConfigs
  ): Promise<CostEstimate[]> {
    const config = environmentConfigs[environment];
    const estimates: CostEstimate[] = [];

    // EC2/ECS Compute costs
    if (config.deploymentMode === 'EC2') {
      estimates.push(...(await this.estimateEC2Costs(config)));
    } else {
      estimates.push(...(await this.estimateECSCosts(config)));
    }

    // Database costs
    estimates.push(...(await this.estimateDatabaseCosts(config)));

    // Storage costs
    estimates.push(...(await this.estimateStorageCosts(config)));

    // Network costs
    estimates.push(...(await this.estimateNetworkCosts(config)));

    // Additional services
    estimates.push(...(await this.estimateAdditionalServicesCosts(config)));

    return estimates;
  }

  private async estimateEC2Costs(config: any): Promise<CostEstimate[]> {
    const estimates: CostEstimate[] = [];
    const instanceType = config.computeConfig?.instanceType || 't3.xlarge';

    try {
      // Get instance pricing
      const price = await this.getEC2Price(instanceType);

      estimates.push({
        service: 'EC2',
        resource: `Instance (${instanceType})`,
        quantity: 1,
        unit: 'hour',
        pricePerUnit: price,
        monthlyHours: this.HOURS_PER_MONTH,
        monthlyCost: price * this.HOURS_PER_MONTH,
      });

      // EBS storage (100GB GP3)
      estimates.push({
        service: 'EC2',
        resource: 'EBS Storage (GP3)',
        quantity: 100,
        unit: 'GB-month',
        pricePerUnit: 0.08,
        monthlyHours: 1,
        monthlyCost: 100 * 0.08,
      });

      // EBS IOPS (if applicable)
      estimates.push({
        service: 'EC2',
        resource: 'EBS IOPS',
        quantity: 3000,
        unit: 'IOPS-month',
        pricePerUnit: 0.005,
        monthlyHours: 1,
        monthlyCost: 3000 * 0.005,
      });
    } catch (error) {
      console.error('Error estimating EC2 costs:', error);
    }

    return estimates;
  }

  private async estimateECSCosts(config: any): Promise<CostEstimate[]> {
    const estimates: CostEstimate[] = [];
    const cpu = config.computeConfig?.cpu || 4096;
    const memory = config.computeConfig?.memory || 8192;
    const desiredCount = config.computeConfig?.desiredCount || 2;

    // Fargate pricing
    const cpuPrice = 0.04048; // per vCPU per hour
    const memoryPrice = 0.004445; // per GB per hour

    const vCPUs = cpu / 1024;
    const memoryGB = memory / 1024;

    estimates.push({
      service: 'ECS Fargate',
      resource: `CPU (${cpu} units)`,
      quantity: vCPUs * desiredCount,
      unit: 'vCPU-hour',
      pricePerUnit: cpuPrice,
      monthlyHours: this.HOURS_PER_MONTH,
      monthlyCost: vCPUs * desiredCount * cpuPrice * this.HOURS_PER_MONTH,
    });

    estimates.push({
      service: 'ECS Fargate',
      resource: `Memory (${memory} MB)`,
      quantity: memoryGB * desiredCount,
      unit: 'GB-hour',
      pricePerUnit: memoryPrice,
      monthlyHours: this.HOURS_PER_MONTH,
      monthlyCost: memoryGB * desiredCount * memoryPrice * this.HOURS_PER_MONTH,
    });

    return estimates;
  }

  private async estimateDatabaseCosts(config: any): Promise<CostEstimate[]> {
    const estimates: CostEstimate[] = [];
    const engine = config.databaseConfig?.engine || 'postgres';

    // PostgreSQL/Aurora
    if (engine.includes('postgres')) {
      const instanceClass = config.databaseConfig?.instanceClass || 'db.t3.medium';

      if (config.environment === 'production') {
        // Aurora Serverless v2
        estimates.push({
          service: 'RDS Aurora',
          resource: 'Serverless v2 (min 0.5 ACU)',
          quantity: 0.5,
          unit: 'ACU-hour',
          pricePerUnit: 0.12,
          monthlyHours: this.HOURS_PER_MONTH,
          monthlyCost: 0.5 * 0.12 * this.HOURS_PER_MONTH,
          notes: 'Minimum capacity, scales up as needed',
        });

        // Aurora storage
        estimates.push({
          service: 'RDS Aurora',
          resource: 'Storage',
          quantity: 100,
          unit: 'GB-month',
          pricePerUnit: 0.1,
          monthlyHours: 1,
          monthlyCost: 100 * 0.1,
        });
      } else {
        // Regular RDS
        const price = await this.getRDSPrice(instanceClass);
        estimates.push({
          service: 'RDS PostgreSQL',
          resource: `Instance (${instanceClass})`,
          quantity: 1,
          unit: 'hour',
          pricePerUnit: price,
          monthlyHours: this.HOURS_PER_MONTH,
          monthlyCost: price * this.HOURS_PER_MONTH,
        });
      }

      // Backup storage
      estimates.push({
        service: 'RDS',
        resource: 'Backup Storage',
        quantity: 100,
        unit: 'GB-month',
        pricePerUnit: 0.095,
        monthlyHours: 1,
        monthlyCost: 100 * 0.095,
      });
    }

    // DocumentDB
    if (engine === 'postgres-and-documentdb') {
      estimates.push({
        service: 'DocumentDB',
        resource: 'Instance (db.t3.medium)',
        quantity: 1,
        unit: 'hour',
        pricePerUnit: 0.08,
        monthlyHours: this.HOURS_PER_MONTH,
        monthlyCost: 0.08 * this.HOURS_PER_MONTH,
      });

      estimates.push({
        service: 'DocumentDB',
        resource: 'Storage',
        quantity: 50,
        unit: 'GB-month',
        pricePerUnit: 0.1,
        monthlyHours: 1,
        monthlyCost: 50 * 0.1,
      });
    }

    return estimates;
  }

  private async estimateStorageCosts(config: any): Promise<CostEstimate[]> {
    const estimates: CostEstimate[] = [];

    // S3 storage
    estimates.push({
      service: 'S3',
      resource: 'Standard Storage',
      quantity: 100,
      unit: 'GB-month',
      pricePerUnit: 0.023,
      monthlyHours: 1,
      monthlyCost: 100 * 0.023,
    });

    // S3 requests
    estimates.push({
      service: 'S3',
      resource: 'PUT/POST/LIST requests',
      quantity: 100000,
      unit: '1000 requests',
      pricePerUnit: 0.005,
      monthlyHours: 1,
      monthlyCost: 100 * 0.005,
    });

    estimates.push({
      service: 'S3',
      resource: 'GET requests',
      quantity: 1000000,
      unit: '1000 requests',
      pricePerUnit: 0.0004,
      monthlyHours: 1,
      monthlyCost: 1000 * 0.0004,
    });

    // EFS (if using ECS)
    if (config.deploymentMode === 'ECS') {
      estimates.push({
        service: 'EFS',
        resource: 'Standard Storage',
        quantity: 20,
        unit: 'GB-month',
        pricePerUnit: 0.3,
        monthlyHours: 1,
        monthlyCost: 20 * 0.3,
      });
    }

    return estimates;
  }

  private async estimateNetworkCosts(config: any): Promise<CostEstimate[]> {
    const estimates: CostEstimate[] = [];

    // ALB
    estimates.push({
      service: 'ELB',
      resource: 'Application Load Balancer',
      quantity: 1,
      unit: 'hour',
      pricePerUnit: 0.0225,
      monthlyHours: this.HOURS_PER_MONTH,
      monthlyCost: 0.0225 * this.HOURS_PER_MONTH,
    });

    // ALB LCU (Load Balancer Capacity Units)
    estimates.push({
      service: 'ELB',
      resource: 'LCU-hour',
      quantity: 10,
      unit: 'LCU-hour',
      pricePerUnit: 0.008,
      monthlyHours: this.HOURS_PER_MONTH,
      monthlyCost: 10 * 0.008 * this.HOURS_PER_MONTH,
    });

    // NAT Gateway (if applicable)
    const natGateways = config.vpcConfig?.natGateways || 0;
    if (natGateways > 0) {
      estimates.push({
        service: 'VPC',
        resource: `NAT Gateway (${natGateways} gateways)`,
        quantity: natGateways,
        unit: 'hour',
        pricePerUnit: 0.045,
        monthlyHours: this.HOURS_PER_MONTH,
        monthlyCost: natGateways * 0.045 * this.HOURS_PER_MONTH,
      });

      // NAT Gateway data processing
      estimates.push({
        service: 'VPC',
        resource: 'NAT Gateway Data',
        quantity: 100,
        unit: 'GB',
        pricePerUnit: 0.045,
        monthlyHours: 1,
        monthlyCost: 100 * 0.045,
      });
    }

    // Data transfer
    estimates.push({
      service: 'Data Transfer',
      resource: 'Out to Internet',
      quantity: 100,
      unit: 'GB',
      pricePerUnit: 0.09,
      monthlyHours: 1,
      monthlyCost: 100 * 0.09,
      notes: 'First 1 GB free',
    });

    return estimates;
  }

  private async estimateAdditionalServicesCosts(config: any): Promise<CostEstimate[]> {
    const estimates: CostEstimate[] = [];

    // CloudWatch
    estimates.push({
      service: 'CloudWatch',
      resource: 'Logs Ingestion',
      quantity: 10,
      unit: 'GB',
      pricePerUnit: 0.5,
      monthlyHours: 1,
      monthlyCost: 10 * 0.5,
    });

    estimates.push({
      service: 'CloudWatch',
      resource: 'Logs Storage',
      quantity: 50,
      unit: 'GB-month',
      pricePerUnit: 0.03,
      monthlyHours: 1,
      monthlyCost: 50 * 0.03,
    });

    estimates.push({
      service: 'CloudWatch',
      resource: 'Metrics',
      quantity: 50,
      unit: 'metric-month',
      pricePerUnit: 0.3,
      monthlyHours: 1,
      monthlyCost: 50 * 0.3,
      notes: 'First 10 metrics free',
    });

    // Secrets Manager
    estimates.push({
      service: 'Secrets Manager',
      resource: 'Secrets',
      quantity: 5,
      unit: 'secret-month',
      pricePerUnit: 0.4,
      monthlyHours: 1,
      monthlyCost: 5 * 0.4,
    });

    // SNS (for alerts)
    if (config.alertEmail) {
      estimates.push({
        service: 'SNS',
        resource: 'Email notifications',
        quantity: 100,
        unit: 'emails',
        pricePerUnit: 0.00002,
        monthlyHours: 1,
        monthlyCost: 100 * 0.00002,
        notes: 'First 1000 emails free',
      });
    }

    // Lambda (for initialization)
    estimates.push({
      service: 'Lambda',
      resource: 'Invocations',
      quantity: 10,
      unit: 'million requests',
      pricePerUnit: 0.2,
      monthlyHours: 1,
      monthlyCost: 0.001,
      notes: 'First 1M requests free',
    });

    return estimates;
  }

  private async getEC2Price(instanceType: string): Promise<number> {
    // Default prices for common instance types (us-east-1)
    const defaultPrices: { [key: string]: number } = {
      't3.micro': 0.0104,
      't3.small': 0.0208,
      't3.medium': 0.0416,
      't3.large': 0.0832,
      't3.xlarge': 0.1664,
      't3.2xlarge': 0.3328,
      'm5.large': 0.096,
      'm5.xlarge': 0.192,
      'm5.2xlarge': 0.384,
    };

    return defaultPrices[instanceType] || 0.1664; // Default to t3.xlarge
  }

  private async getRDSPrice(instanceClass: string): Promise<number> {
    // Default prices for common RDS instance types (us-east-1)
    const defaultPrices: { [key: string]: number } = {
      'db.t3.micro': 0.017,
      'db.t3.small': 0.034,
      'db.t3.medium': 0.068,
      'db.t3.large': 0.136,
      'db.r6g.large': 0.24,
      'db.r6g.xlarge': 0.48,
    };

    return defaultPrices[instanceClass] || 0.068; // Default to db.t3.medium
  }

  public generateReport(estimates: CostEstimate[]): void {
    const table = new Table({
      head: [
        chalk.cyan('Service'),
        chalk.cyan('Resource'),
        chalk.cyan('Quantity'),
        chalk.cyan('Unit Price'),
        chalk.cyan('Monthly Cost'),
        chalk.cyan('Notes'),
      ],
      style: {
        head: [],
        border: [],
      },
    });

    let totalMonthlyCost = 0;
    const serviceTotals: { [key: string]: number } = {};

    estimates.forEach((estimate) => {
      totalMonthlyCost += estimate.monthlyCost;
      serviceTotals[estimate.service] =
        (serviceTotals[estimate.service] || 0) + estimate.monthlyCost;

      table.push([
        estimate.service,
        estimate.resource,
        `${estimate.quantity} ${estimate.unit}`,
        `$${estimate.pricePerUnit.toFixed(4)}`,
        chalk.green(`$${estimate.monthlyCost.toFixed(2)}`),
        estimate.notes || '',
      ]);
    });

    console.log('\n' + chalk.bold.blue('AWS Cost Estimation Report'));
    console.log('='.repeat(80));
    console.log(table.toString());
    console.log('='.repeat(80));

    // Service summary
    console.log('\n' + chalk.bold('Cost Summary by Service:'));
    Object.entries(serviceTotals)
      .sort((a, b) => b[1] - a[1])
      .forEach(([service, cost]) => {
        const percentage = ((cost / totalMonthlyCost) * 100).toFixed(1);
        console.log(
          `  ${service.padEnd(20)} ${chalk.green(`$${cost.toFixed(2)}`).padEnd(15)} (${percentage}%)`
        );
      });

    console.log('\n' + '='.repeat(80));
    console.log(
      chalk.bold(`Total Estimated Monthly Cost: ${chalk.green(`$${totalMonthlyCost.toFixed(2)}`)}`)
    );
    console.log(
      chalk.bold(
        `Total Estimated Annual Cost: ${chalk.green(`$${(totalMonthlyCost * 12).toFixed(2)}`)}`
      )
    );
    console.log('='.repeat(80));

    // Disclaimers
    console.log('\n' + chalk.yellow('⚠️  Important Notes:'));
    console.log(chalk.gray('- Prices are estimates based on us-east-1 region'));
    console.log(chalk.gray('- Actual costs may vary based on usage patterns'));
    console.log(chalk.gray('- Free tier discounts are not included'));
    console.log(chalk.gray('- Data transfer costs are estimated'));
    console.log(chalk.gray('- Consider using AWS Cost Calculator for detailed estimates'));
  }

  public async generateComparisonReport(): Promise<void> {
    console.log('\n' + chalk.bold.blue('Cost Comparison Across Environments'));
    console.log('='.repeat(80));

    const environments: Array<keyof typeof environmentConfigs> = [
      'development',
      'staging',
      'production',
    ];
    const allEstimates: { [key: string]: CostEstimate[] } = {};
    const totals: { [key: string]: number } = {};

    // Calculate estimates for each environment
    for (const env of environments) {
      const estimates = await this.estimateForEnvironment(env);
      allEstimates[env] = estimates;
      totals[env] = estimates.reduce((sum, est) => sum + est.monthlyCost, 0);
    }

    // Create comparison table
    const table = new Table({
      head: [
        chalk.cyan('Service'),
        chalk.cyan('Development'),
        chalk.cyan('Staging'),
        chalk.cyan('Production'),
      ],
    });

    // Get all unique services
    const allServices = new Set<string>();
    Object.values(allEstimates).forEach((estimates) => {
      estimates.forEach((est) => allServices.add(est.service));
    });

    // Add service costs to table
    Array.from(allServices)
      .sort()
      .forEach((service) => {
        const row = [service];
        environments.forEach((env) => {
          const estimates = allEstimates[env];
          if (estimates) {
            const serviceCost = estimates
              .filter((est) => est.service === service)
              .reduce((sum, est) => sum + est.monthlyCost, 0);
            row.push(serviceCost > 0 ? chalk.green(`$${serviceCost.toFixed(2)}`) : '-');
          } else {
            row.push('-');
          }
        });
        table.push(row);
      });

    // Add totals row
    table.push([
      chalk.bold('TOTAL'),
      chalk.bold.green(`$${(totals.development || 0).toFixed(2)}`),
      chalk.bold.green(`$${(totals.staging || 0).toFixed(2)}`),
      chalk.bold.green(`$${(totals.production || 0).toFixed(2)}`),
    ]);

    console.log(table.toString());

    // Annual comparison
    console.log('\n' + chalk.bold('Annual Cost Comparison:'));
    environments.forEach((env) => {
      const monthlyTotal = totals[env] || 0;
      const annual = monthlyTotal * 12;
      console.log(`  ${env.padEnd(15)} ${chalk.green(`$${annual.toFixed(2)}`)}`);
    });
  }
}

// CLI execution
async function main() {
  const args = process.argv.slice(2);
  const estimator = new CostEstimator();

  if (args.includes('--compare')) {
    await estimator.generateComparisonReport();
  } else {
    const environment = (args[0] as keyof typeof environmentConfigs) || 'development';

    if (!environmentConfigs[environment]) {
      console.error(chalk.red(`Invalid environment: ${environment}`));
      console.log('Available environments:', Object.keys(environmentConfigs).join(', '));
      process.exit(1);
    }

    console.log(chalk.blue(`Estimating costs for ${environment} environment...`));
    const estimates = await estimator.estimateForEnvironment(environment);
    estimator.generateReport(estimates);

    if (args.includes('--save')) {
      const fs = require('fs');
      const filename = `cost-estimate-${environment}-${new Date().toISOString().split('T')[0]}.json`;
      fs.writeFileSync(filename, JSON.stringify(estimates, null, 2));
      console.log(`\nEstimate saved to ${filename}`);
    }
  }
}

if (require.main === module) {
  main().catch(console.error);
}

export { CostEstimator };
