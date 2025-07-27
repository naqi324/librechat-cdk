#!/bin/bash
# Build psycopg2 Lambda layer without Docker

set -e

LAYER_DIR="python/lib/python3.11/site-packages"

echo "Building psycopg2 Lambda layer..."

# Clean previous build
rm -rf python psycopg2-layer.zip

# Create directory structure
mkdir -p $LAYER_DIR

# Install psycopg2-binary into the layer directory
pip3 install psycopg2-binary==2.9.9 --target $LAYER_DIR --platform manylinux2014_x86_64 --only-binary=:all: --implementation cp --python-version 3.11

# Create the layer zip
zip -r psycopg2-layer.zip python

# Clean up
rm -rf python

echo "Layer built successfully: psycopg2-layer.zip"
echo "Size: $(du -h psycopg2-layer.zip | cut -f1)"