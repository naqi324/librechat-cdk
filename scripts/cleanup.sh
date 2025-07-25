#!/bin/bash
# cleanup.sh - Clean up all LibreChat resources

echo "⚠️  WARNING: This will delete all LibreChat resources!"
read -p "Are you sure? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled"
    exit 0
fi

STACK_NAME=${1:-LibreChatStack}

echo "Deleting CloudFormation stack: $STACK_NAME"
aws cloudformation delete-stack --stack-name "$STACK_NAME"

echo "Waiting for stack deletion..."
aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"

echo "✅ Cleanup complete"
