#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';

import { LibreChatStack } from '../lib/librechat-stack';
import {
  DeploymentConfigBuilder,
  presetConfigs,
  getConfigFromEnvironment,
} from '../config/deployment-config';

// Load environment variables from .env file if it exists
try {
  require('dotenv').config();
} catch (e) {
  // dotenv is optional, ignore if not installed
}

const app = new cdk.App();

// Determine configuration source
let config;
const configSource = app.node.tryGetContext('configSource') || 'environment';

switch (configSource) {
  case 'minimal-dev':
    config = presetConfigs.minimalDev
      .withKeyPair(app.node.tryGetContext('keyPairName') || process.env.KEY_PAIR_NAME!)
      .build();
    break;

  case 'standard-dev':
    config = presetConfigs.standardDev
      .withKeyPair(app.node.tryGetContext('keyPairName') || process.env.KEY_PAIR_NAME!)
      .build();
    break;

  case 'full-dev':
    config = presetConfigs.fullDev
      .withKeyPair(app.node.tryGetContext('keyPairName') || process.env.KEY_PAIR_NAME!)
      .build();
    break;

  case 'production-ec2':
    config = presetConfigs.productionEC2
      .withKeyPair(app.node.tryGetContext('keyPairName') || process.env.KEY_PAIR_NAME!)
      .withAlertEmail(app.node.tryGetContext('alertEmail') || process.env.ALERT_EMAIL!)
      .build();
    break;

  case 'production-ecs':
    config = presetConfigs.productionECS
      .withAlertEmail(app.node.tryGetContext('alertEmail') || process.env.ALERT_EMAIL!)
      .build();
    break;

  case 'enterprise':
    config = presetConfigs.enterprise
      .withAlertEmail(app.node.tryGetContext('alertEmail') || process.env.ALERT_EMAIL!)
      .build();
    break;

  case 'custom':
    // Build custom configuration from context
    const environment = app.node.tryGetContext('environment') || 'development';
    const builder = new DeploymentConfigBuilder(environment);

    // Apply all context values
    const deploymentMode = app.node.tryGetContext('deploymentMode');
    if (deploymentMode) {
      builder.withDeploymentMode(deploymentMode);
    }

    const keyPairName = app.node.tryGetContext('keyPairName');
    if (keyPairName) {
      builder.withKeyPair(keyPairName);
    }

    const alertEmail = app.node.tryGetContext('alertEmail');
    if (alertEmail) {
      builder.withAlertEmail(alertEmail);
    }

    const allowedIps = app.node.tryGetContext('allowedIps');
    if (allowedIps) {
      builder.withAllowedIps(allowedIps.split(','));
    }

    const domainName = app.node.tryGetContext('domainName');
    if (domainName) {
      builder.withDomain(
        domainName,
        app.node.tryGetContext('certificateArn'),
        app.node.tryGetContext('hostedZoneId')
      );
    }

    const existingVpcId = app.node.tryGetContext('existingVpcId');
    if (existingVpcId) {
      builder.withExistingVpc(existingVpcId);
    }

    // Features
    const features: any = {};
    const enableRag = app.node.tryGetContext('enableRag');
    if (enableRag !== undefined) {
      features.rag = enableRag === 'true';
    }

    const enableMeilisearch = app.node.tryGetContext('enableMeilisearch');
    if (enableMeilisearch !== undefined) {
      features.meilisearch = enableMeilisearch === 'true';
    }

    const enableSharePoint = app.node.tryGetContext('enableSharePoint');
    if (enableSharePoint !== undefined) {
      features.sharePoint = enableSharePoint === 'true';
    }

    if (Object.keys(features).length > 0) {
      builder.withFeatures(features);
    }

    config = builder.build();
    break;

  case 'environment':
  default:
    // Use environment variables
    config = getConfigFromEnvironment();
    break;
}

// Create the stack
const stack = new LibreChatStack(app, `LibreChatStack-${config.environment}`, {
  ...config,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID || 'unknown',
    region: process.env.CDK_DEFAULT_REGION || process.env.AWS_DEFAULT_REGION || 'us-east-1',
  },
  description: `LibreChat ${config.environment} deployment using ${config.deploymentMode}`,
});

// Add additional tags from context
const additionalTags = app.node.tryGetContext('tags');
if (additionalTags) {
  Object.entries(additionalTags).forEach(([key, value]) => {
    cdk.Tags.of(stack).add(key, String(value));
  });
}

// Output configuration summary
console.log('\n🚀 LibreChat CDK Deployment Configuration:');
console.log('==========================================');
console.log(`Environment: ${config.environment}`);
console.log(`Deployment Mode: ${config.deploymentMode}`);
console.log(`Stack Name: LibreChatStack-${config.environment}`);
console.log(`Region: ${process.env.CDK_DEFAULT_REGION || 'default'}`);
console.log(`Features:`);
console.log(`  - RAG: ${config.enableRag ? '✅' : '❌'}`);
console.log(`  - Meilisearch: ${config.enableMeilisearch ? '✅' : '❌'}`);
console.log(`  - SharePoint: ${config.enableSharePoint ? '✅' : '❌'}`);
console.log(`  - Enhanced Monitoring: ${config.enableEnhancedMonitoring ? '✅' : '❌'}`);
console.log('==========================================\n');

app.synth();
