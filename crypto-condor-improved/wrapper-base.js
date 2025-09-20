#!/usr/bin/env node

/**
 * Generic Cryptographic Operation Wrapper
 * 
 * This provides a uniform interface for all crypto libraries,
 * abstracting away implementation details and ensuring general testing.
 */

class CryptoWrapper {
    constructor(libraryName) {
        this.libraryName = libraryName;
        this.library = null;
        this.capabilities = new Set();
        this.encodings = ['hex', 'base64', 'utf8', 'binary'];
    }

    /**
     * Initialize the library and detect capabilities
     * Each library adapter must implement this
     */
    async initialize() {
        throw new Error('initialize() must be implemented by subclass');
    }

    /**
     * Generic hash operation
     * @param {string} algorithm - Hash algorithm (sha256, sha512, etc.)
     * @param {Buffer} data - Input data as buffer
     * @returns {Buffer} Hash output as buffer
     */
    async hash(algorithm, data) {
        if (!this.capabilities.has(`hash.${algorithm}`)) {
            throw new Error(`${this.libraryName} does not support ${algorithm}`);
        }
        throw new Error('hash() must be implemented by subclass');
    }

    /**
     * Generic HMAC operation
     * @param {string} algorithm - Hash algorithm for HMAC
     * @param {Buffer} key - Key as buffer
     * @param {Buffer} data - Input data as buffer
     * @returns {Buffer} HMAC output as buffer
     */
    async hmac(algorithm, key, data) {
        if (!this.capabilities.has(`hmac.${algorithm}`)) {
            throw new Error(`${this.libraryName} does not support HMAC-${algorithm}`);
        }
        throw new Error('hmac() must be implemented by subclass');
    }

    /**
     * Generic signature operation
     * @param {string} algorithm - Signature algorithm (ecdsa, eddsa, etc.)
     * @param {string} curve - Curve name (secp256k1, ed25519, etc.)
     * @param {Buffer} privateKey - Private key as buffer
     * @param {Buffer} message - Message to sign as buffer
     * @returns {Buffer} Signature as buffer
     */
    async sign(algorithm, curve, privateKey, message) {
        if (!this.capabilities.has(`sign.${algorithm}.${curve}`)) {
            throw new Error(`${this.libraryName} does not support ${algorithm} with ${curve}`);
        }
        throw new Error('sign() must be implemented by subclass');
    }

    /**
     * Generic verification operation
     * @param {string} algorithm - Signature algorithm
     * @param {string} curve - Curve name
     * @param {Buffer} publicKey - Public key as buffer
     * @param {Buffer} message - Message that was signed
     * @param {Buffer} signature - Signature to verify
     * @returns {boolean} Verification result
     */
    async verify(algorithm, curve, publicKey, message, signature) {
        if (!this.capabilities.has(`verify.${algorithm}.${curve}`)) {
            throw new Error(`${this.libraryName} does not support ${algorithm} verification with ${curve}`);
        }
        throw new Error('verify() must be implemented by subclass');
    }

    /**
     * Convert data between encodings
     * @param {*} data - Input data
     * @param {string} fromEncoding - Source encoding
     * @param {string} toEncoding - Target encoding
     * @returns {*} Converted data
     */
    convertEncoding(data, fromEncoding, toEncoding) {
        // Generic encoding conversion logic
        let buffer;
        
        // Convert to buffer first
        switch (fromEncoding) {
            case 'hex':
                buffer = Buffer.from(data, 'hex');
                break;
            case 'base64':
                buffer = Buffer.from(data, 'base64');
                break;
            case 'utf8':
                buffer = Buffer.from(data, 'utf8');
                break;
            case 'binary':
                buffer = Buffer.from(data);
                break;
            case 'buffer':
                buffer = data;
                break;
            default:
                throw new Error(`Unsupported source encoding: ${fromEncoding}`);
        }

        // Convert from buffer to target encoding
        switch (toEncoding) {
            case 'hex':
                return buffer.toString('hex');
            case 'base64':
                return buffer.toString('base64');
            case 'utf8':
                return buffer.toString('utf8');
            case 'binary':
                return buffer.toString('binary');
            case 'buffer':
                return buffer;
            default:
                throw new Error(`Unsupported target encoding: ${toEncoding}`);
        }
    }

