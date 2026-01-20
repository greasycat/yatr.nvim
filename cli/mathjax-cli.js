#!/usr/bin/env node

const MathJax = require('mathjax');

// Parse command line arguments
const args = process.argv.slice(2);
let texString = '';
let displayMode = false;

// Simple argument parser
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--tex' && i + 1 < args.length) {
    texString = args[i + 1];
    i++;
  } else if (args[i] === '--display') {
    displayMode = true;
  } else if (args[i] === '--no-display') {
    displayMode = false;
  }
}

// If --tex not provided, exit with error
if (!texString) {
  console.error('Error: texString must be provided via --tex argument');
  process.exit(1);
  return;
} else {
  runConversion();
}


async function runConversion() {
  if (!texString) {
    console.error('Error: texString must be provided via --tex argument or stdin');
    process.exit(1);
    return;
  }

  try {
    // Initialize MathJax with TeX input and SVG output
    let mj = await MathJax.init({
      loader: { load: ['input/tex', 'output/svg', 'adaptors/liteDOM'],
       }
    });

    const adaptor = mj.startup.adaptor;

    const dom = await MathJax.tex2svgPromise(texString, { display: displayMode });
    const svg = adaptor.firstChild(dom);

    const findError = (node) => {
      if (!node) return null;
      
      if (adaptor.hasAttribute(node, 'data-mjx-error')) {
        return adaptor.getAttribute(node, 'data-mjx-error');
      }
      
      if (node.children) {
        for (const child of node.children) {
          const errorMessage = findError(child);
          if (errorMessage) {
            return errorMessage;
          }
        }
      }
      
      return null;
    };

    const errorMessage = findError(svg);
    if (errorMessage) {
      console.error('Error: ' + errorMessage);
      process.exit(1);
      return;
    }


    let svgString = adaptor.serializeXML(svg);

    console.log(svgString);
    process.exit(0);
  } catch (error) {
    console.error('Error: ' + (error.message || String(error)));
    process.exit(1);
  }
}
