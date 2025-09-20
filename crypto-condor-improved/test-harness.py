#!/usr/bin/env python3

"""
Generic Test Harness for crypto-condor

This harness provides a general interface between crypto-condor test vectors
and JavaScript crypto library adapters. It doesn't contain any hard-coded
test values or library-specific logic.
"""

import json
import subprocess
import sys
import os
import logging
from pathlib import Path
from typing import Dict, Any, Optional, List, Callable
from dataclasses import dataclass
from enum import Enum

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class TestResult(Enum):
    """Test result classifications"""
    PASS = "pass"
    FAIL = "fail"
    SKIP = "skip"
    ERROR = "error"
    UNSUPPORTED = "unsupported"


@dataclass
class TestOutcome:
    """Structure for test outcomes"""
    result: TestResult
    operation: str
    algorithm: str
    library: str
    message: Optional[str] = None
    duration_ms: Optional[float] = None
    error_type: Optional[str] = None


class CryptoLibraryAdapter:
    """
    Generic adapter for JavaScript crypto libraries.
    Communicates with library-specific adapters via subprocess.
    """
    
    def __init__(self, library_name: str, adapter_path: str):
        self.library_name = library_name
        self.adapter_path = Path(adapter_path)
        self.capabilities = None
        self.process_timeout = 10  # seconds
        
        if not self.adapter_path.exists():
            raise FileNotFoundError(f"Adapter not found: {adapter_path}")
        
        # Initialize and get capabilities
        self._get_capabilities()
    
    def _get_capabilities(self):
        """Query the adapter for its capabilities"""
        try:
            result = subprocess.run(
                ['node', str(self.adapter_path), '--capabilities'],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            if result.returncode == 0:
                self.capabilities = set(result.stdout.strip().split('\n'))
                logger.info(f"{self.library_name} capabilities: {self.capabilities}")
            else:
                logger.warning(f"Failed to get capabilities for {self.library_name}")
                self.capabilities = set()
                
        except (subprocess.TimeoutExpired, FileNotFoundError) as e:
            logger.error(f"Error getting capabilities: {e}")
            self.capabilities = set()
    
    def supports_operation(self, operation: str, algorithm: str = None) -> bool:
        """Check if the adapter supports a specific operation"""
        if not self.capabilities:
            return False
        
        if algorithm:
            capability_string = f"{operation}.{algorithm}"
        else:
            capability_string = operation
        
        return capability_string in self.capabilities
    
    def execute_test_vector(self, test_vector: Dict[str, Any]) -> TestOutcome:
        """
        Execute a single test vector through the adapter
        
        Args:
            test_vector: Dictionary containing operation and parameters
        
        Returns:
            TestOutcome object with results
        """
        operation = test_vector.get('operation')
        parameters = test_vector.get('parameters', {})
        algorithm = parameters.get('algorithm', 'unknown')
        
        # Check if operation is supported
        if not self.supports_operation(operation, algorithm):
            return TestOutcome(
                result=TestResult.UNSUPPORTED,
                operation=operation,
                algorithm=algorithm,
                library=self.library_name,
                message=f"Operation {operation}.{algorithm} not supported"
            )
        
        try:
            # Execute the adapter with the test vector
            result = subprocess.run(
                ['node', str(self.adapter_path), '--stdin'],
                input=json.dumps(test_vector),
                capture_output=True,
                text=True,
                timeout=self.process_timeout
            )
            
            # Parse the result
            try:
                output = json.loads(result.stdout)
            except json.JSONDecodeError:
                logger.error(f"Invalid JSON from adapter: {result.stdout}")
                return TestOutcome(
                    result=TestResult.ERROR,
                    operation=operation,
                    algorithm=algorithm,
                    library=self.library_name,
                    message="Adapter returned invalid JSON",
                    error_type="ADAPTER_ERROR"
                )
            
            if output.get('success'):
                return TestOutcome(
                    result=TestResult.PASS,
                    operation=operation,
                    algorithm=algorithm,
                    library=self.library_name,
                    duration_ms=output.get('durationMs')
                )
            else:
                error = output.get('error', {})
                return TestOutcome(
                    result=TestResult.FAIL,
                    operation=operation,
                    algorithm=algorithm,
                    library=self.library_name,
                    message=error.get('message', 'Unknown error'),
                    error_type=error.get('type', 'GENERAL_ERROR')
                )
                
        except subprocess.TimeoutExpired:
            return TestOutcome(
                result=TestResult.ERROR,
                operation=operation,
                algorithm=algorithm,
                library=self.library_name,
                message=f"Test timed out after {self.process_timeout}s",
                error_type="TIMEOUT"
            )
        except Exception as e:
            return TestOutcome(
                result=TestResult.ERROR,
                operation=operation,
                algorithm=algorithm,
                library=self.library_name,
                message=str(e),
                error_type="EXECUTION_ERROR"
            )


class CryptoCondorTestRunner:
    """
    Main test runner that integrates with crypto-condor
    """
    
    def __init__(self, library_adapters: Dict[str, CryptoLibraryAdapter]):
        self.adapters = library_adapters
        self.test_results = []
        
    def create_wrapper_function(self, adapter: CryptoLibraryAdapter, 
                                operation: str, algorithm: str) -> Callable:
        """
        Create a wrapper function for crypto-condor to call
        
        This function signature must match what crypto-condor expects
        for the specific primitive being tested.
        """
        
        def wrapper(*args, **kwargs):
            # Build test vector from crypto-condor inputs
            test_vector = self._build_test_vector(operation, algorithm, args, kwargs)
            
            # Execute through adapter
            outcome = adapter.execute_test_vector(test_vector)
            
            # Store result for reporting
            self.test_results.append(outcome)
            
            # Return value in format expected by crypto-condor
            if outcome.result == TestResult.PASS:
                # Extract the actual result from the test vector response
                result = subprocess.run(
                    ['node', str(adapter.adapter_path), '--stdin'],
                    input=json.dumps(test_vector),
                    capture_output=True,
                    text=True,
                    timeout=adapter.process_timeout
                )
                output = json.loads(result.stdout)
                if output.get('success') and 'result' in output:
                    # Convert hex string back to bytes for crypto-condor
                    return bytes.fromhex(output['result'])
            
            # Raise exception for failures (crypto-condor expects this)
            raise Exception(outcome.message or "Test failed")
        
        return wrapper
    
    def _build_test_vector(self, operation: str, algorithm: str, 
                           args: tuple, kwargs: dict) -> Dict[str, Any]:
        """
        Build a test vector from crypto-condor inputs
        
        This maps crypto-condor's calling convention to our generic format
        """
        test_vector = {
            'operation': operation,
            'parameters': {
                'algorithm': algorithm
            }
        }
        
        # Map arguments based on operation type
        if operation == 'hash':
            # crypto-condor passes: hash_function(data: bytes) -> bytes
            test_vector['parameters']['data'] = args[0].hex()
            
        elif operation == 'hmac':
            # crypto-condor passes: hmac_function(key: bytes, data: bytes) -> bytes
            test_vector['parameters']['key'] = args[0].hex()
            test_vector['parameters']['data'] = args[1].hex()
            
        elif operation == 'sign':
            # crypto-condor passes: sign_function(private_key: bytes, message: bytes) -> bytes
            test_vector['parameters']['privateKey'] = args[0].hex()
            test_vector['parameters']['message'] = args[1].hex()
            if 'curve' in kwargs:
                test_vector['parameters']['curve'] = kwargs['curve']
                
        elif operation == 'verify':
            # crypto-condor passes: verify_function(public_key: bytes, message: bytes, signature: bytes) -> bool
            test_vector['parameters']['publicKey'] = args[0].hex()
            test_vector['parameters']['message'] = args[1].hex()
            test_vector['parameters']['signature'] = args[2].hex()
            if 'curve' in kwargs:
                test_vector['parameters']['curve'] = kwargs['curve']
        
        return test_vector
    
    def run_crypto_condor_tests(self, library_name: str, test_suite: str):
        """
        Run crypto-condor test suite for a specific library
        
        Args:
            library_name: Name of the library to test
            test_suite: Test suite to run (e.g., 'SHA', 'HMAC', 'ECDSA')
        """
        if library_name not in self.adapters:
            logger.error(f"No adapter found for {library_name}")
            return None
        
        adapter = self.adapters[library_name]
        
        # Import the appropriate crypto-condor module
        if test_suite == 'SHA':
            from crypto_condor.primitives import SHA
            
            # Test each supported algorithm
            for algorithm in ['SHA_256', 'SHA_512', 'SHA3_256', 'SHA3_512']:
                algo_str = algorithm.lower().replace('_', '-')
                if adapter.supports_operation('hash', algo_str):
                    wrapper = self.create_wrapper_function(adapter, 'hash', algo_str)
                    try:
                        results = SHA.test(wrapper, getattr(SHA.Algorithm, algorithm))
                        logger.info(f"{library_name} {algorithm}: {results}")
                    except Exception as e:
                        logger.error(f"Error testing {library_name} {algorithm}: {e}")
        
        elif test_suite == 'HMAC':
            from crypto_condor.primitives import HMAC
            
            # Test HMAC with different hash algorithms
            for algorithm in ['SHA_256', 'SHA_512']:
                algo_str = algorithm.lower().replace('_', '-')
                if adapter.supports_operation('hmac', algo_str):
                    wrapper = self.create_wrapper_function(adapter, 'hmac', algo_str)
                    try:
                        results = HMAC.test(wrapper, getattr(HMAC.Algorithm, algorithm))
                        logger.info(f"{library_name} HMAC-{algorithm}: {results}")
                    except Exception as e:
                        logger.error(f"Error testing {library_name} HMAC-{algorithm}: {e}")
    
    def generate_report(self) -> Dict[str, Any]:
        """Generate a summary report of all test results"""
        report = {
            'total_tests': len(self.test_results),
            'by_result': {},
            'by_library': {},
            'by_operation': {},
            'failures': []
        }
        
        # Count by result type
        for result_type in TestResult:
            count = sum(1 for r in self.test_results if r.result == result_type)
            report['by_result'][result_type.value] = count
        
        # Group by library
        for adapter_name in self.adapters:
            library_results = [r for r in self.test_results if r.library == adapter_name]
            report['by_library'][adapter_name] = {
                'total': len(library_results),
                'passed': sum(1 for r in library_results if r.result == TestResult.PASS),
                'failed': sum(1 for r in library_results if r.result == TestResult.FAIL),
                'errors': sum(1 for r in library_results if r.result == TestResult.ERROR),
                'unsupported': sum(1 for r in library_results if r.result == TestResult.UNSUPPORTED)
            }
        
        # Collect failures for investigation
        for result in self.test_results:
            if result.result in [TestResult.FAIL, TestResult.ERROR]:
                report['failures'].append({
                    'library': result.library,
                    'operation': result.operation,
                    'algorithm': result.algorithm,
                    'message': result.message,
                    'error_type': result.error_type
                })
        
        return report


def main():
    """Main entry point for the test harness"""
    
    # Parse command line arguments
    if len(sys.argv) < 2:
        print("Usage: test-harness.py <library_name> [test_suite]")
        sys.exit(1)
    
    library_name = sys.argv[1]
    test_suite = sys.argv[2] if len(sys.argv) > 2 else 'SHA'
    
    # Locate adapter
    adapter_path = Path(__file__).parent / 'adapters' / f'{library_name}-adapter.js'
    
    if not adapter_path.exists():
        logger.error(f"Adapter not found: {adapter_path}")
        sys.exit(1)
    
    # Initialize adapter
    try:
        adapter = CryptoLibraryAdapter(library_name, adapter_path)
    except Exception as e:
        logger.error(f"Failed to initialize adapter: {e}")
        sys.exit(1)
    
    # Create test runner
    runner = CryptoCondorTestRunner({library_name: adapter})
    
    # Run tests
    runner.run_crypto_condor_tests(library_name, test_suite)
    
    # Generate and save report
    report = runner.generate_report()
    
    report_path = Path(f'reports/{library_name}_{test_suite.lower()}_results.json')
    report_path.parent.mkdir(exist_ok=True)
    
    with open(report_path, 'w') as f:
        json.dump(report, f, indent=2)
    
    # Print summary
    print(f"\nTest Results for {library_name} - {test_suite}")
    print("=" * 50)
    print(f"Total tests: {report['total_tests']}")
    print(f"Passed: {report['by_result'].get('pass', 0)}")
    print(f"Failed: {report['by_result'].get('fail', 0)}")
    print(f"Errors: {report['by_result'].get('error', 0)}")
    print(f"Unsupported: {report['by_result'].get('unsupported', 0)}")
    
    # Exit with appropriate code
    if report['by_result'].get('fail', 0) > 0 or report['by_result'].get('error', 0) > 0:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == '__main__':
    main()