# LibreChat AWS CDK Infrastructure

[![AWS CDK](https://img.shields.io/badge/AWS%20CDK-2.177.0-orange)](https://aws.amazon.com/cdk/)
[![Node.js](https://img.shields.io/badge/Node.js-18%2B-green)](https://nodejs.org/)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.3-blue)](https://www.typescriptlang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Enterprise-grade AWS infrastructure for deploying [LibreChat](https://github.com/danny-avila/LibreChat), an open-source AI chat platform that supports multiple AI providers, user authentication, and conversation management.

## 📋 Table of Contents

- [About](#about)
- [Features](#features)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Documentation](#documentation)
- [License](#license)
- [Disclaimer](#disclaimer)

## About

This repository provides AWS CDK (Cloud Development Kit) infrastructure code to deploy LibreChat on AWS with production-ready features, security best practices, and cost optimization. It is not affiliated with the official LibreChat project but is designed to work seamlessly with it.

**LibreChat** is an open-source AI chat application created by [Danny Avila](https://github.com/danny-avila) and licensed under the [MIT License](https://github.com/danny-avila/LibreChat/blob/main/LICENSE). Learn more at:
- 🌐 [LibreChat Official Website](https://www.librechat.ai/)
- 📚 [LibreChat Documentation](https://docs.librechat.ai/)
- 💻 [LibreChat GitHub Repository](https://github.com/danny-avila/LibreChat)

## Features

### Infrastructure Features
- **🎯 Flexible Deployment Modes**: Choose between EC2 (simple, cost-effective) or ECS Fargate (scalable, managed)
- **🔐 Enterprise Security**: VPC isolation, IAM roles, KMS encryption, security groups, and audit logging
- **📊 Comprehensive Monitoring**: CloudWatch dashboards, alarms, and centralized logging
- **💰 Cost Optimized**: Right-sized resources with environment-specific configurations
- **🔄 High Availability**: Multi-AZ deployments, auto-scaling, and fault tolerance

### AI & Application Features
- **🤖 AWS Bedrock Integration**: Native support for Claude, Titan, and Llama models
- **🔍 RAG Support**: Vector search capabilities with PostgreSQL pgvector
- **💾 Flexible Storage**: S3 for documents, EFS for shared storage (ECS mode)
- **🗄️ Database Options**: RDS PostgreSQL with pgvector, optional DocumentDB for MongoDB compatibility
- **🔎 Search**: Optional Meilisearch integration for full-text search

## Quick Start

### Prerequisites

- AWS Account with appropriate permissions ([see guide](docs/AWS_AUTHENTICATION.md))
- Node.js 18+ and npm installed
- AWS CLI configured with credentials
- AWS Bedrock access enabled in your region
- EC2 Key Pair (required for EC2 mode only)

### Deployment

```bash
# Clone the repository
git clone https://github.com/your-org/librechat-cdk.git
cd librechat-cdk

# Install dependencies
npm install

# Run interactive deployment wizard (recommended)
npm run wizard
```

The wizard will guide you through the entire deployment process, including AWS setup, configuration selection, and deployment execution.

For manual deployment options, see the [Quick Reference](QUICK_REFERENCE.md).

## Architecture

<details>
<summary>View Architecture Overview</summary>

### EC2 Deployment Mode
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Internet  │────▶│     ALB     │────▶│     EC2     │
└─────────────┘     └─────────────┘     │  Instance   │
                                        └──────┬──────┘
                                               │
                    ┌──────────────────────────┴───────┐
                    │                                  │
              ┌─────▼─────┐                    ┌──────▼──────┐
              │    RDS    │                    │     S3      │
              │PostgreSQL │                    │   Storage   │
              └───────────┘                    └─────────────┘
```

### ECS Deployment Mode
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Internet  │────▶│     ALB     │────▶│     ECS     │
└─────────────┘     └─────────────┘     │   Fargate   │
                                        └──────┬──────┘
                                               │
        ┌──────────────┬───────────────┬───────┴────────┐
        │              │               │                │
  ┌─────▼─────┐  ┌────▼─────┐  ┌─────▼─────┐  ┌──────▼──────┐
  │    RDS    │  │DocumentDB │  │    EFS    │  │     S3      │
  │PostgreSQL │  │(Optional) │  │  Storage  │  │   Storage   │
  └───────────┘  └───────────┘  └───────────┘  └─────────────┘
```
</details>

## Documentation

- 📖 **[Quick Reference](QUICK_REFERENCE.md)** - Commands and configuration cheatsheet
- 📚 **[Documentation Index](docs/README.md)** - Comprehensive guides organized by topic
- 🏗️ **[Project Structure](PROJECT_STRUCTURE.md)** - Repository organization and file descriptions
- 🔒 **[Security Guide](docs/SECURITY.md)** - Security best practices and compliance
- 🔧 **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions

## Contributing

We welcome contributions! Please feel free to submit pull requests, report issues, and help improve the project. For questions or discussions, please open an issue on GitHub.

## License

This infrastructure code is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

**Note**: This license applies only to the infrastructure code in this repository. LibreChat itself is a separate project with its own [MIT License](https://github.com/danny-avila/LibreChat/blob/main/LICENSE).

## Disclaimer

**IMPORTANT**: This software is provided "AS IS", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.

**AWS Costs**: You are responsible for all AWS costs incurred by resources created using this infrastructure code. Please review the [cost estimates](QUICK_REFERENCE.md#cost-optimization) and set up billing alerts before deployment.

**Security**: While this infrastructure implements security best practices, you are responsible for:
- Reviewing and adapting the security configuration to meet your requirements
- Maintaining and updating the infrastructure
- Ensuring compliance with your organization's security policies
- Protecting sensitive data and credentials

**Not Official**: This is not an official LibreChat project. For official LibreChat support, please visit the [LibreChat repository](https://github.com/danny-avila/LibreChat).

---

Built with ❤️ using [AWS CDK](https://aws.amazon.com/cdk/) and [TypeScript](https://www.typescriptlang.org/)