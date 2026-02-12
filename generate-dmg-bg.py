#!/bin/bash
# Generate DMG background from SVG
# Output must be exactly 540x380 pixels (1x, not retina)

cd "$(dirname "$0")"

SVG_FILE="dmg-background.svg"
PNG_FILE="dmg-background.png"

WIDTH=540
HEIGHT=380

# Create SVG
cat > "$SVG_FILE" << EOF
<svg xmlns="http://www.w3.org/2000/svg" width="${WIDTH}" height="${HEIGHT}" viewBox="0 0 ${WIDTH} ${HEIGHT}">
  <rect width="${WIDTH}" height="${HEIGHT}" fill="#fafafa"/>
  <text x="270" y="40" text-anchor="middle" font-family="SF Mono, SFMono-Regular, Menlo, monospace" font-size="22" font-weight="600" fill="#0a0a0a">Swipey</text>
  <text x="270" y="60" text-anchor="middle" font-family="SF Mono, SFMono-Regular, Menlo, monospace" font-size="10" fill="#a3a3a3">a 1273 project</text>
  <text x="270" y="195" text-anchor="middle" font-family="SF Mono, SFMono-Regular, Menlo, monospace" font-size="28" fill="#d4d4d4">→</text>
  <text x="270" y="340" text-anchor="middle" font-family="SF Mono, SFMono-Regular, Menlo, monospace" font-size="12" fill="#a3a3a3">Drag to Applications</text>
</svg>
EOF

# Convert SVG to PNG (1x - DMG backgrounds don't auto-scale @2x)
if command -v rsvg-convert &> /dev/null; then
    rsvg-convert -w $WIDTH -h $HEIGHT "$SVG_FILE" -o "$PNG_FILE"
elif command -v /Applications/Inkscape.app/Contents/MacOS/inkscape &> /dev/null; then
    /Applications/Inkscape.app/Contents/MacOS/inkscape "$SVG_FILE" --export-filename="$PNG_FILE" -w $WIDTH -h $HEIGHT
else
    # Use qlmanage but with careful sizing
    # qlmanage -t -s SIZE creates thumbnail fitting in SIZExSIZE square
    # For 540x380, use -s 540 which will give us 540x380 (since width is larger)
    qlmanage -t -s $WIDTH -o . "$SVG_FILE" 2>/dev/null
    
    if [ -f "${SVG_FILE}.png" ]; then
        mv "${SVG_FILE}.png" "$PNG_FILE"
        # Crop to exact dimensions from top-left (keeps header, cuts bottom padding)
        sips --cropToHeightWidth $HEIGHT $WIDTH --cropOffset 0 0 "$PNG_FILE" >/dev/null 2>&1
    fi
fi

if [ -f "$PNG_FILE" ]; then
    # Verify dimensions
    ACTUAL=$(sips -g pixelWidth -g pixelHeight "$PNG_FILE" 2>/dev/null | grep pixel | awk '{print $2}' | tr '\n' 'x' | sed 's/x$//')
    echo "✓ DMG background created: $PNG_FILE (${ACTUAL})"
else
    echo "❌ Failed to create background"
    exit 1
fi
