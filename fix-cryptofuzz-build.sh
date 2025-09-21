#!/bin/bash
# Script to apply build fixes to cryptofuzz submodule
# These fixes are necessary for successful builds but can't be committed to the submodule

set -e

echo "========================================="
echo "Applying Cryptofuzz Build Fixes"
echo "========================================="

# Ensure we're in the right directory
if [ ! -f "cryptofuzz/Makefile" ]; then
    echo "Error: cryptofuzz/Makefile not found. Run this from the integration-tests directory."
    exit 1
fi

cd cryptofuzz

echo ""
echo "1. Fixing main Makefile for cpu_features and helper tools..."

# Fix 1: cpu_features build without fuzzer flags
sed -i.bak 's|cd third_party/cpu_features && rm -rf build && mkdir build && cd build && cmake \.\. && make|cd third_party/cpu_features \&\& rm -rf build \&\& mkdir build \&\& cd build \&\& CC=clang-15 CXX=clang++-15 CFLAGS="" CXXFLAGS="" LDFLAGS="" cmake .. \&\& make|' Makefile

# Fix 2: generate_dict and generate_corpus without fuzzer flags
sed -i.bak2 's|$(CXX) $(CXXFLAGS) generate_dict\.cpp -o generate_dict|$(CXX) -Wall -Wextra -std=c++17 -I include/ -I . -I fuzzing-headers/include -DFUZZING_HEADERS_NO_IMPL generate_dict.cpp -o generate_dict|' Makefile

sed -i.bak3 's|$(CXX) $(CXXFLAGS) generate_corpus\.cpp -o generate_corpus|$(CXX) -Wall -Wextra -std=c++17 -I include/ -I . -I fuzzing-headers/include -DFUZZING_HEADERS_NO_IMPL generate_corpus.cpp -o generate_corpus|' Makefile

# Fix 3: Add LDFLAGS to final linking step
sed -i.bak4 's|$(CXX) $(CXXFLAGS) $(OBJECT_FILES)|$(CXX) $(CXXFLAGS) $(LDFLAGS) $(OBJECT_FILES)|' Makefile

# Clean up backup files
rm -f Makefile.bak*

echo "✅ Makefile fixes applied"

echo ""
echo "2. Fixing generate_ids.cpp format strings in all JavaScript modules..."

# Fix format string issues in all JS modules
for module in modules/noble-* modules/elliptic modules/crypto-js modules/sjcl modules/bn.js; do
    if [ -f "$module/generate_ids.cpp" ]; then
        echo "   Fixing $module/generate_ids.cpp..."
        
        # Fix format specifiers from %zu to %llu
        sed -i.bak 's/%zu/%llu/g' "$module/generate_ids.cpp"
        
        # Add cast to (unsigned long long) for item.first
        sed -i.bak2 's/item\.first)/(unsigned long long)item.first)/g' "$module/generate_ids.cpp"
        
        # Clean up backup files
        rm -f "$module/generate_ids.cpp.bak"*
    fi
done

echo "✅ Format string fixes applied"

echo ""
echo "3. Fixing module Makefiles to avoid fuzzer flags for generate_ids..."

# Fix Makefiles in JS modules to compile generate_ids without fuzzer flags
for module in modules/noble-* modules/elliptic modules/crypto-js modules/sjcl; do
    if [ -f "$module/Makefile" ]; then
        echo "   Fixing $module/Makefile..."
        
        # Replace generate_ids compilation to use explicit flags without fuzzer
        sed -i.bak 's|$(CXX) $(CXXFLAGS) generate_ids\.cpp -o generate_ids|$(CXX) -Wall -Wextra -Werror -std=c++17 -I ../../include -I ../../fuzzing-headers/include -DFUZZING_HEADERS_NO_IMPL generate_ids.cpp -o generate_ids|' "$module/Makefile"
        
        # Clean up backup files
        rm -f "$module/Makefile.bak"
    fi
done

echo "✅ Module Makefile fixes applied"

echo ""
echo "4. Pre-generating ids.js for modules that need it..."

# Pre-generate ids.js for modules to avoid build failures
for module in modules/noble-curves modules/noble-hashes modules/elliptic modules/crypto-js; do
    if [ -f "$module/generate_ids.cpp" ] && [ -f "$module/Makefile" ]; then
        echo "   Generating ids.js for $module..."
        (
            cd "$module"
            # Compile generate_ids if it doesn't exist
            if [ ! -f "generate_ids" ]; then
                clang++ -Wall -Wextra -Werror -std=c++17 -I ../../include -I ../../fuzzing-headers/include -DFUZZING_HEADERS_NO_IMPL generate_ids.cpp -o generate_ids 2>/dev/null || \
                clang++ -Wall -Wextra -std=c++17 -I ../../include -I ../../fuzzing-headers/include -DFUZZING_HEADERS_NO_IMPL generate_ids.cpp -o generate_ids
            fi
            # Generate ids.js
            if [ -f "generate_ids" ]; then
                ./generate_ids > ids.js
                echo "      ✅ Generated ids.js ($(wc -l < ids.js) lines)"
            fi
        )
    fi
done

cd ..

echo ""
echo "========================================="
echo "✅ All Cryptofuzz build fixes applied!"
echo "========================================="
echo ""
echo "You can now build cryptofuzz with:"
echo "  cd cryptofuzz && make -j\$(nproc)"
echo ""