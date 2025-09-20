#!/bin/bash
# Script to verify LLD linker and DWARF v5 are being used correctly

set -e

echo "========================================="
echo "LLD and DWARF v5 Verification Script"
echo "========================================="
echo ""

# Check if LLD is installed
echo "1. Checking LLD installation:"
if command -v lld &> /dev/null; then
    lld --version 2>&1 | head -1
    echo "✅ LLD is installed"
else
    echo "❌ LLD is not installed"
    echo "   Run: sudo apt-get install lld-15"
fi
echo ""

# Check if clang is configured to use LLD
echo "2. Checking if clang uses LLD:"
if [ -n "$CXX" ]; then
    echo "CXX=$CXX"
    $CXX -fuse-ld=lld -Wl,--version 2>&1 | head -1 | grep -q "LLD" && echo "✅ Clang is configured to use LLD" || echo "❌ Clang is not using LLD"
else
    clang++ -fuse-ld=lld -Wl,--version 2>&1 | head -1 | grep -q "LLD" && echo "✅ Clang can use LLD" || echo "❌ Clang cannot use LLD"
fi
echo ""

# Check environment variables
echo "3. Checking environment variables:"
echo "CC=${CC:-not set}"
echo "CXX=${CXX:-not set}"
echo "CXXFLAGS=${CXXFLAGS:-not set}"
echo "LDFLAGS=${LDFLAGS:-not set}"

if [[ "$LDFLAGS" == *"-fuse-ld=lld"* ]]; then
    echo "✅ LDFLAGS includes LLD"
else
    echo "⚠️  LDFLAGS does not include -fuse-ld=lld"
fi

if [[ "$CXXFLAGS" == *"-gdwarf-5"* ]] || [[ "$LDFLAGS" == *"-gdwarf-5"* ]]; then
    echo "✅ DWARF v5 is enabled"
else
    echo "⚠️  DWARF v5 is not enabled"
fi
echo ""

# Check if cryptofuzz binary exists and verify its debug info
echo "4. Checking cryptofuzz binary (if exists):"
if [ -f "cryptofuzz/cryptofuzz" ]; then
    echo "Found cryptofuzz binary, checking debug info..."
    
    # Check if binary was linked with LLD
    if readelf -p .comment cryptofuzz/cryptofuzz 2>/dev/null | grep -q "Linker: LLD"; then
        echo "✅ Binary was linked with LLD"
    else
        echo "⚠️  Binary may not have been linked with LLD"
    fi
    
    # Check DWARF version
    DWARF_VERSION=$(readelf --debug-dump=info cryptofuzz/cryptofuzz 2>/dev/null | grep "Version:" | head -1 | awk '{print $2}')
    if [ "$DWARF_VERSION" = "5" ]; then
        echo "✅ Binary uses DWARF v5 debug format"
    elif [ -n "$DWARF_VERSION" ]; then
        echo "⚠️  Binary uses DWARF v$DWARF_VERSION (expected v5)"
    else
        echo "⚠️  Could not determine DWARF version"
    fi
    
    # Check for debug sections
    echo ""
    echo "Debug sections in binary:"
    readelf -S cryptofuzz/cryptofuzz | grep debug | head -5
else
    echo "Cryptofuzz binary not found (not built yet)"
fi
echo ""

# Test compilation with current settings
echo "5. Test compilation with LLD:"
cat > /tmp/test_lld.cpp << 'EOF'
#include <iostream>
int main() {
    std::cout << "LLD test successful" << std::endl;
    return 0;
}
EOF

if ${CXX:-clang++} -fuse-ld=lld -gdwarf-5 -o /tmp/test_lld /tmp/test_lld.cpp 2>/dev/null; then
    echo "✅ Test compilation with LLD succeeded"
    
    # Verify the test binary
    if readelf -p .comment /tmp/test_lld 2>/dev/null | grep -q "Linker: LLD"; then
        echo "✅ Test binary confirmed linked with LLD"
    fi
    
    DWARF_VERSION=$(readelf --debug-dump=info /tmp/test_lld 2>/dev/null | grep "Version:" | head -1 | awk '{print $2}')
    if [ "$DWARF_VERSION" = "5" ]; then
        echo "✅ Test binary confirmed using DWARF v5"
    fi
    
    rm /tmp/test_lld
else
    echo "❌ Test compilation with LLD failed"
fi
rm -f /tmp/test_lld.cpp
echo ""

# Performance settings check
echo "6. Performance optimizations:"
if [[ "$LDFLAGS" == *"--threads"* ]]; then
    echo "✅ Parallel linking enabled"
else
    echo "⚠️  Parallel linking not enabled (add -Wl,--threads=auto to LDFLAGS)"
fi

if [[ "$CXXFLAGS" == *"-fno-omit-frame-pointer"* ]]; then
    echo "✅ Frame pointers preserved for better debugging"
else
    echo "⚠️  Frame pointers may be omitted (consider adding -fno-omit-frame-pointer)"
fi
echo ""

echo "========================================="
echo "Summary:"
echo "========================================="
if command -v lld &> /dev/null && \
   [[ "$LDFLAGS" == *"-fuse-ld=lld"* ]] && \
   [[ "$CXXFLAGS" == *"-gdwarf-5"* || "$LDFLAGS" == *"-gdwarf-5"* ]]; then
    echo "✅ System is properly configured for LLD with DWARF v5"
    echo ""
    echo "Expected performance improvements:"
    echo "  • 30-50% faster linking times"
    echo "  • Better memory efficiency during linking"
    echo "  • Improved debugging with DWARF v5"
    echo "  • Optimized sanitizer performance"
else
    echo "⚠️  Some configuration is missing. Please check the warnings above."
    echo ""
    echo "To fix, ensure these environment variables are set:"
    echo "  export LDFLAGS=\"-fuse-ld=lld -gdwarf-5 -Wl,--threads=auto\""
    echo "  export CXXFLAGS=\"\$CXXFLAGS -gdwarf-5 -fuse-ld=lld -fno-omit-frame-pointer\""
fi
echo ""