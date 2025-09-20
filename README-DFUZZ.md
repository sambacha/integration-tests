# Using dfuzz with Cryptofuzz

Simple setup to use dfuzz (Deno-based) instead of libfuzzer-js for JavaScript fuzzing.

## Quick Setup

```bash
# Run setup script
./setup-dfuzz.sh

# Set environment variables
export LIBFUZZER_JS_PATH=$PWD/dfuzz-bridge
export LINK_FLAGS=$LIBFUZZER_JS_PATH/js.o

# Build cryptofuzz modules
cd cryptofuzz
python3 gen_repository.py
cd modules/noble-curves
make
```

## GitHub Actions

Add to your workflow:

```yaml
- name: Setup dfuzz
  uses: ./.github/actions/setup-dfuzz

- name: Build with dfuzz
  run: |
    cd cryptofuzz
    make
```

Or use the complete workflow:

```yaml
- uses: ./.github/workflows/dfuzz.yml
```

## Files

- `setup-dfuzz.sh` - Local setup script
- `.github/workflows/dfuzz.yml` - GitHub workflow
- `.github/actions/setup-dfuzz/` - Reusable action

## Requirements

- Deno 1.45+
- clang/clang++
- Python 3
- xxd

## How It Works

dfuzz provides a compatibility layer that:
1. Replaces QuickJS with Deno/V8
2. Maintains the same C++ API (`js.h`)
3. Runs JavaScript directly (no bytecode compilation)

## Supported Modules

All JavaScript cryptofuzz modules work with dfuzz:
- noble-curves
- noble-hashes
- bn.js
- elliptic
- crypto-js
- And others...

## Notes

- dfuzz uses V8 instead of QuickJS (faster execution)
- No actual bytecode compilation (JS files are copied directly)
- Compatible with existing cryptofuzz build system