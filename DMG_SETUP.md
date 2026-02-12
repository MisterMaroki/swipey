# DMG Customization Guide

The Swipey installer now includes a custom DMG (Disk Image) with visual guidance for first-time users, helping them understand that they need to drag the app to the Applications folder.

## What's New

- **Custom background image** with brutalist minimal design (matches Swipey's aesthetic)
- **Visual drag-to-Applications guidance** with arrow and instructions
- **Icon positioning** (when using create-dmg) for optimal UX
- **Polished installation experience** for end users

## Installation Requirements

### Option 1: Basic (Recommended for quick builds)
No additional tools required. The build script will:
1. Generate a PNG background using ImageMagick
2. Create a standard DMG with the background

**Install ImageMagick:**
```bash
brew install imagemagick
```

### Option 2: Premium (Polished Windows)
For a fully customized DMG window with positioned icons and background:

**Install create-dmg:**
```bash
npm install -g create-dmg
```

This adds:
- Custom window size and position
- Icon positioning for app and Applications folder
- Better visual presentation

## Usage

### Building with `build-app.sh`

```bash
./build-app.sh
```

The script will:
1. Build the Swift app
2. Generate the DMG background image
3. Create the DMG with custom styling
4. Suggest optional tools if needed

### What the Background Looks Like

```
┌─────────────────────────────────┐
│                                 │
│           Swipey                │
│                                 │
│   Drag Swipey to Applications   │
│                                 │
│              ↓                  │
│                                 │
│      Drop here to install       │
│     ┌─────────────────────┐     │
│     │                     │     │
│     └─────────────────────┘     │
│                                 │
└─────────────────────────────────┘
```

Brutalist minimal aesthetic:
- Clean typography
- Muted colors (#fafafa white, #0a0a0a black)
- Simple geometric elements
- Clear visual hierarchy

## Files Changed

- **build-app.sh** - Updated DMG creation logic
- **generate-dmg-bg.py** - New script to generate background image using ImageMagick
- **dmg-background.png** - Generated at build time (not version controlled)

## Troubleshooting

### "ImageMagick not found"
The script will still create a standard DMG, but without the custom background.

```bash
brew install imagemagick
./build-app.sh  # Run again
```

### "create-dmg not found"
The DMG will be created but without window positioning. To enable:

```bash
npm install -g create-dmg
./build-app.sh  # Run again
```

### Background image not rendering
- Check that ImageMagick is installed: `convert --version`
- Verify system fonts: `ls /System/Library/Fonts/Helvetica.ttc`
- Try rebuilding: `rm dmg-background.png && ./build-app.sh`

## Design Tokens

The DMG background uses the same design system as the Swipey website:

```
Colors:
  - Background: #fafafa (white)
  - Text: #0a0a0a (black)
  - Accent: #737373 (gray-500)
  - Border: #e5e5e5 (gray-200)

Typography:
  - Title: 36pt Helvetica
  - Body: 16pt Helvetica
  - Small: 13pt Helvetica
```

These can be customized in `generate-dmg-bg.py`.

## Next Steps

After building, test the DMG:

```bash
# Mount the DMG
open site/Swipey-v*.dmg

# Verify:
# 1. Background image appears
# 2. App icon is visible
# 3. Applications folder is visible
# 4. Instructions are clear
```
