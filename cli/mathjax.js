const MathJax = require('mathjax');

// MathJax module for converting TeX to SVG
class MathJaxConverter {
  constructor() {
    this.initialized = false;
  }

  async init() {
    if (this.initialized) {
      return;
    }

    try {
      // Initialize MathJax with TeX input and SVG output
      await MathJax.init({
        loader: { load: ['input/tex', 'output/svg'] }
      });

      this.initialized = true;
    } catch (error) {
      throw new Error(`Failed to initialize MathJax: ${error.message}`);
    }
  }

  async convertTexToSvg(texString, displayMode = false) {
    try {
      // Ensure MathJax is initialized
      if (!this.initialized) {
        await this.init();
      }

      if (!texString || typeof texString !== 'string') {
        return {
          status: 'err',
          error: 'texString must be a non-empty string'
        };
      }

      // Convert TeX to SVG using the promise-based API
      const svg = await MathJax.tex2svgPromise(texString, { display: displayMode });

      // Serialize the SVG to a string
      let svgString = MathJax.startup.adaptor.serializeXML(svg);

      // Extract only the <svg> element, removing any outer container
      // MathJax may wrap the SVG in a container like <mjx-container>
      const svgMatch = svgString.match(/<svg[\s\S]*<\/svg>/i);
      if (svgMatch) {
        svgString = svgMatch[0];
      }

      return {
        status: 'ok',
        svg: svgString,
        display: displayMode
      };
    } catch (error) {
      return {
        status: 'err',
        error: error.message || String(error)
      };
    }
  }
}

// Export singleton instance
const converter = new MathJaxConverter();

module.exports = {
  convertTexToSvg: async (texString, displayMode) => {
    return await converter.convertTexToSvg(texString, displayMode);
  }
};
