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
#include <filesystem>

namespace fs = std::filesystem;

// Track module context
static thread_local std::string g_moduleContext;
static thread_local std::string g_jsSourcePath;

JS::JS(void) : memoryLimit(10 * 1024 * 1024) {
    // Try to detect module context from current working directory
    char cwd[1024];
    if (getcwd(cwd, sizeof(cwd)) != nullptr) {
        std::string path(cwd);
        if (path.find("/modules/") != std::string::npos) {
            size_t pos = path.find_last_of('/');
            if (pos != std::string::npos) {
                g_moduleContext = path.substr(pos + 1);
            }
        }
    }
}

JS::~JS(void) {
}

void JS::SetBytecode(const std::vector<char>& bytecode) {
    SetBytecode(std::vector<uint8_t>(
        (uint8_t*)bytecode.data(),
        (uint8_t*)(bytecode.data() + bytecode.size())
    ));
}

void JS::SetBytecode(const std::vector<uint8_t>& bytecode) {
    this->bytecode = bytecode;
    
    // Check if this is a dfuzz marker
    std::string marker(bytecode.begin(), bytecode.end());
    if (marker.find("DFUZZ_JS:") == 0) {
        g_jsSourcePath = marker.substr(9);
    }
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
    // Store the JavaScript filename for later use
    g_jsSourcePath = javascriptFilename;
    
    // Create a marker that contains the filename
    std::string marker = "DFUZZ_JS:" + javascriptFilename;
    return std::vector<uint8_t>(marker.begin(), marker.end());
}

std::string JS::findJavaScriptFile(const std::string& hint) {
    // Priority order for finding JS files:
    // 1. Explicit path from CompileJavascript
    // 2. Module-specific built file
    // 3. Common harness.js
    
    std::vector<std::string> searchPaths;
    
    // Add stored path
    if (!g_jsSourcePath.empty()) {
        searchPaths.push_back(g_jsSourcePath);
    }
    
    // Add module-specific paths based on context
    if (!g_moduleContext.empty()) {
        searchPaths.push_back(g_moduleContext + ".js");
        searchPaths.push_back("./" + g_moduleContext + ".js");
    }
    
    // Add common names
    searchPaths.push_back("combined.js");
    searchPaths.push_back("harness.js");
    searchPaths.push_back("module.js");
    
    // Check each path
    for (const auto& path : searchPaths) {
        if (fs::exists(path)) {
            return fs::absolute(path).string();
        }
    }
    
    // Fallback to stored path even if it doesn't exist
    return g_jsSourcePath.empty() ? "harness.js" : g_jsSourcePath;
}

std::optional<std::string> JS::Run(const std::string& data) {
    return Run(data.c_str(), data.size(), true);
}

std::optional<std::string> JS::Run(const void* data, const size_t size, const bool asString) {
    // Find the JavaScript file to execute
    std::string jsPath = findJavaScriptFile("");
    
    // Check if we can use the jsfuzzer-compat directly
    std::string jsfuzzerPath = "/Users/janitor/libfuzzer-js/jsfuzzer";
    if (!fs::exists(jsfuzzerPath)) {
        jsfuzzerPath = "/Users/janitor/libfuzzer-js/jsfuzzer-compat";
    }
    
    // Create input data file
    char inputFile[] = "/tmp/dfuzz_input_XXXXXX";
    int inputFd = mkstemp(inputFile);
    if (inputFd == -1) {
        return std::nullopt;
    }
    
    // Write input data
    if (write(inputFd, data, size) != (ssize_t)size) {
        close(inputFd);
        unlink(inputFile);
        return std::nullopt;
    }
    close(inputFd);
    
    // Create a simple wrapper that sets FuzzerInput and runs the harness
    std::string wrapperScript = R"(
// Load input from file
const fs = typeof Deno !== 'undefined' ? 
    { readFileSync: (path) => Deno.readFileSync(path) } :
    require('fs');

const inputData = fs.readFileSync(')" + std::string(inputFile) + R"(');
const FuzzerInput = )" + (asString ? 
    "new TextDecoder().decode(inputData)" : 
    "new Uint8Array(inputData)") + R"(;

let FuzzerOutput = undefined;

// Load and execute the harness
)" + [&]() {
    try {
        auto jsContent = LoadFile(jsPath);
        return std::string(jsContent.data());
    } catch (...) {
        return std::string("// Error loading: " + jsPath);
    }
}() + R"(

// Output result
if (FuzzerOutput !== undefined) {
    if (typeof FuzzerOutput === 'string') {
        console.log(FuzzerOutput);
    } else {
        console.log(JSON.stringify(FuzzerOutput));
    }
}
)";
    
    // Write wrapper script
    char wrapperFile[] = "/tmp/dfuzz_wrapper_XXXXXX.js";
    int wrapperFd = mkstemps(wrapperFile, 3);
    if (wrapperFd == -1) {
        unlink(inputFile);
        return std::nullopt;
    }
    
    FILE* fp = fdopen(wrapperFd, "w");
    if (!fp) {
        close(wrapperFd);
        unlink(inputFile);
        return std::nullopt;
    }
    
    fprintf(fp, "%s", wrapperScript.c_str());
    fclose(fp);
    
    // Execute with deno directly for better performance
    std::string cmd = "deno run --allow-all --quiet " + std::string(wrapperFile) + " 2>/dev/null";
    
    // Run command and capture output
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) {
        unlink(inputFile);
        unlink(wrapperFile);
        return std::nullopt;
    }
    
    // Read output
    std::string result;
    char buffer[4096];
    while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
        result += buffer;
    }
    
    int exitCode = pclose(pipe);
    
    // Cleanup
    unlink(inputFile);
    unlink(wrapperFile);
    
    if (exitCode != 0) {
        return std::nullopt;
    }
    
    // Remove trailing newline
    while (!result.empty() && (result.back() == '\n' || result.back() == '\r')) {
        result.pop_back();
    }
    
    return result.empty() ? std::nullopt : std::make_optional(result);
}