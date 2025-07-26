#!/bin/bash
# Build Lambda deployment package with dependencies

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Building Lambda deployment package...${NC}"

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Clean up any existing build
rm -rf package python *.zip

# Create a directory for the package
mkdir -p python

# Install dependencies into the package directory
pip install -r requirements.txt -t python/ --platform manylinux2014_x86_64 --only-binary=:all: --python-version 3.11

# Copy the Lambda function
cp init_postgres.py python/

# Create the deployment package
cd python
zip -r ../lambda-package.zip .
cd ..

# Clean up
rm -rf python

echo -e "${GREEN}✅ Lambda package created: lambda-package.zip${NC}"