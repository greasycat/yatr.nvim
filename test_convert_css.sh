#!/bin/bash

# Script to convert SVG files using rsvg-convert with CSS to make all text white
# Usage: ./test_convert_css.sh input.svg [output.png]

if [ $# -lt 1 ]; then
    echo "Usage: $0 <input.svg> [output.png]"
    exit 1
fi

INPUT_SVG="$1"
OUTPUT="${2:-output.png}"

# Check if input file exists
if [ ! -f "$INPUT_SVG" ]; then
    echo "Error: Input file '$INPUT_SVG' not found"
    exit 1
fi

# Check if rsvg-convert is available
if ! command -v rsvg-convert &> /dev/null; then
    echo "Error: rsvg-convert not found. Please install librsvg."
    exit 1
fi

# Create temporary CSS file that makes all text white
TEMP_CSS=$(mktemp)
cat > "$TEMP_CSS" << 'EOF'
text, tspan, textPath {
    fill: white !important;
    stroke: white !important;
}
EOF

# Convert SVG using rsvg-convert with the CSS stylesheet
rsvg-convert -s "$TEMP_CSS" "$INPUT_SVG" -o "$OUTPUT"

# Check if conversion was successful
if [ $? -eq 0 ]; then
    echo "Successfully converted '$INPUT_SVG' to '$OUTPUT' with white text"
else
    echo "Error: Conversion failed"
    rm -f "$TEMP_CSS"
    exit 1
fi

# Clean up temporary CSS file
rm -f "$TEMP_CSS"
