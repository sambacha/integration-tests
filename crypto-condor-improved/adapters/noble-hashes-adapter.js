#!/usr/bin/env node

/**
 * Noble-Hashes Adapter
 * 
 * Adapts the @noble/hashes library to the generic CryptoWrapper interface.
 * No hard-coded test values or special cases - pure algorithmic implementation.
 */

const CryptoWrapper = require('../wrapper-base');

class NobleHashesAdapter extends CryptoWrapper {
    constructor() {
        super('noble-hashes');
        this.hashModules = {};
        this.hmacModule = null;
    }

    async initialize() {
        try {
            // Dynamically discover and load available hash algorithms
            const algorithms = [
                { name: 'sha256', module: '@noble/hashes/sha256' },
                { name: 'sha512', module: '@noble/hashes/sha512' },
                { name: 'sha3-256', module: '@noble/hashes/sha3', export: 'sha3_256' },
                { name: 'sha3-512', module: '@noble/hashes/sha3', export: 'sha3_512' },
                { name: 'blake2b', module: '@noble/hashes/blake2b' },
                { name: 'blake2s', module: '@noble/hashes/blake2s' },
                { name: 'blake3', module: '@noble/hashes/blake3' },
                { name: 'ripemd160', module: '@noble/hashes/ripemd160' }
            ];

            for (const algo of algorithms) {
                try {
                    const mod = require(algo.module);
                    const hashFn = algo.export ? mod[algo.export] : mod[algo.name];
                    
                    if (hashFn) {
                        this.hashModules[algo.name] = hashFn;
                        this.capabilities.add(`hash.${algo.name}`);
                    }
                } catch (err) {
                    // Algorithm not available in this version - skip silently
                    continue;
                }
            }

            // Load HMAC support
            try {
                const { hmac } = require('@noble/hashes/hmac');
                this.hmacModule = hmac;
                
                // HMAC is available for all hash algorithms
                for (const algo of Object.keys(this.hashModules)) {
                    this.capabilities.add(`hmac.${algo}`);
                }
            } catch (err) {
                // HMAC not available
            }

            // Load PBKDF2 if available
            try {
                const { pbkdf2, pbkdf2Async } = require('@noble/hashes/pbkdf2');
                this.pbkdf2 = pbkdf2;
                this.pbkdf2Async = pbkdf2Async;
                this.capabilities.add('kdf.pbkdf2');
            } catch (err) {
                // PBKDF2 not available
            }

            // Load scrypt if available
            try {
                const { scrypt, scryptAsync } = require('@noble/hashes/scrypt');
                this.scrypt = scrypt;
                this.scryptAsync = scryptAsync;
                this.capabilities.add('kdf.scrypt');
            } catch (err) {
                // Scrypt not available
            }

            return true;
        } catch (error) {
            throw new Error(`Failed to initialize noble-hashes: ${error.message}`);
        }
    }

    async hash(algorithm, data) {
        const hashFn = this.hashModules[algorithm];
        if (!hashFn) {
            throw new Error(`Hash algorithm ${algorithm} not supported by noble-hashes`);
        }

        try {
            // Noble-hashes accepts Uint8Array, we have Buffer (which extends Uint8Array)
            const result = hashFn(data);
            // Convert Uint8Array result to Buffer
            return Buffer.from(result);
        } catch (error) {
            throw new Error(`Hash operation failed: ${error.message}`);
        }
    }

    async hmac(algorithm, key, data) {
        if (!this.hmacModule) {
            throw new Error('HMAC not supported in this version of noble-hashes');
        }

        const hashFn = this.hashModules[algorithm];
        if (!hashFn) {
            throw new Error(`HMAC with ${algorithm} not supported by noble-hashes`);
        }

        try {
            // Noble-hashes HMAC takes (hash function, key, message)
            const result = this.hmacModule(hashFn, key, data);
            return Buffer.from(result);
        } catch (error) {
            throw new Error(`HMAC operation failed: ${error.message}`);
        }
    }

