# MathJax Module Tests

This directory contains tests for the MathJax module.

## Running Tests

To run the tests, use one of the following methods:

### Using npm/yarn script:
```bash
npm test
# or
yarn test
```

### Direct execution:
```bash
node tests/mathjax.test.js
```

## Test Coverage

The test suite covers:

1. **Basic inline math conversion** - Tests simple formulas in inline mode
2. **Display mode conversion** - Tests formulas in display mode
3. **Complex fraction** - Tests complex mathematical expressions
4. **Error handling** - Tests invalid inputs (empty string, null)
5. **Multiple consecutive conversions** - Tests the singleton pattern
6. **Inline vs display mode** - Verifies different output for same formula
7. **SVG file output** - Saves an SVG to file for visual inspection

## Test Output

Test results are printed to the console. When tests pass, you'll see:
```
=== Test Results ===
✓ Passed: 8
✗ Failed: 0
Total: 8

All tests passed! 🎉
```

Generated SVG files (for visual inspection) are saved to `tests/output/` directory.
