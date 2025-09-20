#!/bin/bash
# Simple script to setup dfuzz as libfuzzer-js replacement

set -e

echo "Setting up dfuzz..."

# Install Deno if not present
if ! command -v deno &> /dev/null; then
    echo "Installing Deno..."
    curl -fsSL https://deno.land/install.sh | sh
    export PATH="$HOME/.deno/bin:$PATH"
fi

# Create dfuzz-bridge directory
mkdir -p dfuzz-bridge
cd dfuzz-bridge

# Create minimal jsfuzzer compatibility
cat > jsfuzzer-compat.ts << 'EOF'
#!/usr/bin/env -S deno run --allow-all
// Minimal dfuzz compatibility layer for cryptofuzz
const args = Deno.args;
let jsFile = "";

for (const arg of args) {
  if (arg.startsWith("--js=")) {
    jsFile = arg.substring(5);
  }
}

if (jsFile) {
  const code = await Deno.readTextFile(jsFile);
  // Execute the fuzzer code
  eval(code);
}
EOF

# Compile jsfuzzer
deno compile --allow-all --output jsfuzzer jsfuzzer-compat.ts

# Create js.cpp bridge
cat > js.cpp << 'EOF'
#include "js.h"
#include <cstdlib>
#include <fstream>

JS::JS() {}
JS::~JS() {}

void JS::SetBytecode(const std::vector<uint8_t>& bytecode) {
    jsSource = bytecode;
}

std::optional<std::string> JS::Run(const std::string& input) {
    std::ofstream out("/tmp/fuzzer.js");
    out.write((char*)jsSource.data(), jsSource.size());
    out.close();
    
    std::string cmd = "echo '" + input + "' | ./dfuzz-bridge/jsfuzzer --js=/tmp/fuzzer.js 2>&1";
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) return std::nullopt;
    
    std::string result;
    char buffer[256];
    while (fgets(buffer, sizeof(buffer), pipe)) {
        result += buffer;
    }
    pclose(pipe);
    return result;
}
EOF

# Create js.h
cat > js.h << 'EOF'
#ifndef JS_H
#define JS_H
#include <vector>
#include <string>
#include <optional>

class JS {
    std::vector<uint8_t> jsSource;
public:
    JS();
    ~JS();
    void SetBytecode(const std::vector<uint8_t>& bytecode);
    std::optional<std::string> Run(const std::string& input);
};
#endif
EOF

# Create to_bytecode script
cat > to_bytecode << 'EOF'
#!/bin/bash
# dfuzz: just copy JS file as "bytecode"
cp "$1" "$2"
EOF
chmod +x to_bytecode

# Compile js.o
clang++ -c js.cpp -o js.o -std=c++17 -fPIC

cd ..

echo ""
echo "✅ dfuzz setup complete!"
echo ""
echo "To use dfuzz with cryptofuzz:"
echo "  export LIBFUZZER_JS_PATH=$PWD/dfuzz-bridge"
echo "  export LINK_FLAGS=\$LIBFUZZER_JS_PATH/js.o"
echo "  export LIBFUZZER_LINK=\"-fsanitize=fuzzer\""
echo ""