#!/bin/bash
set -e

echo "Applying noble-curves fixes..."

# Apply the patch to fix import paths and format specifiers
if [ -f noble-curves-fixes.patch ]; then
    cd cryptofuzz
    patch -p1 < ../noble-curves-fixes.patch
    cd ..
fi

# Build noble-curves module
cd cryptofuzz/modules/noble-curves

# Install dependencies if needed
if [ ! -d node_modules ]; then
    npm install
fi

# Generate ids.js
make ids.js

# Build the module
npm run build

echo "Noble-curves fixes applied successfully"