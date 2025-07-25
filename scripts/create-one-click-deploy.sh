#!/bin/bash
# create-one-click-deploy.sh - Create a one-click deployment link

REGION=${1:-us-east-1}
BUCKET_NAME="librechat-templates-$(aws sts get-caller-identity --query Account --output text)"

# Create S3 bucket for templates
aws s3 mb "s3://${BUCKET_NAME}" --region "$REGION" 2>/dev/null || true

# Generate and upload template
npm run build
cdk synth --no-staging > librechat-cloudformation.yaml

aws s3 cp librechat-cloudformation.yaml "s3://${BUCKET_NAME}/librechat-latest.yaml" \
    --acl public-read

# Generate one-click deploy URL
TEMPLATE_URL="https://${BUCKET_NAME}.s3.${REGION}.amazonaws.com/librechat-latest.yaml"
STACK_NAME="LibreChat-Production"

CONSOLE_URL="https://console.aws.amazon.com/cloudformation/home?region=${REGION}#/stacks/new?stackName=${STACK_NAME}&templateURL=${TEMPLATE_URL}"

echo "✅ One-click deployment URL generated:"
echo ""
echo "$CONSOLE_URL"
echo ""
echo "Share this URL for easy deployment!"
