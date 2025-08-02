# Local CDK Testing Guide

This guide shows how to test your CDK build locally without deploying to AWS.

## 1. CDK Synthesis Testing (No AWS Required)

### Basic Synthesis Test
Tests if your CDK code compiles and generates valid CloudFormation:

```bash
# Build TypeScript
npm run build

# Synthesize CloudFormation template
cdk synth

# Or with specific configuration
cdk synth -c configSource=ultra-minimal-dev

# Check the generated template
cat cdk.out/LibreChatStack-development.template.json | jq '.Resources | length'
```

### Validate Template Size
Large templates can cause deployment issues:

```bash
# Check template size (should be < 1MB)
ls -lh cdk.out/*.template.json

# Count resources (should be < 200)
cat cdk.out/LibreChatStack-development.template.json | jq '.Resources | length'
```

## 2. Unit Testing (No AWS Required)

### Run Existing Tests
```bash
# Run all unit tests
npm test

# Run tests in watch mode
npm run test:watch

# Run tests with coverage
npm run test:coverage
```

### Test Specific Configurations
Create a test file `test/deployment-configs.test.ts`:

```typescript
import { App } from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { LibreChatStack } from '../lib/librechat-stack';
import { presetConfigs } from '../config/deployment-config';

describe('Deployment Configurations', () => {
  test('Ultra-minimal config creates fewer resources', () => {
    const app = new App();
    const stack = new LibreChatStack(app, 'TestStack', {
      ...presetConfigs['ultra-minimal-dev'].build(),
      env: { account: '123456789012', region: 'us-east-1' }
    });
    
    const template = Template.fromStack(stack);
    const resources = Object.keys(template.toJSON().Resources);
    
    console.log(`Ultra-minimal creates ${resources.length} resources`);
    expect(resources.length).toBeLessThan(100); // Should be minimal
  });

  test('No DocumentDB in ultra-minimal', () => {
    const app = new App();
    const stack = new LibreChatStack(app, 'TestStack', {
      ...presetConfigs['ultra-minimal-dev'].build(),
      env: { account: '123456789012', region: 'us-east-1' }
    });
    
    const template = Template.fromStack(stack);
    
    // Should not have DocumentDB resources
    expect(() => {
      template.hasResourceProperties('AWS::DocDB::DBCluster', {});
    }).toThrow();
  });
});
```

Run with:
```bash
npm test deployment-configs.test.ts
```

## 3. Local Stack Simulation (Partial AWS Services)

### Using LocalStack (Docker Required)
LocalStack simulates AWS services locally:

```bash
# Install LocalStack
pip install localstack

# Start LocalStack
localstack start -d

# Configure AWS CLI for LocalStack
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

# Deploy to LocalStack (limited services)
cdklocal deploy
```

Note: LocalStack free tier only supports basic services. Many CDK constructs won't work.

## 4. Dry Run Analysis

### Resource Counting Script
Create `scripts/analyze-deployment.js`:

```javascript
const fs = require('fs');
const path = require('path');

function analyzeTemplate(templatePath) {
  const template = JSON.parse(fs.readFileSync(templatePath, 'utf8'));
  const resources = template.Resources || {};
  
  // Count resources by type
  const resourceTypes = {};
  let customResources = 0;
  let lambdaFunctions = 0;
  
  Object.entries(resources).forEach(([name, resource]) => {
    const type = resource.Type;
    resourceTypes[type] = (resourceTypes[type] || 0) + 1;
    
    if (type.startsWith('Custom::')) customResources++;
    if (type === 'AWS::Lambda::Function') lambdaFunctions++;
  });
  
  // Find slow resources
  const slowResources = [
    'AWS::DocDB::DBCluster',
    'AWS::DocDB::DBInstance',
    'AWS::RDS::DBCluster',
    'AWS::RDS::DBInstance',
    'AWS::ECS::Service',
    'Custom::',
  ];
  
  console.log('\n📊 Deployment Analysis');
  console.log('====================');
  console.log(`Total Resources: ${Object.keys(resources).length}`);
  console.log(`Custom Resources: ${customResources}`);
  console.log(`Lambda Functions: ${lambdaFunctions}`);
  
  console.log('\n🐌 Slow Resources (10+ minutes each):');
  Object.entries(resourceTypes).forEach(([type, count]) => {
    if (slowResources.some(slow => type.includes(slow))) {
      console.log(`  ${type}: ${count}`);
    }
  });
  
  console.log('\n📈 Resource Distribution:');
  Object.entries(resourceTypes)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10)
    .forEach(([type, count]) => {
      console.log(`  ${type}: ${count}`);
    });
    
  // Estimate deployment time
  let estimatedMinutes = 10; // Base time
  estimatedMinutes += customResources * 5;
  estimatedMinutes += (resourceTypes['AWS::DocDB::DBCluster'] || 0) * 15;
  estimatedMinutes += (resourceTypes['AWS::DocDB::DBInstance'] || 0) * 10;
  estimatedMinutes += (resourceTypes['AWS::RDS::DBCluster'] || 0) * 10;
  estimatedMinutes += (resourceTypes['AWS::RDS::DBInstance'] || 0) * 8;
  estimatedMinutes += (resourceTypes['AWS::ECS::Service'] || 0) * 10;
  
  console.log(`\n⏱️  Estimated Deployment Time: ${estimatedMinutes}-${estimatedMinutes + 20} minutes`);
  
  if (estimatedMinutes > 90) {
    console.log('\n⚠️  WARNING: Deployment may exceed Isengard token lifetime!');
    console.log('   Consider using ultra-minimal configuration or AWS CloudShell.');
  }
}

// Synthesize and analyze
console.log('🔨 Building project...');
require('child_process').execSync('npm run build', { stdio: 'inherit' });

console.log('\n🔧 Synthesizing CDK...');
require('child_process').execSync('cdk synth', { stdio: 'inherit' });

const templatePath = path.join(__dirname, '../cdk.out/LibreChatStack-development.template.json');
analyzeTemplate(templatePath);

// Compare configurations
console.log('\n\n📊 Comparing Configurations');
console.log('===========================');

const configs = ['minimal-dev', 'ultra-minimal-dev', 'standard-dev'];
configs.forEach(config => {
  try {
    console.log(`\n${config}:`);
    require('child_process').execSync(`cdk synth -c configSource=${config}`, { stdio: 'pipe' });
    analyzeTemplate(templatePath);
  } catch (e) {
    console.log(`  ❌ Failed to synthesize ${config}`);
  }
});
```

