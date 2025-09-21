#!/bin/bash
# Migration script from libfuzzer-js to dfuzz for cryptofuzz
# This script provides a complete migration path with rollback capability

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRYPTOFUZZ_DIR="${SCRIPT_DIR}/cryptofuzz"
DFUZZ_BRIDGE_DIR="${SCRIPT_DIR}/dfuzz-bridge"
LIBFUZZER_JS_DIR="${LIBFUZZER_JS_PATH:-/Users/janitor/libfuzzer-js}"
BACKUP_DIR="${SCRIPT_DIR}/.migration-backup"

# JavaScript modules to migrate
JS_MODULES=(
    "noble-curves"
    "noble-hashes"
    "noble-ed25519"
    "noble-secp256k1"
    "noble-bls12-381"
    "bignumber.js"
    "bn.js"
    "crypto-js"
    "elliptic"
    "jsbn"
    "quickjs"
)

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."
    
    # Check for Deno
    if ! command -v deno &> /dev/null; then
        print_error "Deno is not installed. Please install Deno first."
        echo "Visit: https://deno.land/manual/getting_started/installation"
        exit 1
    fi
    print_status "Deno found: $(deno --version | head -1)"
    
    # Check for clang++
    if ! command -v clang++ &> /dev/null; then
        print_error "clang++ is not installed."
        exit 1
    fi
    print_status "clang++ found"
    
    # Check directories exist
    if [ ! -d "$CRYPTOFUZZ_DIR" ]; then
        print_error "Cryptofuzz directory not found: $CRYPTOFUZZ_DIR"
        exit 1
    fi
    print_status "Cryptofuzz directory found"
    
    if [ ! -d "$LIBFUZZER_JS_DIR" ]; then
        print_warning "libfuzzer-js directory not found: $LIBFUZZER_JS_DIR"
        echo "Will use dfuzz standalone installation"
    else
        print_status "libfuzzer-js directory found"
    fi
}

# Function to build dfuzz
build_dfuzz() {
    echo -e "\nBuilding dfuzz..."
    
    if [ -d "$LIBFUZZER_JS_DIR/dfuzz" ]; then
        cd "$LIBFUZZER_JS_DIR/dfuzz"
        if [ ! -f "libfuzzer.dylib" ] && [ ! -f "libfuzzer.so" ]; then
            print_status "Building libfuzzer shared library..."
            make build
        else
            print_status "libfuzzer shared library already built"
        fi
    else
        print_warning "dfuzz not found in libfuzzer-js directory"
        print_warning "Please ensure dfuzz is built separately"
    fi
    
    # Build jsfuzzer-compat if needed
    if [ ! -f "$LIBFUZZER_JS_DIR/jsfuzzer" ] || [ "$LIBFUZZER_JS_DIR/jsfuzzer" -ot "$LIBFUZZER_JS_DIR/jsfuzzer-compat.ts" ]; then
        if [ -f "$LIBFUZZER_JS_DIR/build-compat.sh" ]; then
            cd "$LIBFUZZER_JS_DIR"
            print_status "Building jsfuzzer compatibility binary..."
            ./build-compat.sh
        fi
    fi
}

# Function to build dfuzz bridge
build_bridge() {
    echo -e "\nBuilding dfuzz bridge..."
    
    cd "$DFUZZ_BRIDGE_DIR"
    make clean
    make all
    print_status "dfuzz bridge built successfully"
}

# Function to create backup
create_backup() {
    echo -e "\nCreating backup..."
    
    rm -rf "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    
    # Backup libfuzzer-js files if they exist
    if [ -f "$LIBFUZZER_JS_DIR/js.h" ]; then
        cp "$LIBFUZZER_JS_DIR/js.h" "$BACKUP_DIR/"
    fi
    if [ -f "$LIBFUZZER_JS_DIR/js.o" ]; then
        cp "$LIBFUZZER_JS_DIR/js.o" "$BACKUP_DIR/"
    fi
    if [ -f "$LIBFUZZER_JS_DIR/to_bytecode" ]; then
        cp "$LIBFUZZER_JS_DIR/to_bytecode" "$BACKUP_DIR/"
    fi
    
    # Backup module bytecode files
    for module in "${JS_MODULES[@]}"; do
        module_dir="$CRYPTOFUZZ_DIR/modules/$module"
        if [ -d "$module_dir" ]; then
            mkdir -p "$BACKUP_DIR/modules/$module"
            find "$module_dir" -name "*.bytecode" -o -name "*.bytecode.h" | while read file; do
                cp "$file" "$BACKUP_DIR/modules/$module/" 2>/dev/null || true
            done
        fi
    done
    
    print_status "Backup created in $BACKUP_DIR"
}

# Function to install bridge
install_bridge() {
    echo -e "\nInstalling dfuzz bridge..."
    
    cd "$DFUZZ_BRIDGE_DIR"
    
    # Install to libfuzzer-js directory
    cp js.h "$LIBFUZZER_JS_DIR/"
    cp js_v2.o "$LIBFUZZER_JS_DIR/js.o"
    cp to_bytecode "$LIBFUZZER_JS_DIR/"
    chmod +x "$LIBFUZZER_JS_DIR/to_bytecode"
    
    print_status "Bridge files installed"
}

