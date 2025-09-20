#include "js.h"
#include <iostream>
#include <fstream>
#include <sstream>
#include <cstdio>
#include <cstring>
#include <memory>
#include <stdexcept>
#include <array>
#include <unistd.h>
#include <sys/wait.h>

// Global path to JavaScript source file - set when bytecode is loaded
static thread_local std::string g_jsSourcePath;

JS::JS(void) : memoryLimit(10 * 1024 * 1024) { // Default 10MB
}

JS::~JS(void) {
}

void JS::SetBytecode(const std::vector<char>& bytecode) {
    // In dfuzz mode, we don't use bytecode directly
    // Instead, we'll need to track which JS file this corresponds to
    this->bytecode = std::vector<uint8_t>(
        (uint8_t*)bytecode.data(),
        (uint8_t*)(bytecode.data() + bytecode.size())
    );
}

void JS::SetBytecode(const std::vector<uint8_t>& bytecode) {
    this->bytecode = bytecode;
}

void JS::SetMemoryLimit(const size_t limit) {
    memoryLimit = limit;
}

std::vector<char> JS::LoadFile(const std::string& fn) {
    std::vector<char> buffer;
    std::ifstream file(fn, std::ios::binary | std::ios::ate);
    std::streamsize size = file.tellg();
    if (size <= 0) {
        throw std::runtime_error("LoadFile: Load error");
    }
    file.seekg(0, std::ios::beg);
    
    buffer.resize(size + 1);
    if (!file.read(buffer.data(), size)) {
        throw std::runtime_error("LoadFile: Read error");
    }
    buffer[size] = 0x00;
    
    return buffer;
}

std::vector<uint8_t> JS::CompileJavascript(const std::string& javascriptFilename) {
    // Store the JavaScript filename globally for later use
    g_jsSourcePath = javascriptFilename;
    
    // In dfuzz mode, we don't compile to bytecode
    // Return a marker that contains the filename for tracking
    std::string marker = "DFUZZ_JS:" + javascriptFilename;
    return std::vector<uint8_t>(marker.begin(), marker.end());
}

std::string JS::findJavaScriptFile(const std::string& moduleDir) {
    // Try to find the JavaScript file based on module context
    // Check common locations relative to the module
    std::vector<std::string> candidates = {
        g_jsSourcePath,  // Try global path first
        moduleDir + "/harness.js",
        moduleDir + "/combined.js",
        moduleDir + "/module.js",
        // Add module-specific names
        moduleDir + "/noble-curves.js",
        moduleDir + "/noble-hashes.js",
        moduleDir + "/noble-ed25519.js",
        moduleDir + "/noble-secp256k1.js",
        moduleDir + "/noble-bls12-381.js",
        moduleDir + "/bignumber.js",
        moduleDir + "/bn.js",
        moduleDir + "/crypto-js.js",
        moduleDir + "/elliptic.js",
        moduleDir + "/jsbn.js"
    };
    
    for (const auto& path : candidates) {
        if (access(path.c_str(), F_OK) == 0) {
            return path;
        }
    }
    
    // If no file found, return the global path as fallback
    return g_jsSourcePath.empty() ? "harness.js" : g_jsSourcePath;
}

std::optional<std::string> JS::Run(const std::string& data) {
    return Run(data.c_str(), data.size(), true);
}

std::optional<std::string> JS::Run(const void* data, const size_t size, const bool asString) {
    // Create a wrapper script that will handle the fuzzer execution
    std::string wrapperScript = R"(
// dfuzz bridge wrapper
const input = )" + (asString ? 
        "'" + std::string((const char*)data, size) + "'" : 
        "new Uint8Array([" + [&]() {
            std::string arr;
            const uint8_t* bytes = (const uint8_t*)data;
            for (size_t i = 0; i < size; i++) {
                if (i > 0) arr += ",";
                arr += std::to_string(bytes[i]);
            }
            return arr;
        }() + "])") + R"(;

// Set global for compatibility
var FuzzerInput = input;
var FuzzerOutput = undefined;

// Import and run the original harness
)" + [&]() {
    // Read the original JavaScript file
    std::string jsPath = findJavaScriptFile(".");
    try {
        auto jsContent = LoadFile(jsPath);
        return std::string(jsContent.data());
    } catch (...) {
        return std::string("// Failed to load JavaScript file");
    }
}() + R"(

// Return the output
if (FuzzerOutput !== undefined) {
    console.log(JSON.stringify(FuzzerOutput));
}
)";
    
    // Write wrapper to temp file
    char tmpfile[] = "/tmp/dfuzz_bridge_XXXXXX.js";
    int fd = mkstemps(tmpfile, 3);
    if (fd == -1) {
        return std::nullopt;
    }
    
    FILE* fp = fdopen(fd, "w");
    if (!fp) {
        close(fd);
        return std::nullopt;
    }
    
    fprintf(fp, "%s", wrapperScript.c_str());
    fclose(fp);
    
    // Execute with Deno
    std::string cmd = "deno run --allow-all --quiet " + std::string(tmpfile) + " 2>&1";
    
    // Run command and capture output
    std::array<char, 4096> buffer;
    std::string result;
    
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) {
        unlink(tmpfile);
        return std::nullopt;
    }
    
    while (fgets(buffer.data(), buffer.size(), pipe) != nullptr) {
        result += buffer.data();
    }
    
    int exitCode = pclose(pipe);
    unlink(tmpfile);
    
    if (exitCode != 0) {
        return std::nullopt;
    }
    
    // Remove trailing newline if present
    if (!result.empty() && result.back() == '\n') {
        result.pop_back();
    }
    
    return result.empty() ? std::nullopt : std::make_optional(result);
}