Run with:
```bash
node scripts/analyze-deployment.js
```

## 5. Testing Lambda Functions Locally

### Test Database Initialization Functions
```bash
# Test PostgreSQL init function
cd lambda/init-postgres
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Mock test
python3 -c "
import os
os.environ['MAX_RETRIES'] = '5'
os.environ['RETRY_DELAY'] = '1'
# Add mock testing here
"
```

## 6. CDK Diff for Change Impact

### Preview Changes Without Deploying
```bash
# See what would change
cdk diff

# Compare different configurations
cdk diff -c configSource=minimal-dev
cdk diff -c configSource=ultra-minimal-dev

# Show security-related changes
cdk diff --security-only
```

## 7. Create Local Test Script

Create `test-deployment-time.sh`:

```bash
#!/bin/bash

echo "🧪 Testing CDK Deployment Configurations"
echo "======================================"

# Function to test configuration
test_config() {
    local config=$1
    echo -e "\n📋 Testing: $config"
    
    # Synthesize
    if cdk synth -c configSource=$config > /dev/null 2>&1; then
        # Count resources
        RESOURCE_COUNT=$(cat cdk.out/LibreChatStack-development.template.json | jq '.Resources | length')
        TEMPLATE_SIZE=$(ls -lh cdk.out/LibreChatStack-development.template.json | awk '{print $5}')
        
        # Check for slow resources
        DOCDB_COUNT=$(cat cdk.out/LibreChatStack-development.template.json | jq '.Resources | to_entries | map(select(.value.Type | contains("DocDB"))) | length')
        RDS_COUNT=$(cat cdk.out/LibreChatStack-development.template.json | jq '.Resources | to_entries | map(select(.value.Type | contains("RDS"))) | length')
        CUSTOM_COUNT=$(cat cdk.out/LibreChatStack-development.template.json | jq '.Resources | to_entries | map(select(.value.Type | startswith("Custom::"))) | length')
        
        echo "  ✅ Synthesis successful"
        echo "  📊 Resources: $RESOURCE_COUNT"
        echo "  📦 Template size: $TEMPLATE_SIZE"
        echo "  🗄️  Databases: RDS=$RDS_COUNT, DocDB=$DOCDB_COUNT"
        echo "  🔧 Custom resources: $CUSTOM_COUNT"
        
        # Estimate time
        EST_TIME=$((10 + CUSTOM_COUNT * 5 + DOCDB_COUNT * 15 + RDS_COUNT * 10))
        echo "  ⏱️  Estimated time: ${EST_TIME}-$((EST_TIME + 20)) minutes"
        
        if [ $EST_TIME -gt 90 ]; then
            echo "  ⚠️  WARNING: May exceed token lifetime!"
        fi
    else
        echo "  ❌ Synthesis failed"
    fi
}

# Test configurations
test_config "minimal-dev"
test_config "ultra-minimal-dev"
test_config "standard-dev"

echo -e "\n✅ Testing complete!"
```

Make executable and run:
```bash
chmod +x test-deployment-time.sh
./test-deployment-time.sh
```

## 8. Mock AWS Credentials for Testing

### Test with Dummy Credentials
```bash
# Set dummy credentials for synthesis only
export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
export AWS_DEFAULT_REGION=us-east-1

# This allows CDK synth to work without real AWS access
cdk synth
```

## Summary

1. **Use `cdk synth`** - Fastest way to validate your CDK code
2. **Run unit tests** - Validates logic without AWS
3. **Analyze templates** - Understand resource counts and deployment time
4. **Test configurations** - Compare different presets locally
5. **Mock credentials** - Test synthesis without AWS access

These methods let you validate and optimize your CDK deployment without any AWS connection or time constraints!