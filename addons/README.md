# Required Addons

## Godot OpenXR Vendors Plugin (REQUIRED)

This plugin provides Meta Quest-specific features including passthrough activation,
hand tracking quality improvements, and Quest-specific extensions.

### Install Instructions

1. Open the Godot editor with this project loaded.
2. Go to **AssetLib** tab (top center of the editor).
3. Search for **"Godot OpenXR Vendors"**.
4. Download and install the plugin.
5. Go to **Project > Project Settings > Plugins** and enable it.

Alternatively, grab it from GitHub:
https://github.com/GodotVR/godot_openxr_vendors

### What it provides

- `OpenXRFbPassthroughExtensionWrapper` — Meta passthrough activation API
- `OpenXRHandTrackingExtensionWrapper` — Enhanced hand tracking
- Proper Quest touch controller action bindings
- Quest-specific manifest entries for the Android export

### After Installing

Re-export the Android build. The plugin adds required `<uses-feature>` entries
to the AndroidManifest for the Quest store and sideloading.
