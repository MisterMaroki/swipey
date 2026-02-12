#!/bin/bash
# Generate DMG background image using ImageMagick
# Run from the swipey project root

OUTPUT="dmg-background.png"
WIDTH=600
HEIGHT=400

# Colors (matching Swipey's brutalist minimal aesthetic)
BG="#fafafa"      # white
TEXT="#0a0a0a"    # black
ACCENT="#737373"  # gray-500
BORDER="#e5e5e5"  # gray-200

# Check if ImageMagick is installed
if ! command -v convert &> /dev/null; then
    echo "❌ ImageMagick not found. Install with: brew install imagemagick"
    exit 1
fi

# Create the background image
convert \
    -size ${WIDTH}x${HEIGHT} \
    "xc:${BG}" \
    -fill "${TEXT}" \
    -font "/System/Library/Fonts/Helvetica.ttc" \
    -pointsize 36 \
    -gravity North \
    -annotate +0+40 "Swipey" \
    -pointsize 16 \
    -gravity Center \
    -annotate +0-80 "Drag Swipey to Applications" \
    -pointsize 56 \
    -fill "${ACCENT}" \
    -gravity Center \
    -annotate +0-20 "↓" \
    -pointsize 13 \
    -gravity Center \
    -annotate +0+50 "Drop here to install" \
    -stroke "${BORDER}" \
    -strokewidth 2 \
    -fill none \
    -draw "rectangle 80,320 520,360" \
    "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "✓ DMG background created: $OUTPUT"
else
    echo "❌ Failed to create background image"
    exit 1
fi
