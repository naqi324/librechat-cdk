# DocumentDB Setup and Initialization

## Overview

This CDK deployment creates AWS DocumentDB (MongoDB-compatible) for LibreChat. However, to avoid deployment failures due to DocumentDB's startup time (5-10 minutes), the initialization is handled separately from the CDK deployment.

## Why Separate Initialization?

1. **Reliability**: DocumentDB takes 5-10 minutes to become available after creation
2. **Flexibility**: Allows deployment to succeed even if DocumentDB isn't immediately ready
3. **Application Resilience**: LibreChat can initialize collections on first connection

## Initialization Options

### Option 1: Let LibreChat Initialize (Recommended)

LibreChat will automatically create required collections and indexes on first connection. This is the simplest and most reliable approach.

**Pros:**
- No manual steps required
- Handles DocumentDB availability automatically
- Works across all environments

**Cons:**
- Slight delay on first application startup
- Collections created on-demand rather than upfront

### Option 2: Post-Deployment Script

Use the provided initialization script after deployment:

```bash
# Wait for deployment to complete
./scripts/validate-deployment.sh post-deploy production

# Initialize DocumentDB (run from bastion host or VPC-connected machine)
./scripts/init-documentdb.sh LibreChatStack-production us-east-1
```

**Pros:**
- Collections and indexes created upfront
- Can verify setup before application deployment
- Provides connection testing

**Cons:**
- Requires MongoDB client
- Must run from within VPC or bastion host
- Manual step after deployment

### Option 3: Bastion Host Initialization

1. Create an EC2 instance in the same VPC:
```bash
# Use the key pair from your deployment
aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --instance-type t3.micro \
  --key-name your-key-pair \
  --subnet-id subnet-xxxxx \
  --security-group-ids sg-xxxxx
```

2. SSH to the instance and run:
```bash
# Install MongoDB client
sudo yum install -y mongodb-org-shell

# Download CA certificate
curl -sS https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o rds-ca-2019-root.pem

# Get connection details from CloudFormation outputs
# Connect and initialize
mongo "mongodb://USERNAME:PASSWORD@docdb-endpoint:27017/?tls=true&tlsCAFile=rds-ca-2019-root.pem&replicaSet=rs0"
```

## Collections and Indexes

The following collections and indexes are created:

### Collections:
- `users` - User accounts
- `conversations` - Chat conversations
- `messages` - Individual messages
- `presets` - User presets
- `files` - Uploaded files metadata
- `assistants` - AI assistants
- `tools` - Available tools
- `sessions` - User sessions

### Key Indexes:
- Users: email (unique), username (unique), createdAt, lastLogin
- Conversations: userId + createdAt, endpoint, title (text), updatedAt
- Messages: conversationId + createdAt, userId, parentMessageId, model
- Sessions: userId, expiresAt (TTL)

## Troubleshooting

### "DocumentDB did not become available in time"

This error occurs when trying to connect before DocumentDB is ready. Solutions:
1. Wait 5-10 minutes after deployment
2. Use the application's built-in retry logic
3. Run initialization script manually later

### Cannot connect from local machine

DocumentDB is only accessible from within the VPC. Options:
1. Use a bastion host
2. Set up VPN access
3. Use Systems Manager Session Manager

### Performance Considerations

1. **Connection Pooling**: LibreChat uses connection pooling by default
2. **Read Preference**: Set to `secondaryPreferred` for better performance
3. **Indexes**: All required indexes are created automatically
4. **Instance Size**: Adjust based on workload (t3.medium minimum recommended)

## Security Notes

- DocumentDB requires TLS/SSL connections
- Credentials stored in AWS Secrets Manager
- Network isolated in private subnets
- No public access allowed
- Encryption at rest enabled by default