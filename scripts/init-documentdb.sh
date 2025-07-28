#!/bin/bash

# DocumentDB Post-Deployment Initialization Script
# This script initializes DocumentDB collections and indexes after deployment
# Usage: ./init-documentdb.sh <stack-name> [region]

set -e

STACK_NAME=${1:-LibreChatStack-development}
REGION=${2:-$(aws configure get region || echo "us-east-1")}

echo "🔍 DocumentDB Initialization Script"
echo "=================================="
echo "Stack: $STACK_NAME"
echo "Region: $REGION"
echo ""

# Get DocumentDB endpoint from CloudFormation outputs
echo "📡 Getting DocumentDB endpoint..."
DOCDB_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='documentdbEndpoint'].OutputValue" \
  --output text 2>/dev/null || echo "")

if [ -z "$DOCDB_ENDPOINT" ]; then
  echo "❌ DocumentDB endpoint not found. Is DocumentDB enabled in this deployment?"
  exit 1
fi

echo "✅ DocumentDB endpoint: $DOCDB_ENDPOINT"

# Get secret ARN
SECRET_ARN=$(aws cloudformation describe-stack-resources \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query "StackResources[?LogicalResourceId=='DatabaseDocumentDbClusterSecretAttachment*'].PhysicalResourceId" \
  --output text | head -1)

if [ -z "$SECRET_ARN" ]; then
  echo "❌ DocumentDB secret not found"
  exit 1
fi

# Get credentials from Secrets Manager
echo "🔐 Retrieving credentials..."
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --region "$REGION" \
  --query SecretString \
  --output text)

USERNAME=$(echo "$SECRET_JSON" | jq -r .username)
PASSWORD=$(echo "$SECRET_JSON" | jq -r .password)

# Download CA certificate if not present
if [ ! -f "rds-ca-2019-root.pem" ]; then
  echo "📥 Downloading RDS CA certificate..."
  curl -sS "https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem" -o rds-ca-2019-root.pem
fi

# Create initialization script
cat > /tmp/init-docdb.js << 'EOF'
// DocumentDB initialization script
print("Initializing DocumentDB for LibreChat...");

db = db.getSiblingDB('librechat');

// Create collections
const collections = [
  'users',
  'conversations', 
  'messages',
  'presets',
  'files',
  'assistants',
  'tools',
  'sessions'
];

collections.forEach(function(collectionName) {
  if (!db.getCollectionNames().includes(collectionName)) {
    db.createCollection(collectionName);
    print("Created collection: " + collectionName);
  } else {
    print("Collection exists: " + collectionName);
  }
});

// Create indexes
print("\nCreating indexes...");

// Users indexes
db.users.createIndex({ email: 1 }, { unique: true });
db.users.createIndex({ username: 1 }, { unique: true });
db.users.createIndex({ createdAt: 1 });
db.users.createIndex({ lastLogin: -1 });

// Conversations indexes
db.conversations.createIndex({ userId: 1, createdAt: -1 });
db.conversations.createIndex({ endpoint: 1 });
db.conversations.createIndex({ title: "text" });
db.conversations.createIndex({ updatedAt: -1 });

// Messages indexes
db.messages.createIndex({ conversationId: 1, createdAt: 1 });
db.messages.createIndex({ userId: 1 });
db.messages.createIndex({ parentMessageId: 1 });
db.messages.createIndex({ model: 1 });

// Presets indexes
db.presets.createIndex({ userId: 1 });
db.presets.createIndex({ title: 1 });

// Files indexes
db.files.createIndex({ userId: 1, createdAt: -1 });
db.files.createIndex({ type: 1 });
db.files.createIndex({ filename: 1 });

// Assistants indexes
db.assistants.createIndex({ userId: 1 });
db.assistants.createIndex({ name: 1 });

// Tools indexes
db.tools.createIndex({ userId: 1 });
db.tools.createIndex({ name: 1 });
db.tools.createIndex({ type: 1 });

// Sessions indexes
db.sessions.createIndex({ userId: 1 });
db.sessions.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });

print("\n✅ DocumentDB initialization complete!");

// Show collection statistics
print("\nCollection statistics:");
collections.forEach(function(collectionName) {
  const stats = db[collectionName].stats();
  print("- " + collectionName + ": " + stats.count + " documents");
});
EOF

# Check if mongo client is installed
if ! command -v mongo &> /dev/null && ! command -v mongosh &> /dev/null; then
  echo "⚠️  MongoDB client not found. Please install mongo or mongosh to run initialization."
  echo ""
  echo "To initialize manually, run:"
  echo "mongo \"mongodb://$USERNAME:****@$DOCDB_ENDPOINT:27017/?tls=true&tlsCAFile=rds-ca-2019-root.pem&replicaSet=rs0\" < /tmp/init-docdb.js"
  echo ""
  echo "Or from an EC2 instance in the same VPC:"
  echo "1. Install MongoDB client: sudo yum install -y mongodb-org-shell"
  echo "2. Download CA cert: curl -sS https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o rds-ca-2019-root.pem"
  echo "3. Run the initialization script"
  exit 1
fi

# Determine which mongo client to use
MONGO_CMD=""
if command -v mongosh &> /dev/null; then
  MONGO_CMD="mongosh"
elif command -v mongo &> /dev/null; then
  MONGO_CMD="mongo"
fi

# Run initialization
echo "🚀 Initializing DocumentDB..."
CONNECTION_STRING="mongodb://$USERNAME:$PASSWORD@$DOCDB_ENDPOINT:27017/?tls=true&tlsCAFile=rds-ca-2019-root.pem&replicaSet=rs0"

# Test connection first
echo "Testing connection..."
if $MONGO_CMD "$CONNECTION_STRING" --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
  echo "✅ Connection successful"
  
  # Run initialization script
  $MONGO_CMD "$CONNECTION_STRING" < /tmp/init-docdb.js
  
  # Clean up
  rm -f /tmp/init-docdb.js
  
  echo ""
  echo "✅ DocumentDB initialization complete!"
else
  echo "❌ Failed to connect to DocumentDB"
  echo ""
  echo "This could be because:"
  echo "1. DocumentDB is still starting up (can take 5-10 minutes)"
  echo "2. You're not running from within the VPC"
  echo "3. Security group rules are blocking access"
  echo ""
  echo "Try again in a few minutes or run from an EC2 instance in the same VPC."
  exit 1
fi