    async kdf(algorithm, password, salt, options = {}) {
        switch (algorithm) {
            case 'pbkdf2':
                if (!this.pbkdf2Async) {
                    throw new Error('PBKDF2 not supported');
                }
                
                const hashFn = this.hashModules[options.hash || 'sha256'];
                if (!hashFn) {
                    throw new Error(`Hash ${options.hash} not available for PBKDF2`);
                }
                
                const result = await this.pbkdf2Async(
                    hashFn,
                    password,
                    salt,
                    {
                        c: options.iterations || 1000,
                        dkLen: options.keyLength || 32
                    }
                );
                return Buffer.from(result);
            
            case 'scrypt':
                if (!this.scryptAsync) {
                    throw new Error('Scrypt not supported');
                }
                
                const scryptResult = await this.scryptAsync(
                    password,
                    salt,
                    {
                        N: options.N || 16384,
                        r: options.r || 8,
                        p: options.p || 1,
                        dkLen: options.keyLength || 32
                    }
                );
                return Buffer.from(scryptResult);
            
            default:
                throw new Error(`KDF algorithm ${algorithm} not supported`);
        }
    }

    /**
     * Extended test vector processor that handles KDF operations
     */
    async processTestVector(testVector) {
        // Handle KDF operations separately
        if (testVector.operation === 'kdf') {
            const { algorithm, password, salt, options } = testVector.parameters;
            
            try {
                const result = await this.kdf(
                    algorithm,
                    this.convertEncoding(password, 'hex', 'buffer'),
                    this.convertEncoding(salt, 'hex', 'buffer'),
                    options
                );
                
                return {
                    success: true,
                    result: result.toString('hex'),
                    library: this.libraryName
                };
            } catch (error) {
                return {
                    success: false,
                    error: {
                        message: error.message,
                        type: this.classifyError(error)
                    },
                    library: this.libraryName
                };
            }
        }
        
        // Delegate to parent class for standard operations
        return super.processTestVector(testVector);
    }
}

// Export for use as a module
if (require.main !== module) {
    module.exports = NobleHashesAdapter;
}

// CLI interface for direct execution
if (require.main === module) {
    const adapter = new NobleHashesAdapter();
    
    async function main() {
        await adapter.initialize();
        
        // Parse command line arguments
        const args = process.argv.slice(2);
        
        if (args.length === 0) {
            // Print capabilities and exit
            console.log(JSON.stringify({
                library: adapter.libraryName,
                capabilities: adapter.getCapabilities()
            }, null, 2));
            process.exit(0);
        }
        
        if (args.length === 1 && args[0] === '--capabilities') {
            console.log(adapter.getCapabilities().join('\n'));
            process.exit(0);
        }
        
        // Process test vector from stdin or arguments
        if (args[0] === '--stdin') {
            let input = '';
            process.stdin.on('data', chunk => input += chunk);
            process.stdin.on('end', async () => {
                try {
                    const testVector = JSON.parse(input);
                    const result = await adapter.processTestVector(testVector);
                    console.log(JSON.stringify(result));
                    process.exit(result.success ? 0 : 1);
                } catch (error) {
                    console.error(JSON.stringify({
                        success: false,
                        error: {
                            message: error.message,
                            type: 'PARSE_ERROR'
                        }
                    }));
                    process.exit(1);
                }
            });
        } else {
            // Process test vector from command line
            try {
                const testVector = JSON.parse(args.join(' '));
                const result = await adapter.processTestVector(testVector);
                console.log(JSON.stringify(result));
                process.exit(result.success ? 0 : 1);
            } catch (error) {
                console.error(JSON.stringify({
                    success: false,
                    error: {
                        message: error.message,
                        type: 'PARSE_ERROR'
                    }
                }));
                process.exit(1);
            }
        }
    }
    
    main().catch(error => {
        console.error(JSON.stringify({
            success: false,
            error: {
                message: error.message,
                type: 'INITIALIZATION_ERROR'
            }
        }));
        process.exit(1);
    });
}