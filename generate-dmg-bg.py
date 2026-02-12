#!/bin/bash
# Generate DMG background from SVG using macOS Quick Look
# Brutalist minimal style matching Swipey aesthetic

cd "$(dirname "$0")"

SVG_FILE="dmg-background.svg"
PNG_FILE="dmg-background.png"

# Create SVG with drag guidance text
cat > "$SVG_FILE" << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="600" height="400" viewBox="0 0 600 400">
  <rect width="600" height="400" fill="#fafafa"/>
  <text x="300" y="55" text-anchor="middle" font-family="Helvetica, Arial, sans-serif" font-size="28" font-weight="500" fill="#0a0a0a">Swipey</text>
  <text x="300" y="150" text-anchor="middle" font-family="Helvetica, Arial, sans-serif" font-size="14" fill="#0a0a0a">Drag to Applications</text>
  <text x="300" y="210" text-anchor="middle" font-family="Helvetica, Arial, sans-serif" font-size="44" fill="#a3a3a3">→</text>
</svg>
EOF

# Convert SVG to PNG using Quick Look
qlmanage -t -s 600 -o . "$SVG_FILE" 2>/dev/null

# Rename and resize output
if [ -f "${SVG_FILE}.png" ]; then
    mv "${SVG_FILE}.png" "$PNG_FILE"
    # Resize to exact dimensions (qlmanage makes square)
    sips -z 400 600 "$PNG_FILE" >/dev/null 2>&1
    echo "✓ DMG background created: $PNG_FILE"
else
    echo "❌ Failed to create background"
    exit 1
fi
