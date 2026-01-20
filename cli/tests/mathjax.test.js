const { convertTexToSvg } = require('../mathjax.js');
const fs = require('fs');
const path = require('path');

// Test helper functions
function assert(condition, message) {
  if (!condition) {
    throw new Error(`Assertion failed: ${message}`);
  }
}

function assertEqual(actual, expected, message) {
  if (actual !== expected) {
    throw new Error(`Assertion failed: ${message || ''}\n  Expected: ${expected}\n  Actual: ${actual}`);
  }
}

async function runTest(testName, testFn) {
  try {
    console.log(`Running test: ${testName}`);
    await testFn();
    console.log(`✓ ${testName} passed\n`);
  } catch (error) {
    console.error(`✗ ${testName} failed: ${error.message}\n`);
    throw error;
  }
}

// Test suite
async function runTests() {
  console.log('=== MathJax Module Tests ===\n');

  let passed = 0;
  let failed = 0;

  // Test 1: Basic inline math conversion
  await runTest('Basic inline math conversion', async () => {
    const result = await convertTexToSvg('E = mc^2', false);
    assert(result.status === 'ok', 'Status should be ok');
    assert(result.svg, 'SVG should be returned');
    assert(result.svg.includes('<svg'), 'SVG should contain <svg> tag');
    assert(result.display === false, 'Display mode should be false');
    assert(result.svg.includes('E'), 'SVG should contain the formula');
  });
  passed++;

  // Test 2: Display mode conversion
  await runTest('Display mode conversion', async () => {
    const result = await convertTexToSvg('\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}', true);
    assert(result.status === 'ok', 'Status should be ok');
    assert(result.svg, 'SVG should be returned');
    assert(result.display === true, 'Display mode should be true');
    assert(result.svg.includes('<svg'), 'SVG should contain <svg> tag');
  });
  passed++;

  // Test 3: Complex fraction
  await runTest('Complex fraction conversion', async () => {
    const result = await convertTexToSvg('\\frac{1}{x^2-1}', true);
    assert(result.status === 'ok', 'Status should be ok');
    assert(result.svg, 'SVG should be returned');
    assert(result.svg.includes('<svg'), 'SVG should contain <svg> tag');
  });
  passed++;

  // Test 4: Error handling - empty string
  await runTest('Error handling - empty string', async () => {
    const result = await convertTexToSvg('', false);
    assert(result.status === 'err', 'Status should be err');
    assert(result.error, 'Error message should be present');
  });
  passed++;

  // Test 5: Error handling - null input
  await runTest('Error handling - null input', async () => {
    const result = await convertTexToSvg(null, false);
    assert(result.status === 'err', 'Status should be err');
    assert(result.error, 'Error message should be present');
  });
  passed++;

  // Test 6: Multiple consecutive conversions (test singleton)
  await runTest('Multiple consecutive conversions', async () => {
    const result1 = await convertTexToSvg('x^2 + y^2 = r^2', false);
    const result2 = await convertTexToSvg('a^2 + b^2 = c^2', false);
    assert(result1.status === 'ok', 'First conversion should succeed');
    assert(result2.status === 'ok', 'Second conversion should succeed');
    assert(result1.svg !== result2.svg, 'Different formulas should produce different SVGs');
  });
  passed++;

  // Test 7: Inline vs display mode difference
  await runTest('Inline vs display mode difference', async () => {
    const tex = '\\sum_{i=1}^n i';
    const inline = await convertTexToSvg(tex, false);
    const display = await convertTexToSvg(tex, true);
    assert(inline.status === 'ok', 'Inline should succeed');
    assert(display.status === 'ok', 'Display should succeed');
    // Display mode might produce different SVG structure
    assert(inline.svg !== display.svg, 'Inline and display modes should produce different SVGs');
  });
  passed++;

  // Test 8: Save SVG to file (optional visual inspection)
  await runTest('Save SVG to file', async () => {
    const result = await convertTexToSvg('\\color{white} \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}', false);
    assert(result.status === 'ok', 'Conversion should succeed');
    
    const testDir = path.join(__dirname, 'output');
    if (!fs.existsSync(testDir)) {
      fs.mkdirSync(testDir, { recursive: true });
    }
    
    const outputPath = path.join(testDir, 'quadratic-formula.svg');
    fs.writeFileSync(outputPath, result.svg);
    assert(fs.existsSync(outputPath), 'SVG file should be created');
    console.log(`  SVG saved to: ${outputPath}`);
  });
  passed++;

  console.log('=== Test Results ===');
  console.log(`✓ Passed: ${passed}`);
  console.log(`✗ Failed: ${failed}`);
  console.log(`Total: ${passed + failed}\n`);

  if (failed === 0) {
    console.log('All tests passed! 🎉');
    process.exit(0);
  } else {
    console.log('Some tests failed. ❌');
    process.exit(1);
  }
}

// Run tests
runTests().catch((error) => {
  console.error('Fatal error running tests:', error);
  process.exit(1);
});
