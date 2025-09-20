#!/bin/bash
# Apply pre-made patches to cryptofuzz submodule
# This script copies fixed files instead of trying to patch them

set -e

echo "========================================="
echo "Applying Cryptofuzz Patches"
echo "========================================="

# Ensure we're in the right directory
if [ ! -d "patches" ] || [ ! -d "cryptofuzz" ]; then
    echo "Error: Must run from integration-tests directory with patches/ and cryptofuzz/ present"
    exit 1
fi

echo ""
echo "1. Applying main Makefile patch..."
cp patches/cryptofuzz/Makefile cryptofuzz/Makefile
echo "   ✅ Applied cryptofuzz/Makefile"

echo ""
echo "2. Applying generate_ids.cpp fixes to all JavaScript modules..."
JS_MODULES=(
    "noble-curves"
    "noble-bls12-381"
    "noble-ed25519"
    "noble-hashes"
    "noble-secp256k1"
    "elliptic"
    "crypto-js"
    "sjcl"
    "bn.js"
)

for module in "${JS_MODULES[@]}"; do
    if [ -d "cryptofuzz/modules/$module" ]; then
        if [ -f "cryptofuzz/modules/$module/generate_ids.cpp" ]; then
            cp patches/cryptofuzz/modules/generate_ids.cpp "cryptofuzz/modules/$module/generate_ids.cpp"
            echo "   ✅ Fixed $module/generate_ids.cpp"
        fi
    fi
done

echo ""
echo "3. Applying module-specific Makefile patches..."

# Apply specific Makefile patches
if [ -f "patches/cryptofuzz/modules/noble-curves-Makefile" ]; then
    cp patches/cryptofuzz/modules/noble-curves-Makefile cryptofuzz/modules/noble-curves/Makefile
    echo "   ✅ Applied noble-curves/Makefile"
fi

if [ -f "patches/cryptofuzz/modules/noble-hashes-Makefile" ]; then
    cp patches/cryptofuzz/modules/noble-hashes-Makefile cryptofuzz/modules/noble-hashes/Makefile
    echo "   ✅ Applied noble-hashes/Makefile"
fi

if [ -f "patches/cryptofuzz/modules/elliptic-Makefile" ]; then
    cp patches/cryptofuzz/modules/elliptic-Makefile cryptofuzz/modules/elliptic/Makefile
    echo "   ✅ Applied elliptic/Makefile"
fi

# Apply the same Makefile pattern to other noble modules
for module in noble-bls12-381 noble-ed25519 noble-secp256k1; do
    if [ -d "cryptofuzz/modules/$module" ] && [ -f "cryptofuzz/modules/$module/Makefile" ]; then
        # Use sed to fix the generate_ids rule in-place
        sed -i.bak 's|$(CXX) $(CXXFLAGS) generate_ids\.cpp -o generate_ids|$(CXX) -Wall -Wextra -Werror -std=c++17 -I ../../include -I ../../fuzzing-headers/include -DFUZZING_HEADERS_NO_IMPL generate_ids.cpp -o generate_ids|' \
            "cryptofuzz/modules/$module/Makefile"
        rm -f "cryptofuzz/modules/$module/Makefile.bak"
        echo "   ✅ Fixed $module/Makefile"
    fi
done

# Also fix crypto-js and sjcl
for module in crypto-js sjcl; do
    if [ -d "cryptofuzz/modules/$module" ] && [ -f "cryptofuzz/modules/$module/Makefile" ]; then
        sed -i.bak 's|$(CXX) $(CXXFLAGS) generate_ids\.cpp -o generate_ids|$(CXX) -Wall -Wextra -Werror -std=c++17 -I ../../include -I ../../fuzzing-headers/include -DFUZZING_HEADERS_NO_IMPL generate_ids.cpp -o generate_ids|' \
            "cryptofuzz/modules/$module/Makefile"
        rm -f "cryptofuzz/modules/$module/Makefile.bak"
        echo "   ✅ Fixed $module/Makefile"
    fi
done

echo ""
echo "4. Pre-generating ids.js files..."

# Pre-generate ids.js for modules that need it
cd cryptofuzz
for module in "${JS_MODULES[@]}"; do
    if [ -d "modules/$module" ] && [ -f "modules/$module/generate_ids.cpp" ]; then
        (
            cd "modules/$module"
            # Try to compile and run generate_ids
            if clang++ -Wall -Wextra -std=c++17 -I ../../include -I ../../fuzzing-headers/include -DFUZZING_HEADERS_NO_IMPL generate_ids.cpp -o generate_ids 2>/dev/null; then
                ./generate_ids > ids.js
                echo "   ✅ Generated ids.js for $module ($(wc -l < ids.js) lines)"
            else
                echo "   ⚠️  Could not generate ids.js for $module (will be built during make)"
            fi
        ) 2>/dev/null || true
    fi
done
cd ..

echo ""
echo "========================================="
echo "✅ All patches applied successfully!"
echo "========================================="
echo ""
echo "The cryptofuzz submodule has been patched with:"
echo "  • Fixed Makefile for cpu_features and helper tools"
echo "  • Fixed generate_ids.cpp format strings"
echo "  • Fixed module Makefiles to avoid fuzzer conflicts"
echo "  • Pre-generated ids.js files where possible"
echo ""
echo "You can now build cryptofuzz normally."
echo ""