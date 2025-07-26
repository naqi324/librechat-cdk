# Scripts Directory

## Primary Setup Script

**Use `./setup.sh` in the root directory** - This is the main setup and deployment script that handles everything:
- Environment validation
- Dependency installation
- Interactive configuration
- CDK bootstrap
- Stack deployment

## Specialized Scripts

These scripts remain for specific use cases:

### `estimate-cost.ts`
Estimates AWS costs for different deployment configurations.
```bash
npx ts-node scripts/estimate-cost.ts

# Or compile and run
npm run build
node scripts/estimate-cost.js
```

### `cleanup.sh`
Removes all deployed resources and cleans up the AWS account.
```bash
./scripts/cleanup.sh
```
**Warning:** This will delete all resources created by the stack!

### `deploy.sh`
Advanced deployment script for CI/CD pipelines. Use this when you need:
- Non-interactive deployments
- Custom environment variables
- Integration with CI/CD systems

### `create-one-click-deploy.sh`
Generates a CloudFormation template for one-click deployment via AWS Console.
```bash
./scripts/create-one-click-deploy.sh
```

### `fix-bootstrap.sh`
Fixes CDK bootstrap conflicts and ECR repository issues.
```bash
./scripts/fix-bootstrap.sh
```
Use this when you encounter bootstrap errors like "container-assets repository already exists".

### `check-bootstrap-status.sh`
Checks the current CDK bootstrap status and health.
```bash
./scripts/check-bootstrap-status.sh
```

## Note on Removed Scripts

The following scripts have been consolidated into the main `setup.sh`:
- ~~`quickstart.sh`~~ 
- ~~`setup-deployment.sh`~~
- ~~`setup-environment.sh`~~
- ~~`deploy-interactive.sh`~~

All functionality from these scripts is now available in the comprehensive `./setup.sh` script in the root directory.