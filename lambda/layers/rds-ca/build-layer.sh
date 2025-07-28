#!/bin/bash

# Build script for RDS CA certificate Lambda layer
# This creates a Lambda layer with AWS RDS CA certificates

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="${SCRIPT_DIR}/build"

echo "Building RDS CA certificate Lambda layer..."

# Clean up any existing build
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Download RDS CA certificates
echo "Downloading AWS RDS CA certificates..."
cd "${BUILD_DIR}"

# Download the global bundle that works with all regions
curl -sS "https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem" -o rds-ca-2019-root.pem

# Create the layer structure - certificates go in /opt
mkdir -p opt
mv rds-ca-2019-root.pem opt/

# Create the zip file
zip -r9 "${SCRIPT_DIR}/rds-ca-layer.zip" opt/

# Clean up build directory
rm -rf "${BUILD_DIR}"

echo "RDS CA certificate Lambda layer built successfully: ${SCRIPT_DIR}/rds-ca-layer.zip"
echo "Layer size: $(du -h "${SCRIPT_DIR}/rds-ca-layer.zip" | cut -f1)"