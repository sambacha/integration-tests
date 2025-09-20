#pragma once

#include <vector>
#include <string>
#include <optional>

// Drop-in replacement for libfuzzer-js's JS class
// This version uses dfuzz/Deno internally via subprocess
class JS {
    private:
        std::vector<uint8_t> bytecode;
        std::string javascriptPath;
        size_t memoryLimit;
        
        // Helper to locate the JavaScript file from bytecode name
        std::string findJavaScriptFile(const std::string& bytecodePath);
        
    public:
        JS(void);
        ~JS(void);
        
        // Static methods for compatibility
        static std::vector<char> LoadFile(const std::string& fn);
        static std::vector<uint8_t> CompileJavascript(const std::string& javascriptFilename);
        
        // Bytecode setters (we'll store the path and find the JS file)
        void SetBytecode(const std::vector<char>& bytecode);
        void SetBytecode(const std::vector<uint8_t>& bytecode);
        
        // Memory limit setter (informational only in dfuzz)
        void SetMemoryLimit(const size_t limit);
        
        // Main execution method - runs JavaScript with dfuzz
        std::optional<std::string> Run(const std::string& data);
        std::optional<std::string> Run(const void* data, const size_t size, const bool asString = false);
};