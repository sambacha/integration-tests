#!/bin/bash
set -e

# Setup script for libfuzzer-js using sambacha repository
echo "Setting up libfuzzer-js..."

# Clone the sambacha libfuzzer-js repository
if [ ! -d "libfuzzer-js" ]; then
    echo "Cloning libfuzzer-js from sambacha repository..."
    git clone --depth 1 https://github.com/sambacha/libfuzzer-js.git
fi

cd libfuzzer-js/
echo "Building libfuzzer-js..."
make

# Export the required environment variables
export LIBFUZZER_A_PATH="-fsanitize=fuzzer"
export LIBFUZZER_JS_PATH=$(realpath .)
export LINK_FLAGS="$LINK_FLAGS $LIBFUZZER_JS_PATH/js.o $LIBFUZZER_JS_PATH/quickjs/libquickjs.a"

echo "libfuzzer-js setup complete!"
echo "LIBFUZZER_JS_PATH=$LIBFUZZER_JS_PATH"
cd ../