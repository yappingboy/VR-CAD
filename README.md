# VR-CAD

A VR CAD tool for the **Meta Quest** (Quest 2, 3, Pro) built in **Godot 4**.
Design objects in mixed reality — at real-world scale — and export directly to
STL (3D printing) or prepare geometry for CNC.

---

## Features

| Phase | Feature | Status |
|-------|---------|--------|
| 1 | Passthrough (mixed reality) mode | ✅ |
| 1 | OpenXR initialization & session management | ✅ |
| 2 | Controller ray interaction (hover, select, grab) | ✅ |
| 2 | Haptic feedback | ✅ |
| 3 | Arbitrary work planes (surface-aligned or free-floating) | ✅ |
| 3 | Grid overlay with snap-to-grid | ✅ |
| 4 | Box / Cylinder / Sphere primitives | ✅ |
| 4 | Undo / Redo (command pattern, 64 steps) | ✅ |
| 5 | Wrist-mounted tool palette | ✅ |
| 5 | Thumbstick radial context menu | ✅ |
| 5 | Floating property panel (dimensions, volume) | ✅ |
| 6 | Scale reference ghosts (human, ruler, cards…) | ✅ |
| 6 | Binary STL export | ✅ |

---

## Requirements

### Software
- **Godot 4.3+** — [godotengine.org](https://godotengine.org)
- **Android SDK** (API 29+) — Android Studio or command-line tools
- **Godot OpenXR Vendors plugin** — see `addons/README.md`

### Hardware
- Meta Quest 2, 3, or Pro
- USB-C cable (or wireless ADB) for sideloading

---

## Setup (step-by-step for beginners)

### 1 — Install Godot 4.3+
Download from [godotengine.org](https://godotengine.org/download).
Choose the **standard** build (not .NET / C#).

### 2 — Install Android SDK
Open Godot → **Editor → Editor Settings → Export → Android** and point it
at your Android SDK path. If you don't have the SDK:
1. Download [Android Studio](https://developer.android.com/studio).
2. In Android Studio → SDK Manager → install **SDK Platform 29 (Android 10)**.
3. Note the SDK path (usually `~/Android/Sdk` on Linux/Mac, `%APPDATA%\Android\Sdk` on Windows).

### 3 — Install the OpenXR Vendors plugin
Open this project in Godot, then:
1. Click **AssetLib** tab at the top of the editor.
2. Search **"Godot OpenXR Vendors"**.
3. Download and install.
4. **Project → Project Settings → Plugins** → enable the plugin.

### 4 — Enable developer mode on the Quest
1. Create a Meta developer account at [developer.oculus.com](https://developer.oculus.com).
2. In the Meta app on your phone → Menu → Devices → your headset → Developer Mode → ON.

### 5 — Export to the Quest
1. **Project → Export → Add… → Android**.
2. The `export_presets.cfg` in this repo has sensible defaults already.
3. Plug in your Quest via USB-C.
4. **Export Project** → choose `.apk` → click **Export**.
5. Put on the headset → **Apps → Unknown Sources → VR-CAD**.

---

## Controls

### Left controller
| Input | Action |
|-------|--------|
| Wrist palm-up | Show / hide tool palette |
| Trigger | Select / place object |
| Grip | Grab and move selected object |
| Thumbstick | Scroll / nudge |
| X button | Undo |
| Y button | Toggle work plane placement mode |

### Right controller
| Input | Action |
|-------|--------|
| Trigger | Confirm / place |
| Grip | Resize active handle |
| Thumbstick | (hold B) open radial context menu |
| A button | Redo |
| B button | Open radial menu |

---

## Project structure

```
VR-CAD/
├── scenes/
│   ├── main.tscn          ← Entry point
│   └── xr_rig.tscn        ← XR camera + both controllers
├── scripts/
│   ├── xr/
│   │   ├── xr_manager.gd       ← XR init + passthrough
│   │   ├── controller_input.gd ← Button/axis reading + haptics
│   │   └── interaction_ray.gd  ← Raycasting hover/select/grab
│   ├── cad/
│   │   ├── cad_object.gd           ← Base class for all geometry
│   │   ├── primitive_box.gd
│   │   ├── primitive_cylinder.gd
│   │   ├── primitive_sphere.gd
│   │   ├── work_plane.gd           ← Grid plane + snapping
│   │   ├── plane_manager.gd        ← Autoload singleton
│   │   └── undo_redo_manager.gd    ← Autoload singleton
│   ├── ui/
│   │   ├── wrist_menu.gd      ← Tool palette on left wrist
│   │   ├── radial_menu.gd     ← Thumbstick radial picker
│   │   └── property_panel.gd  ← Object dimensions panel
│   └── utils/
│       ├── scale_reference.gd ← Ghost overlays for real-world scale
│       └── stl_exporter.gd    ← Binary STL file writer
├── addons/
│   └── README.md    ← How to install the OpenXR Vendors plugin
├── export_presets.cfg
└── project.godot
```

---

## Fabrication workflow

### 3D printing
1. Build your model in VR.
2. Use **scale reference ghosts** to verify real-world size.
3. Open the wrist menu → **Export STL**.
4. Copy the `.stl` from `user://` (see below) to your slicer.

Finding the exported file:
```
# On the Quest headset (via ADB):
adb pull /sdcard/Android/data/com.vrcad.app/files/ ./exports/

# On desktop fallback (Linux/Mac):
~/.local/share/godot/app_userdata/VR-CAD/

# On desktop fallback (Windows):
%APPDATA%\Godot\app_userdata\VR-CAD\
```

### CNC / Woodworking
Export STL and import into your CAM software (Fusion 360, FreeCAD, Carbide Create).
The model is in metres; most CAM tools let you set import units.

---

## Development tips

- **Desktop testing**: Run the project on desktop — `xr_manager.gd` detects no
  headset and falls back to a basic 3D camera so you can iterate without
  putting on the Quest every time.
- **Godot Remote Debug**: With the Quest plugged in, **Debug → Deploy with Remote
  Debug** lets you see `print()` output in the Godot console while running on device.
- **Hot reload**: Use the Godot Remote deploy to push updates without fully
  reinstalling the APK each time.
