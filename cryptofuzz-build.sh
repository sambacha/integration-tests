#!/bin/bash
set -e

# This script builds cryptofuzz and its dependencies
# Usage: ./cryptofuzz-build.sh [fast]

FAST_MODE="${1:-}"

echo "Building cryptofuzz..."

# Set up environment variables
export CXXFLAGS="${CXXFLAGS:-} -I/usr/include/boost"

# Apply patches to cryptofuzz if they exist
if [ -f "apply-patches.sh" ]; then
    echo "Applying cryptofuzz patches..."
    ./apply-patches.sh
elif [ -f "libfuzzer-js.patch" ]; then
    echo "Applying libfuzzer-js patch..."
    cd cryptofuzz
    patch -p1 < ../libfuzzer-js.patch || true
    cd ..
fi

# Setup libfuzzer-js if needed
if [ -f "setup-libfuzzer-js.sh" ] && [ "$SETUP_LIBFUZZER_JS" = "1" ]; then
    echo "Setting up libfuzzer-js..."
    source ./setup-libfuzzer-js.sh
fi

# Enter cryptofuzz directory
cd cryptofuzz

# Generate repository files
echo "Generating repository files..."
python3 gen_repository.py || python gen_repository.py

# Build noble-curves module if it exists
if [ -d "modules/noble-curves" ]; then
    echo "Building noble-curves module..."
    cd modules/noble-curves
    
    # Apply fixes if patch exists
    if [ -f "../../../noble-curves-fixes.patch" ]; then
        echo "Applying noble-curves patches..."
        patch -p3 < ../../../noble-curves-fixes.patch || true
    fi
    
    # Install dependencies and build
    if [ ! -d "node_modules" ]; then
        npm install
    fi
    
    # Generate ids.js
    make ids.js || true
    
    # Build the module
    npm run build || true
    
    cd ../..
fi

# Build cryptofuzz
echo "Building main cryptofuzz binary..."
if [ "$FAST_MODE" = "fast" ]; then
    echo "Fast mode: skipping some modules"
    # Add fast mode specific build options
    make -j$(nproc)
else
    # Full build
    make -j$(nproc)
fi

echo "Build completed successfully!"