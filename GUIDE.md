# GIGIdesk Build Guide (Custom RustDesk Fork)

> **Last updated:** February 2026
> **Maintained by:** Softaims

GIGIdesk is a customized fork of [RustDesk](https://github.com/rustdesk/rustdesk) v1.4.5, rebranded and extended for the GIGI Connect elder-care remote desktop platform. This guide covers setting up the development environment, compiling native Rust binaries, and building the Flutter macOS UI for both **Intel (x86_64)** and **Apple Silicon (arm64)**.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Repository Setup](#repository-setup)
5. [vcpkg Setup (Native Dependencies)](#vcpkg-setup-native-dependencies)
6. [Rust Toolchain Setup](#rust-toolchain-setup)
7. [Flutter Setup](#flutter-setup)
8. [Building for macOS Intel (x86_64)](#building-for-macos-intel-x86_64)
9. [Building for macOS Apple Silicon (arm64)](#building-for-macos-apple-silicon-arm64)
10. [Building for Windows](#building-for-windows)
11. [Custom CLI Flags](#custom-cli-flags)
12. [Important Files & Configuration](#important-files--configuration)
13. [How the Architecture Switching Works](#how-the-architecture-switching-works)
14. [Icons & Branding](#icons--branding)
15. [Integrating with GIGI Connect Desktop](#integrating-with-gigi-connect-desktop)
16. [Troubleshooting](#troubleshooting)

---

## Project Overview

| Property | Value |
|---|---|
| **Cargo Package Name** | `gigidesk` |
| **Binary Name** | `gigidesk` (lowercase — this is what Cargo produces) |
| **Flutter App Name** | `GIGIdesk` (mixed case — PRODUCT_NAME in Xcode) |
| **Bundle Identifier** | `com.softaims.gigidesk` |
| **Version** | 1.4.5 |
| **Lib Crate** | `librustdesk` (unchanged from upstream for FFI compatibility) |
| **URL Scheme** | `gigidesk://` |
| **LSUIElement** | `1` (agent app — no Dock icon, tray only) |

### What's Customized

- **Branding**: All user-facing text changed from "RustDesk" → "GIGIdesk" (Rust lang strings, Flutter UI, About page)
- **CLI Flags**: `--password` works **without root/sudo** (direct config write fallback)
- **Headless Mode**: `--server` flag starts the connection server + system tray with **no main window**
- **Flutter UI**: Custom left/right panes with GIGIdesk branding, service toggle hidden (always-on for elder care)
- **Icons**: All icons replaced with GIGI Connect branding (icns, png, svg, ico)
- **Bundle ID & Signing**: `com.softaims.gigidesk`, ad-hoc signed

---

## Architecture

The build produces a macOS `.app` bundle with this structure:

```
GIGIdesk.app/
├── Contents/
│   ├── Info.plist
│   ├── MacOS/
│   │   ├── gigidesk          ← Main Rust binary (Flutter embedder + RustDesk core)
│   │   └── service           ← Background service binary (IPC, connection server)
│   ├── Resources/
│   │   ├── AppIcon.icns      ← App icon
│   │   └── ...               ← Flutter assets, frameworks
│   └── Frameworks/
│       ├── FlutterMacOS.framework
│       └── librustdesk.dylib ← Rust native library (FFI bridge to Flutter)
```

The build process has **two stages**:
1. **Rust Compilation** — Produces `librustdesk.dylib` (the FFI library) and `service` binary. **Both are architecture-specific compiled binaries** — the x86_64 dylib and the arm64 dylib are entirely different machine-code files even though they come from the same Rust source.
2. **Flutter Build** — Produces the `.app` bundle, embeds the dylib, compiles Dart → native code.

> **⚠️ Important**: Both Intel and ARM64 Flutter builds output to the **same path**: `flutter/build/macos/Build/Products/Release/GIGIdesk.app`. Flutter does not create separate folders per architecture. You must **copy the `.app` out to `desktop/assets/`** immediately after each build before building the other architecture, or it will be overwritten.

---

## Prerequisites

### Required Tools

| Tool | Tested Version | Install |
|---|---|---|
| **Rust** (stable) | 1.93.0 | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
| **Flutter** (stable) | 3.38.9 | [flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install) |
| **Xcode** | 16.x | Mac App Store |
| **Xcode Command Line Tools** | — | `xcode-select --install` |
| **CocoaPods** | 1.15+ | `sudo gem install cocoapods` |
| **Python 3** | 3.12+ | `brew install python3` |
| **vcpkg** | latest | See [vcpkg Setup](#vcpkg-setup-native-dependencies) |
| **Git** | — | Pre-installed on macOS |
| **cmake** | 3.25+ | `brew install cmake` |
| **nasm** | 2.15+ | `brew install nasm` |

### macOS-Specific

```bash
# Ensure Xcode license is accepted
sudo xcodebuild -license accept

# Verify Flutter sees macOS as a target
flutter doctor
```

---

## Repository Setup

```bash
# Clone the repo
git clone <your-repo-url> Customdesk
cd Customdesk

# Verify Cargo.toml
head -5 Cargo.toml
# Should show: name = "gigidesk", version = "1.4.5"
```

---

## vcpkg Setup (Native Dependencies)

GIGIdesk depends on native C/C++ libraries (aom, opus, libvpx, libyuv, libjpeg-turbo) managed via vcpkg. These must be compiled for **each target architecture**.

### Install vcpkg

```bash
cd ~
git clone https://github.com/microsoft/vcpkg
cd vcpkg
./bootstrap-vcpkg.sh

# Set the env var (add to ~/.zshrc for persistence)
export VCPKG_ROOT="$HOME/vcpkg"
```

### Install Dependencies for Intel (x64-osx)

```bash
cd /path/to/Customdesk
$VCPKG_ROOT/vcpkg install --x-install-root="$VCPKG_ROOT/installed" --triplet=x64-osx
```

### Install Dependencies for Apple Silicon (arm64-osx)

```bash
$VCPKG_ROOT/vcpkg install --x-install-root="$VCPKG_ROOT/installed" --triplet=arm64-osx
```

### Verify

```bash
ls $VCPKG_ROOT/installed/x64-osx/lib/
# Should show: libaom.a  libjpeg.a  libopus.a  libturbojpeg.a  libvpx.a  libyuv.a

ls $VCPKG_ROOT/installed/arm64-osx/lib/
# Same files for arm64
```

> **⚠️ Critical**: Both triplets must be installed before building. The Rust build system (`build.rs`) automatically selects the correct triplet based on the target architecture. If the triplet is missing, you'll get linker errors like `ld: library not found for -lopus`.

---

## Rust Toolchain Setup

### Install Both Targets

Even if you're on an Intel Mac, you can **cross-compile** for ARM64 (and vice versa):

```bash
# Add both macOS targets
rustup target add x86_64-apple-darwin
rustup target add aarch64-apple-darwin

# Verify
rustup target list --installed
# Should show both:
# aarch64-apple-darwin
# x86_64-apple-darwin
```

### Default Toolchain

The default toolchain should match your **host machine**:

```bash
rustup show active-toolchain
# Intel Mac:  stable-x86_64-apple-darwin (default)
# M-chip Mac: stable-aarch64-apple-darwin (default)
```

> **Key Insight**: When building for your **native** architecture, you use `cargo build --release` (no `--target`). When **cross-compiling**, you use `cargo build --release --target aarch64-apple-darwin` (or `x86_64-apple-darwin`). The output goes to different directories:
> - Native: `target/release/`
> - Cross: `target/aarch64-apple-darwin/release/`

---

## Flutter Setup

```bash
cd Customdesk/flutter

# Get dependencies
flutter pub get

# Verify macOS is available
flutter devices
# Should list "macOS (desktop)"
```

### CocoaPods

Flutter's macOS build uses CocoaPods for native plugin dependencies. The Podfile is at `flutter/macos/Podfile`.

```bash
cd flutter/macos
pod install
```

> **⚠️ Important**: Pods must be reinstalled when switching architectures. The Podfile's `post_install` hook reads the target arch from `CustomArch.xcconfig` and compiles pods accordingly. If you switch from x64 → arm64 without reinstalling pods, you'll get `Unable to find module dependency` errors.

---

## Building for macOS Intel (x86_64)

### Step 1: Set Architecture Config

```bash
cd Customdesk

# Write x86_64 config
cat > flutter/macos/Flutter/CustomArch.xcconfig << 'EOF'
// Force x86_64 architecture for Intel Macs
ARCHS = x86_64
ONLY_ACTIVE_ARCH = NO
EXCLUDED_ARCHS = arm64
EOF
```

### Step 2: Build Rust Library

```bash
# From the Customdesk root
MACOSX_DEPLOYMENT_TARGET=10.14 \
VCPKG_ROOT=$HOME/vcpkg \
cargo build --features flutter --release
```

This produces:
- `target/release/liblibrustdesk.dylib` — The Rust FFI library (x86_64). Flutter embeds this into the `.app` bundle.
- `target/release/service` — Background service binary (IPC server, connection handler)
- `target/release/gigidesk` — Standalone Rust binary (not embedded — Flutter builds its own runner binary that links to the dylib)

### Step 3: Copy the dylib

Flutter expects `librustdesk.dylib` (without the `lib` prefix duplication):

```bash
cp target/release/liblibrustdesk.dylib target/release/librustdesk.dylib
```

> **Why this copy?** Cargo produces `liblibrustdesk.dylib` (lib prefix + crate name `librustdesk`). Flutter's Xcode build phase expects to find `librustdesk.dylib` in `target/release/`. The copy creates the expected filename.
>
> **⚠️ Note**: When you later build for ARM64, this file will be overwritten with the arm64 dylib. Always complete one full arch build (cargo → dylib copy → Flutter → save .app) before starting the other.

### Step 4: Clean & Reinstall Pods

```bash
cd flutter/macos
rm -rf Pods Podfile.lock
pod install
cd ..
```

### Step 5: Build Flutter

```bash
# Clean Xcode caches to avoid architecture mismatches
rm -rf build/macos ~/Library/Developer/Xcode/DerivedData/Runner-*

flutter build macos --release
```

On success: `✓ Built build/macos/Build/Products/Release/GIGIdesk.app`

### Step 6: Copy Service Binary into .app

```bash
cp -rf ../target/release/service build/macos/Build/Products/Release/GIGIdesk.app/Contents/MacOS/
```

### Step 7: Verify

```bash
file build/macos/Build/Products/Release/GIGIdesk.app/Contents/MacOS/gigidesk
# Should say: Mach-O 64-bit executable x86_64

file build/macos/Build/Products/Release/GIGIdesk.app/Contents/MacOS/service
# Should say: Mach-O 64-bit executable x86_64
```

---

## Building for macOS Apple Silicon (arm64)

### Step 1: Set Architecture Config

```bash
cd Customdesk

cat > flutter/macos/Flutter/CustomArch.xcconfig << 'EOF'
// Force arm64 architecture for Apple Silicon cross-compile
ARCHS = arm64
ONLY_ACTIVE_ARCH = NO
EXCLUDED_ARCHS = x86_64
EOF
```

### Step 2: Build Rust Library

If building **on an Intel Mac** (cross-compiling):

```bash
MACOSX_DEPLOYMENT_TARGET=10.14 \
VCPKG_ROOT=$HOME/vcpkg \
cargo build --features flutter --release --target aarch64-apple-darwin
```

Output goes to `target/aarch64-apple-darwin/release/`.

If building **on an M-chip Mac** (native):

```bash
MACOSX_DEPLOYMENT_TARGET=10.14 \
VCPKG_ROOT=$HOME/vcpkg \
cargo build --features flutter --release
```

Output goes to `target/release/`.

### Step 3: Copy the dylib

The dylib must be placed in `target/release/` regardless of where Cargo put it, because Flutter always looks there:

```bash
# If cross-compiled from Intel:
cp target/aarch64-apple-darwin/release/liblibrustdesk.dylib target/release/librustdesk.dylib
cp target/aarch64-apple-darwin/release/liblibrustdesk.dylib target/release/liblibrustdesk.dylib

# If native on M-chip:
cp target/release/liblibrustdesk.dylib target/release/librustdesk.dylib
```

> **⚠️ Critical**: The x86_64 and arm64 dylibs are **completely different compiled binaries** — same Rust source, but compiled to different CPU instruction sets. You are overwriting `target/release/` with the arm64 binary so Flutter (which always reads from there) picks up the correct one. If you forget this step, you'll get a runtime crash: the app binary is arm64 but the dylib is x86_64 and cannot be loaded.

### Step 4: Clean & Reinstall Pods

```bash
cd flutter/macos
rm -rf Pods Podfile.lock
pod install
cd ..
```

### Step 5: Build Flutter

```bash
rm -rf build/macos ~/Library/Developer/Xcode/DerivedData/Runner-*
flutter build macos --release
```

### Step 6: Copy Service Binary

```bash
# If cross-compiled:
cp -rf ../target/aarch64-apple-darwin/release/service build/macos/Build/Products/Release/GIGIdesk.app/Contents/MacOS/

# If native:
cp -rf ../target/release/service build/macos/Build/Products/Release/GIGIdesk.app/Contents/MacOS/
```

### Step 7: Verify

```bash
file build/macos/Build/Products/Release/GIGIdesk.app/Contents/MacOS/gigidesk
# Should say: Mach-O 64-bit executable arm64

file build/macos/Build/Products/Release/GIGIdesk.app/Contents/MacOS/service
# Should say: Mach-O 64-bit executable arm64
```

---

## Building for Windows

> **TODO**: Document Windows build process (electron-builder flow, NSIS installer, etc.)

---

## Custom CLI Flags

GIGIdesk has custom CLI modifications in `src/core_main.rs`:

### `--password <password>` (Modified)

Sets the permanent password **without requiring root/sudo**. This is a key customization — upstream RustDesk requires admin privileges.

**How it works:**
1. Tries IPC (`ipc::set_permanent_password`) first (works if the service is running)
2. If IPC fails, falls back to writing directly via `Config::set_permanent_password()`
3. Also sets `verification-method` to `use-permanent-password` via `Config::set_option()`

```bash
./gigidesk --password MySecurePass123
# Output: Done!
```

> **⚠️ Note**: Uses `Config::set_option()` (not `Config2::set_option()`). Using `Config2` will cause a compile error — `Config2` doesn't have a `set_option` method.

### `--server` (Modified)

Starts GIGIdesk in **headless mode** — runs the connection server in a background thread and the system tray on the main thread. No main window is shown.

```bash
./gigidesk --server
```

**Platform behavior:**
- **macOS/Windows**: Spawns server thread → starts tray on main thread → no window
- **Linux**: Starts server directly (tray handled separately via `--tray`)

This is critical for the GIGI Connect use case: the elder's GIGIdesk should run invisibly, always ready for connections.

### `--get-id`

Prints the RustDesk device ID to stdout:

```bash
./gigidesk --get-id
# Output: 123456789
```

### `--get-permanent-password`

Prints the current permanent password to stdout:

```bash
./gigidesk --get-permanent-password
# Output: MySecurePass123
```

---

## Important Files & Configuration

### Rust Side

| File | Purpose |
|---|---|
| `Cargo.toml` | Package name (`gigidesk`), version, dependencies, features |
| `src/core_main.rs` | CLI flag handling, `--password`/`--server`/`--get-id` customizations |
| `src/lib.rs` | APP_NAME loading, custom client detection, `is_rustdesk()` returns false |
| `src/lang/en.rs` | English UI strings (all rebranded to "GIGIdesk") |
| `build.rs` | Native C/C++ compilation, vcpkg integration, linker flags |
| `build.py` | Python build script (used for full builds with `--flutter` flag) |

### Flutter Side

| File | Purpose |
|---|---|
| `flutter/macos/Flutter/CustomArch.xcconfig` | **Architecture selector** — controls x86_64 vs arm64 |
| `flutter/macos/Flutter/Flutter-Release.xcconfig` | Includes `CustomArch.xcconfig` for release builds |
| `flutter/macos/Podfile` | CocoaPods config with dynamic arch reading from `CustomArch.xcconfig` |
| `flutter/macos/Runner/Configs/AppInfo.xcconfig` | `PRODUCT_NAME = GIGIdesk`, `PRODUCT_BUNDLE_IDENTIFIER = com.softaims.gigidesk` |
| `flutter/macos/Runner/AppIcon.icns` | macOS app icon (replaced with GIGI Connect logo) |
| `flutter/macos/Runner/Info.plist` | App metadata, `LSUIElement = 1` (agent app), URL scheme `gigidesk://` |
| `flutter/lib/desktop/pages/desktop_home_page.dart` | Custom left/right pane UI with GIGIdesk branding |
| `flutter/lib/desktop/pages/desktop_setting_page.dart` | Settings page (service toggle hidden) |
| `flutter/assets/icon.svg` | Flutter UI icon (replaced with GIGI Connect logo) |

### Icons & Assets

| File | Size | Purpose |
|---|---|---|
| `flutter/macos/Runner/AppIcon.icns` | 1024×1024 | macOS app icon |
| `res/icon.png` | 1024×1024 | General icon |
| `res/mac-icon.png` | 1024×1024 | macOS-specific icon |
| `res/128x128.png` | 128×128 | Medium icon |
| `res/128x128@2x.png` | 256×256 | Retina medium icon |
| `res/64x64.png` | 64×64 | Small icon |
| `res/32x32.png` | 32×32 | Tiny icon |
| `res/mac-tray-dark-x2.png` | 60×60 | macOS dark tray icon |
| `res/mac-tray-light-x2.png` | 48×48 | macOS light tray icon |
| `res/icon.ico` | — | Windows app icon |
| `res/tray-icon.ico` | — | Windows tray icon |
| `res/logo.svg` | — | SVG logo |
| `flutter/assets/icon.svg` | — | Flutter in-app icon |

---

## How the Architecture Switching Works

This is the most important concept to understand. macOS builds require all binaries, frameworks, and pods to be the **same architecture**. The system uses three coordinated config points:

### 1. `CustomArch.xcconfig` (Master Switch)

This file controls the architecture for the entire Flutter/Xcode build:

```xcconfig
// For Intel:
ARCHS = x86_64
ONLY_ACTIVE_ARCH = NO
EXCLUDED_ARCHS = arm64

// For Apple Silicon:
ARCHS = arm64
ONLY_ACTIVE_ARCH = NO
EXCLUDED_ARCHS = x86_64
```

It's included by `Flutter-Release.xcconfig`:
```xcconfig
#include "CustomArch.xcconfig"
```

This controls:
- The `gigidesk` binary architecture
- All Flutter framework architectures
- All Swift/ObjC plugin compilations

### 2. Podfile `post_install` (Pod Architecture)

The Podfile dynamically reads `CustomArch.xcconfig` and sets the pod build architecture:

```ruby
post_install do |installer|
  custom_arch_file = File.join(__dir__, 'Flutter', 'CustomArch.xcconfig')
  target_arch = 'x86_64' # default
  if File.exist?(custom_arch_file)
    File.foreach(custom_arch_file) do |line|
      if line =~ /^\s*ARCHS\s*=\s*(\S+)/
        target_arch = $1
        break
      end
    end
  end

  installer.pods_project.targets.each do |target|
    flutter_additional_macos_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['ARCHS'] = target_arch
      config.build_settings['ONLY_ACTIVE_ARCH'] = 'NO'
    end
  end
end
```

> **Why this matters**: Without this, pods compile for the host machine's architecture. If you're cross-compiling arm64 on an Intel Mac, the pods would be x86_64 but the Runner expects arm64 → `Unable to find module dependency` errors.

### 3. Cargo `--target` flag (Rust Library)

- Native build: `cargo build --release` → `target/release/`
- Cross build: `cargo build --release --target aarch64-apple-darwin` → `target/aarch64-apple-darwin/release/`

The dylib must then be copied to `target/release/librustdesk.dylib` because Flutter's Xcode project always looks there.

### Architecture Switch Checklist

When switching architectures, you must:

1. ✅ Update `CustomArch.xcconfig` (arm64 ↔ x86_64)
2. ✅ Build Rust with correct target (with or without `--target`)
3. ✅ Copy the correct dylib to `target/release/librustdesk.dylib`
4. ✅ Delete pods and reinstall: `cd flutter/macos && rm -rf Pods Podfile.lock && pod install`
5. ✅ Clean Flutter build: `rm -rf build/macos ~/Library/Developer/Xcode/DerivedData/Runner-*`
6. ✅ Build Flutter: `flutter build macos --release`
7. ✅ Copy the correct `service` binary into the `.app`

> **If you skip any step**, you'll get architecture mismatch crashes or linker errors.

---

## Icons & Branding

### Replacing Icons

All GIGIdesk icons should match the GIGI Connect branding. The source of truth is the `.icns` file at `desktop/assets/logo/icon.icns` (in the GIGI Connect Electron project).

To regenerate all sizes from a new icon:

```bash
# From the Customdesk directory, assuming you have icon.icns as source:
SOURCE="path/to/new/icon.icns"

# macOS app icon
cp "$SOURCE" flutter/macos/Runner/AppIcon.icns

# PNG variants
sips -s format png --resampleHeightWidth 1024 1024 "$SOURCE" --out res/icon.png
sips -s format png --resampleHeightWidth 1024 1024 "$SOURCE" --out res/mac-icon.png
sips -s format png --resampleHeightWidth 256 256 "$SOURCE" --out res/128x128@2x.png
sips -s format png --resampleHeightWidth 128 128 "$SOURCE" --out res/128x128.png
sips -s format png --resampleHeightWidth 64 64 "$SOURCE" --out res/64x64.png
sips -s format png --resampleHeightWidth 32 32 "$SOURCE" --out res/32x32.png

# Tray icons
sips -s format png --resampleHeightWidth 60 60 "$SOURCE" --out res/mac-tray-dark-x2.png
sips -s format png --resampleHeightWidth 48 48 "$SOURCE" --out res/mac-tray-light-x2.png
```

For SVG icons (`flutter/assets/icon.svg`, `res/logo.svg`), replace manually with your branded SVG.

For Windows icons (`res/icon.ico`, `res/tray-icon.ico`), use the same `.ico` file from your brand assets.

---

## Integrating with GIGI Connect Desktop

The built GIGIdesk `.app` bundles are embedded inside the GIGI Connect Electron app as `extraResource`. The naming convention is:

```
desktop/assets/GIGIdesk-x64.app    ← Intel build
desktop/assets/GIGIdesk-arm64.app  ← Apple Silicon build
```

### Saving builds for GIGI Connect

> **Remember**: Both Intel and ARM64 Flutter builds land at the exact same output path (`flutter/build/macos/Build/Products/Release/GIGIdesk.app`). Copy it out **immediately** after each build before starting the next one.

After building each architecture:

```bash
# Run from Customdesk/flutter directory

# After Intel build:
cp -R build/macos/Build/Products/Release/GIGIdesk.app \
  ../../desktop/assets/GIGIdesk-x64.app

# After ARM64 build (this overwrites the same source path):
cp -R build/macos/Build/Products/Release/GIGIdesk.app \
  ../../desktop/assets/GIGIdesk-arm64.app
```

### How GIGI Connect uses GIGIdesk

The Electron app (`desktop/`) bundles GIGIdesk and manages it:

1. **Silent Install**: On first run, copies `GIGIdesk-{arch}.app` → `/Applications/GIGIdesk.app`
2. **Auto-Setup**: Runs `gigidesk --password <elder-password>` to set the permanent password
3. **Headless Launch**: Runs `gigidesk --server` for invisible background operation
4. **Watchdog**: Monitors GIGIdesk via `pgrep -f gigidesk` and restarts if it crashes
5. **ID Retrieval**: Runs `gigidesk --get-id` to get the device ID for registration

Key service files in the Electron app:
- `desktop/src/services/rustdesk.service.js` — Install, setup, launch GIGIdesk
- `desktop/src/services/background-agent.service.js` — Watchdog, tray, auto-start

### Binary Name Consistency

The Cargo binary is `gigidesk` (lowercase). All references in the Electron services must match:

```javascript
// Correct:
const MAC_RUSTDESK_BINARY = '/Applications/GIGIdesk.app/Contents/MacOS/gigidesk';
const RUSTDESK_PROCESS_NAME = 'gigidesk';

// Wrong (will fail to find the binary):
const MAC_RUSTDESK_BINARY = '/Applications/GIGIdesk.app/Contents/MacOS/GIGIdesk';
```

### Forge Config Architecture Selection

The Electron Forge build uses `RUSTDESK_ARCH` env var to select which `.app` to bundle:

```javascript
// forge.config.js
const rustdeskArch = process.env.RUSTDESK_ARCH || 'x64';
const rustdeskApp = `assets/GIGIdesk-${rustdeskArch}.app`;
```

Build commands:
```bash
npm run make:intel   # RUSTDESK_ARCH=x64 electron-forge make
npm run make:arm64   # RUSTDESK_ARCH=arm64 electron-forge make --arch=arm64
```

> **Note**: `make:arm64` needs `--arch=arm64` so that Electron itself is also packaged as a native ARM64 binary (not running under Rosetta).

---

## Troubleshooting

### `Unable to find module dependency: 'desktop_multi_window'` (and other pods)

**Cause**: Pods were compiled for the wrong architecture.

**Fix**:
```bash
cd flutter/macos
rm -rf Pods Podfile.lock
pod install
cd ..
rm -rf build/macos ~/Library/Developer/Xcode/DerivedData/Runner-*
flutter build macos --release
```

### `ld: library not found for -lopus` (or -laom, -lvpx, etc.)

**Cause**: vcpkg triplet not installed for the target architecture.

**Fix**:
```bash
$VCPKG_ROOT/vcpkg install --x-install-root="$VCPKG_ROOT/installed" --triplet=arm64-osx
# or
$VCPKG_ROOT/vcpkg install --x-install-root="$VCPKG_ROOT/installed" --triplet=x64-osx
```

### `Config2::set_option` compile error

**Cause**: Using the wrong config type for `set_option`.

**Fix**: Use `Config::set_option()` not `Config2::set_option()`. `Config2` doesn't expose `set_option`.

### Runtime crash: wrong architecture dylib

**Cause**: `target/release/librustdesk.dylib` is the wrong architecture (e.g., x86_64 dylib in an arm64 app).

**Fix**: Verify with `file target/release/librustdesk.dylib` and re-copy the correct one:
```bash
# For arm64 (after cross-compile on Intel):
cp target/aarch64-apple-darwin/release/liblibrustdesk.dylib target/release/librustdesk.dylib
```

### `flutter clean` breaks the build

**Cause**: `flutter clean` removes the ephemeral directory (Flutter-Generated.xcconfig) and plugin registrations.

**Fix**: Always run `flutter pub get` after `flutter clean`:
```bash
flutter clean
flutter pub get
cd macos && pod install && cd ..
flutter build macos --release
```

### "File is damaged" on Apple Silicon Macs

**Cause**: Electron's Fuses plugin invalidates the code signature during packaging.

**Fix**: The GIGI Connect `forge.config.js` has a `postPackage` hook that re-signs everything:
```javascript
// Signs nested GIGIdesk app first, then the outer Electron app
execSync(`codesign --deep --force --sign - "${rustdeskInResources}"`);
execSync(`codesign --deep --force --sign - "${appPath}"`);
```

If you get this error outside of Electron packaging, manually re-sign:
```bash
codesign --deep --force --sign - /path/to/GIGIdesk.app
```

### `electron-squirrel-startup` module not found

**Cause**: This Windows-only module was listed in Vite's externals, so it doesn't get bundled. On macOS, it's not available.

**Fix**: In the Electron app's `main.js`, the import is wrapped safely:
```javascript
let started = false;
try {
  if (process.platform === 'win32') {
    started = require('electron-squirrel-startup');
  }
} catch { }
```

---

## Quick Reference: Full Build Commands

### Build Both Architectures (Intel Mac)

```bash
cd Customdesk
export VCPKG_ROOT="$HOME/vcpkg"

# ─── Intel (x86_64) ─────────────────────────
cat > flutter/macos/Flutter/CustomArch.xcconfig << 'EOF'
ARCHS = x86_64
ONLY_ACTIVE_ARCH = NO
EXCLUDED_ARCHS = arm64
EOF

MACOSX_DEPLOYMENT_TARGET=10.14 cargo build --features flutter --release
cp target/release/liblibrustdesk.dylib target/release/librustdesk.dylib

cd flutter/macos && rm -rf Pods Podfile.lock && pod install && cd ..
rm -rf build/macos && flutter build macos --release
cp -rf ../target/release/service build/macos/Build/Products/Release/GIGIdesk.app/Contents/MacOS/

# Save Intel build
cp -R build/macos/Build/Products/Release/GIGIdesk.app /path/to/desktop/assets/GIGIdesk-x64.app

# ─── Apple Silicon (arm64) ───────────────────
cd ..
cat > flutter/macos/Flutter/CustomArch.xcconfig << 'EOF'
ARCHS = arm64
ONLY_ACTIVE_ARCH = NO
EXCLUDED_ARCHS = x86_64
EOF

MACOSX_DEPLOYMENT_TARGET=10.14 cargo build --features flutter --release --target aarch64-apple-darwin
cp target/aarch64-apple-darwin/release/liblibrustdesk.dylib target/release/librustdesk.dylib
cp target/aarch64-apple-darwin/release/liblibrustdesk.dylib target/release/liblibrustdesk.dylib

cd flutter/macos && rm -rf Pods Podfile.lock && pod install && cd ..
rm -rf build/macos ~/Library/Developer/Xcode/DerivedData/Runner-*
flutter build macos --release
cp -rf ../target/aarch64-apple-darwin/release/service build/macos/Build/Products/Release/GIGIdesk.app/Contents/MacOS/

# Save ARM64 build
cp -R build/macos/Build/Products/Release/GIGIdesk.app /path/to/desktop/assets/GIGIdesk-arm64.app
```

### Verify Both Builds

```bash
echo "Intel:" && file /path/to/desktop/assets/GIGIdesk-x64.app/Contents/MacOS/gigidesk
echo "ARM64:" && file /path/to/desktop/assets/GIGIdesk-arm64.app/Contents/MacOS/gigidesk
```
