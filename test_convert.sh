#!/bin/bash

# Test script to convert equations, matrices, and cases to PNG files using mathjax-cli
# This script converts three different LaTeX expressions to PNG files in the current working directory

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MATHJAX_CLI="$SCRIPT_DIR/cli/mathjax-cli.js"

# Check if mathjax-cli.js exists
if [ ! -f "$MATHJAX_CLI" ]; then
    echo "Error: mathjax-cli.js not found at $MATHJAX_CLI" >&2
    exit 1
fi

# Check if node is available
if ! command -v node &> /dev/null; then
    echo "Error: node command not found" >&2
    exit 1
fi

# Find SVG to PNG converter (prefer rsvg-convert, fallback to convert/ImageMagick)
SVG_CONVERTER=""
if command -v rsvg-convert &> /dev/null; then
    SVG_CONVERTER="rsvg-convert"
elif command -v convert &> /dev/null; then
    SVG_CONVERTER="convert"
else
    echo "Error: No SVG converter found. Please install rsvg-convert (librsvg) or ImageMagick" >&2
    exit 1
fi

# Function to convert TeX to PNG
# Usage: convert_tex_to_png "latex_expression" "output_file.png" [--display]
convert_tex_to_png() {
    local tex_expr="$1"
    local output_file="$2"
    local display_mode="${3:-}"
    
    # Convert TeX to SVG using mathjax-cli
    local svg_content
    if [ "$display_mode" = "--display" ]; then
        svg_content=$(node "$MATHJAX_CLI" --tex "$tex_expr" --display 2>&1)
    else
        svg_content=$(node "$MATHJAX_CLI" --tex "$tex_expr" 2>&1)
    fi
    
    # Check if conversion was successful
    if [ $? -ne 0 ] || [ -z "$svg_content" ]; then
        echo "Error: Failed to convert TeX to SVG" >&2
        echo "$svg_content" >&2
        return 1
    fi
    
    # Write SVG to temporary file
    local temp_svg=$(mktemp --suffix=.svg)
    echo "$svg_content" > "$temp_svg"
    
    # Convert SVG to PNG
    if [ "$SVG_CONVERTER" = "rsvg-convert" ]; then
        rsvg-convert --stylesheet=cli/white.css --format=png -h 300 -a "$temp_svg" > "$output_file"
    elif [ "$SVG_CONVERTER" = "convert" ]; then
        convert "$temp_svg" "png:$output_file" 2>/dev/null
    fi
    
    # Check if PNG conversion was successful
    if [ $? -eq 0 ] && [ -f "$output_file" ]; then
        echo "Successfully converted to: $output_file"
        rm -f "$temp_svg"
        return 0
    else
        echo "Error: Failed to convert SVG to PNG" >&2
        rm -f "$temp_svg"
        return 1
    fi
}

# Get current working directory
CWD=$(pwd)

echo "Converting LaTeX expressions to PNG files in: $CWD"
echo "Using SVG converter: $SVG_CONVERTER"
echo ""

# 1. Convert an equation (quadratic formula)
echo "1. Converting equation..."
convert_tex_to_png "x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}" "$CWD/equation.png" --display

# 2. Convert a matrix
echo ""
echo "2. Converting matrix..."
convert_tex_to_png "\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}" "$CWD/matrix.png" --display

# 3. Convert cases (piecewise function)
echo ""
echo "3. Converting cases..."
convert_tex_to_png "f(x) = \\begin{cases} x^2 & \\text{if } x \\geq 0 \\\\ -x & \\text{if } x < 0 \\end{cases}" "$CWD/cases.png" --display

echo ""
echo "Conversion complete!"
