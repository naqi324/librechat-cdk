# LibreChat CDK Documentation

Welcome to the LibreChat CDK documentation. This guide will help you deploy and manage LibreChat on AWS.

## 📚 Documentation Structure

### Getting Started
- [**Main README**](../README.md) - Quick start and overview
- [**Project Structure**](../PROJECT_STRUCTURE.md) - Repository organization and file descriptions

### Deployment Guides
- [**AWS Authentication**](./AWS_AUTHENTICATION.md) - Setting up AWS credentials and permissions
- [**Local Testing Guide**](./LOCAL_TESTING_GUIDE.md) - Development and testing locally
- [**Deployment Optimization**](./DEPLOYMENT_OPTIMIZATION.md) - Cost and performance optimization
- [**Network Architecture**](./NETWORK_ARCHITECTURE.md) - VPC and networking details

### Configuration
- [**DocumentDB Setup**](./DOCUMENTDB_SETUP.md) - MongoDB-compatible database configuration
- [**Security Guide**](./SECURITY.md) - Security best practices and compliance

### Operations
- [**Troubleshooting Guide**](./TROUBLESHOOTING.md) - Common issues and solutions
- [**Cleanup Guide**](./CLEANUP.md) - Removing deployments and resources
- [**Cleanup Scripts**](../scripts/README-cleanup.md) - Cleanup script documentation

### Enterprise
- [**Isengard Token Workarounds**](./ISENGARD_TOKEN_WORKAROUNDS.md) - Enterprise AWS token solutions

### Development
- [**Claude.md**](../CLAUDE.md) - Instructions for AI-assisted development

## 🎯 Quick Links by Task

### I want to...

#### Deploy LibreChat
1. Start with the [Main README](../README.md)
2. Set up [AWS Authentication](./AWS_AUTHENTICATION.md)
3. Run the interactive deployment wizard: `npm run wizard`

#### Test Locally
1. Follow the [Local Testing Guide](./LOCAL_TESTING_GUIDE.md)
2. Use `docker-compose up` for local development

#### Optimize Costs
1. Read [Deployment Optimization](./DEPLOYMENT_OPTIMIZATION.md)
2. Use minimal configurations for development
3. Consider EC2 mode for production cost savings

#### Fix Issues
1. Check [Troubleshooting Guide](./TROUBLESHOOTING.md)
2. Review CloudFormation events in AWS Console
3. Check logs in CloudWatch

#### Clean Up Resources
1. Use the [Cleanup Guide](./CLEANUP.md)
2. Run `./scripts/cleanup.sh` for automated cleanup

## 📋 Configuration Reference

### Deployment Modes
- **EC2**: Simple, cost-effective, SSH access
- **ECS**: Scalable, managed, production-grade

### Environment Presets
- `minimal-dev` - Basic development setup
- `standard-dev` - Development with full features
- `production-ec2` - Production on EC2
- `production-ecs` - Production on ECS
- `enterprise` - Full enterprise features

### Key Environment Variables
```bash
DEPLOYMENT_ENV=production
DEPLOYMENT_MODE=ECS
KEY_PAIR_NAME=my-key
ALERT_EMAIL=ops@company.com
DOMAIN_NAME=chat.company.com
```

## 🆘 Getting Help

1. Check the relevant documentation section
2. Review [Troubleshooting Guide](./TROUBLESHOOTING.md)
3. Check AWS CloudFormation events
4. Review CloudWatch logs
5. Create an issue in the repository

## 📊 Architecture Diagrams

See the [Main README](../README.md#-architecture) for architecture diagrams and the [Network Architecture](./NETWORK_ARCHITECTURE.md) guide for detailed networking information.