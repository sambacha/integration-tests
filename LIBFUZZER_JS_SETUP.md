# LibFuzzer-JS Setup

This project uses a fork of libfuzzer-js from https://github.com/sambacha/libfuzzer-js

## Quick Setup

To build cryptofuzz with JavaScript fuzzing support:

```bash
# Set the environment variable to enable libfuzzer-js setup
export SETUP_LIBFUZZER_JS=1

# Run the build script
./cryptofuzz-build.sh
```

## Manual Setup

If you need to set up libfuzzer-js manually:

```bash
# Run the setup script
./setup-libfuzzer-js.sh

# Or manually:
git clone --depth 1 https://github.com/sambacha/libfuzzer-js.git
cd libfuzzer-js/
make
export LIBFUZZER_JS_PATH=$(realpath .)
export LINK_FLAGS="$LINK_FLAGS $LIBFUZZER_JS_PATH/js.o $LIBFUZZER_JS_PATH/quickjs/libquickjs.a"
cd ../
```

## Patches

The `libfuzzer-js.patch` file contains documentation updates to use the sambacha repository instead of the original guidovranken repository. This patch is automatically applied during the build process.

## JavaScript Modules

The following JavaScript fuzzing modules require libfuzzer-js:
- noble-curves
- noble-hashes  
- noble-ed25519
- noble-secp256k1
- noble-bls12-381
- elliptic
- sjcl
- crypto-js
- bn.js
- bignumber.js
- jsbn
- quickjs

These modules will only build if `LIBFUZZER_JS_PATH` is set in the environment.