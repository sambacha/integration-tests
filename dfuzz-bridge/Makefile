# Makefile for dfuzz-bridge
# Builds compatibility layer for replacing libfuzzer-js with dfuzz

CXX ?= clang++
CXXFLAGS = -std=c++17 -O2 -fPIC -Wall

# Build targets
all: libdfuzz-bridge.a to_bytecode

# Build static library
libdfuzz-bridge.a: js_v2.o
	ar rcs libdfuzz-bridge.a js_v2.o
	ranlib libdfuzz-bridge.a

js_v2.o: js_v2.cpp js.h
	$(CXX) $(CXXFLAGS) -c js_v2.cpp -o js_v2.o

# Install targets - replaces libfuzzer-js in LIBFUZZER_JS_PATH
install: all
	@if [ -z "$(LIBFUZZER_JS_PATH)" ]; then \
		echo "Error: LIBFUZZER_JS_PATH not set"; \
		exit 1; \
	fi
	@echo "Installing dfuzz-bridge to $(LIBFUZZER_JS_PATH)"
	# Backup original files if they exist
	@if [ -f "$(LIBFUZZER_JS_PATH)/js.h" ]; then \
		mv "$(LIBFUZZER_JS_PATH)/js.h" "$(LIBFUZZER_JS_PATH)/js.h.backup"; \
	fi
	@if [ -f "$(LIBFUZZER_JS_PATH)/to_bytecode" ]; then \
		mv "$(LIBFUZZER_JS_PATH)/to_bytecode" "$(LIBFUZZER_JS_PATH)/to_bytecode.backup"; \
	fi
	# Install new files
	cp js.h "$(LIBFUZZER_JS_PATH)/"
	cp to_bytecode "$(LIBFUZZER_JS_PATH)/"
	chmod +x "$(LIBFUZZER_JS_PATH)/to_bytecode"
	# Also copy the compiled object for linking
	cp js_v2.o "$(LIBFUZZER_JS_PATH)/js.o"

# Test installation
test: install
	@echo "Testing dfuzz-bridge installation..."
	@echo "const test = 'hello';" > /tmp/test.js
	$(LIBFUZZER_JS_PATH)/to_bytecode /tmp/test.js /tmp/test.bytecode
	@if [ -f /tmp/test.bytecode ]; then \
		echo "✓ to_bytecode works"; \
		rm -f /tmp/test.js /tmp/test.bytecode; \
	else \
		echo "✗ to_bytecode failed"; \
		exit 1; \
	fi

# Clean build artifacts
clean:
	rm -f *.o *.a

# Help target
help:
	@echo "dfuzz-bridge - Drop-in replacement for libfuzzer-js using dfuzz"
	@echo ""
	@echo "Usage:"
	@echo "  make              - Build the bridge library"
	@echo "  make install      - Install to LIBFUZZER_JS_PATH"
	@echo "  make test         - Test the installation"
	@echo "  make clean        - Remove build artifacts"
	@echo ""
	@echo "Environment variables:"
	@echo "  LIBFUZZER_JS_PATH - Path to libfuzzer-js installation (required for install)"
	@echo ""
	@echo "Example:"
	@echo "  export LIBFUZZER_JS_PATH=/path/to/libfuzzer-js"
	@echo "  make install"

.PHONY: all install test clean help