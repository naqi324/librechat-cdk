#!/bin/bash

# Build script for pymongo Lambda layer
# This creates a Lambda layer with pymongo and its dependencies

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="${SCRIPT_DIR}/build"
LAYER_DIR="${BUILD_DIR}/python"

echo "Building pymongo Lambda layer..."

# Clean up any existing build
rm -rf "${BUILD_DIR}"
mkdir -p "${LAYER_DIR}"

# Create a temporary requirements file
cat > "${BUILD_DIR}/requirements.txt" << EOF
pymongo==4.6.1
dnspython==2.4.2
EOF

# Install packages to the layer directory
python3 -m pip install -r "${BUILD_DIR}/requirements.txt" \
    --target "${LAYER_DIR}" \
    --platform manylinux2014_x86_64 \
    --python-version 3.11 \
    --only-binary :all: \
    --upgrade

# Remove unnecessary files to reduce layer size
find "${LAYER_DIR}" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "${LAYER_DIR}" -type f -name "*.pyc" -delete
find "${LAYER_DIR}" -type f -name "*.pyo" -delete
find "${LAYER_DIR}" -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
find "${LAYER_DIR}" -type d -name "test" -exec rm -rf {} + 2>/dev/null || true

# Create the zip file
cd "${BUILD_DIR}"
zip -r9 "${SCRIPT_DIR}/pymongo-layer.zip" python/

# Clean up build directory
rm -rf "${BUILD_DIR}"

echo "pymongo Lambda layer built successfully: ${SCRIPT_DIR}/pymongo-layer.zip"
echo "Layer size: $(du -h "${SCRIPT_DIR}/pymongo-layer.zip" | cut -f1)"