    /**
     * Process a generic test vector
     * @param {Object} testVector - Test vector with operation and parameters
     * @returns {Object} Result with success flag and output/error
     */
    async processTestVector(testVector) {
        const startTime = process.hrtime.bigint();
        
        try {
            const { operation, parameters } = testVector;
            let result;

            // Validate operation is supported
            if (!this[operation]) {
                throw new Error(`Operation ${operation} not implemented`);
            }

            // Convert all inputs from hex to buffers (standard input format)
            const convertedParams = this.preprocessParameters(operation, parameters);

            // Execute the operation
            switch (operation) {
                case 'hash':
                    result = await this.hash(
                        convertedParams.algorithm,
                        convertedParams.data
                    );
                    break;
                
                case 'hmac':
                    result = await this.hmac(
                        convertedParams.algorithm,
                        convertedParams.key,
                        convertedParams.data
                    );
                    break;
                
                case 'sign':
                    result = await this.sign(
                        convertedParams.algorithm,
                        convertedParams.curve,
                        convertedParams.privateKey,
                        convertedParams.message
                    );
                    break;
                
                case 'verify':
                    result = await this.verify(
                        convertedParams.algorithm,
                        convertedParams.curve,
                        convertedParams.publicKey,
                        convertedParams.message,
                        convertedParams.signature
                    );
                    break;
                
                default:
                    throw new Error(`Unknown operation: ${operation}`);
            }

            const endTime = process.hrtime.bigint();
            const durationMs = Number(endTime - startTime) / 1000000;

            return {
                success: true,
                result: Buffer.isBuffer(result) ? result.toString('hex') : result,
                durationMs,
                library: this.libraryName
            };

        } catch (error) {
            const endTime = process.hrtime.bigint();
            const durationMs = Number(endTime - startTime) / 1000000;

            return {
                success: false,
                error: {
                    message: error.message,
                    type: this.classifyError(error),
                    stack: process.env.DEBUG ? error.stack : undefined
                },
                durationMs,
                library: this.libraryName
            };
        }
    }

    /**
     * Preprocess parameters for an operation
     * @param {string} operation - Operation name
     * @param {Object} parameters - Raw parameters
     * @returns {Object} Processed parameters with buffers
     */
    preprocessParameters(operation, parameters) {
        const processed = {};

        // Define which parameters should be converted to buffers
        const bufferParams = {
            hash: ['data'],
            hmac: ['key', 'data'],
            sign: ['privateKey', 'message'],
            verify: ['publicKey', 'message', 'signature']
        };

        const paramsToConvert = bufferParams[operation] || [];

        for (const [key, value] of Object.entries(parameters)) {
            if (paramsToConvert.includes(key)) {
                // Assume hex encoding by default, but check for encoding hints
                const encoding = parameters[`${key}Encoding`] || 'hex';
                processed[key] = this.convertEncoding(value, encoding, 'buffer');
            } else {
                processed[key] = value;
            }
        }

        return processed;
    }

    /**
     * Classify errors for better reporting
     * @param {Error} error - The error to classify
     * @returns {string} Error classification
     */
    classifyError(error) {
        const message = error.message.toLowerCase();
        
        if (message.includes('not supported') || message.includes('not implemented')) {
            return 'UNSUPPORTED_OPERATION';
        }
        if (message.includes('invalid') || message.includes('malformed')) {
            return 'INVALID_INPUT';
        }
        if (message.includes('key') && (message.includes('size') || message.includes('length'))) {
            return 'INVALID_KEY_SIZE';
        }
        if (message.includes('verify') || message.includes('verification')) {
            return 'VERIFICATION_FAILED';
        }
        if (message.includes('encode') || message.includes('decode')) {
            return 'ENCODING_ERROR';
        }
        
        return 'GENERAL_ERROR';
    }

    /**
     * Get library capabilities for reporting
     * @returns {Array} List of supported operations
     */
    getCapabilities() {
        return Array.from(this.capabilities);
    }
}

module.exports = CryptoWrapper;