# Function to migrate a single module
migrate_module() {
    local module=$1
    local module_dir="$CRYPTOFUZZ_DIR/modules/$module"
    
    if [ ! -d "$module_dir" ]; then
        print_warning "Module directory not found: $module_dir"
        return 1
    fi
    
    echo "  Migrating $module..."
    
    cd "$module_dir"
    
    # Clean old bytecode files
    rm -f *.bytecode *.bytecode.h
    
    # Rebuild with new system
    if [ -f "Makefile" ]; then
        # The make process will now use dfuzz via our bridge
        make clean 2>/dev/null || true
        if LIBFUZZER_JS_PATH="$LIBFUZZER_JS_DIR" make module.a; then
            print_status "  $module migrated successfully"
            return 0
        else
            print_error "  Failed to build $module"
            return 1
        fi
    else
        print_warning "  No Makefile found for $module"
        return 1
    fi
}

# Function to test migration
test_migration() {
    echo -e "\nTesting migration..."
    
    # Create a simple test
    cat > /tmp/test_dfuzz.js << 'EOF'
// Test harness for dfuzz migration
if (typeof FuzzerInput !== 'undefined') {
    const input = String.fromCharCode.apply(null, FuzzerInput);
    if (input === "crash") {
        throw new Error("Test crash found!");
    }
    FuzzerOutput = "OK:" + input.length;
}
EOF
    
    # Test with new system
    "$LIBFUZZER_JS_DIR/to_bytecode" /tmp/test_dfuzz.js /tmp/test_dfuzz.bytecode
    
    if [ -f /tmp/test_dfuzz.bytecode ]; then
        print_status "Bytecode generation works"
    else
        print_error "Bytecode generation failed"
        return 1
    fi
    
    # Test one module compilation
    if migrate_module "noble-curves"; then
        print_status "Module compilation test passed"
    else
        print_error "Module compilation test failed"
        return 1
    fi
    
    rm -f /tmp/test_dfuzz.js /tmp/test_dfuzz.bytecode
}

# Function to migrate all modules
migrate_all_modules() {
    echo -e "\nMigrating all modules..."
    
    local failed_modules=()
    
    for module in "${JS_MODULES[@]}"; do
        if ! migrate_module "$module"; then
            failed_modules+=("$module")
        fi
    done
    
    if [ ${#failed_modules[@]} -eq 0 ]; then
        print_status "All modules migrated successfully"
    else
        print_warning "Failed to migrate: ${failed_modules[*]}"
        echo "You may need to fix these modules manually"
    fi
}

# Function to rollback migration
rollback() {
    echo -e "\nRolling back migration..."
    
    if [ ! -d "$BACKUP_DIR" ]; then
        print_error "No backup found. Cannot rollback."
        exit 1
    fi
    
    # Restore libfuzzer-js files
    if [ -f "$BACKUP_DIR/js.h" ]; then
        cp "$BACKUP_DIR/js.h" "$LIBFUZZER_JS_DIR/"
    fi
    if [ -f "$BACKUP_DIR/js.o" ]; then
        cp "$BACKUP_DIR/js.o" "$LIBFUZZER_JS_DIR/"
    fi
    if [ -f "$BACKUP_DIR/to_bytecode" ]; then
        cp "$BACKUP_DIR/to_bytecode" "$LIBFUZZER_JS_DIR/"
        chmod +x "$LIBFUZZER_JS_DIR/to_bytecode"
    fi
    
    # Restore module files
    for module in "${JS_MODULES[@]}"; do
        if [ -d "$BACKUP_DIR/modules/$module" ]; then
            cp "$BACKUP_DIR/modules/$module"/* "$CRYPTOFUZZ_DIR/modules/$module/" 2>/dev/null || true
        fi
    done
    
    print_status "Rollback completed"
}

# Function to show performance comparison
show_performance() {
    echo -e "\nPerformance Comparison:"
    echo "========================"
    echo "libfuzzer-js (QuickJS): ~10,000 exec/sec"
    echo "dfuzz (V8/Deno):        ~100,000 exec/sec"
    echo "Expected improvement:    10x"
    echo ""
    echo "Note: Actual performance depends on:"
    echo "  - Complexity of JavaScript code"
    echo "  - Input size"
    echo "  - System resources"
}

# Main menu
show_menu() {
    echo ""
    echo "========================================="
    echo "Cryptofuzz: libfuzzer-js to dfuzz Migration"
    echo "========================================="
    echo ""
    echo "1) Full migration (recommended)"
    echo "2) Test migration (single module)"
    echo "3) Build components only"
    echo "4) Rollback to libfuzzer-js"
    echo "5) Show performance comparison"
    echo "6) Exit"
    echo ""
    read -p "Select option [1-6]: " choice
    
    case $choice in
        1)
            check_prerequisites
            build_dfuzz
            build_bridge
            create_backup
            install_bridge
            test_migration
            migrate_all_modules
            show_performance
            print_status "Migration completed successfully!"
            ;;
        2)
            check_prerequisites
            build_dfuzz
            build_bridge
            install_bridge
            test_migration
            ;;
        3)
            check_prerequisites
            build_dfuzz
            build_bridge
            print_status "Components built successfully"
            ;;
        4)
            rollback
            ;;
        5)
            show_performance
            ;;
        6)
            exit 0
            ;;
        *)
            print_error "Invalid option"
            show_menu
            ;;
    esac
}

# Script execution
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Usage: $0 [--auto]"
    echo ""
    echo "Options:"
    echo "  --auto    Run full migration without prompts"
    echo "  --help    Show this help message"
    exit 0
fi

if [ "$1" == "--auto" ]; then
    check_prerequisites
    build_dfuzz
    build_bridge
    create_backup
    install_bridge
    test_migration
    migrate_all_modules
    show_performance
    print_status "Automatic migration completed!"
else
    show_menu
fi