# GIGIdesk Build Script Guide

## Overview

`build-gigidesk.sh` automates the entire GIGIdesk `.app` build pipeline for macOS — from compiling Rust, through Flutter, to a ready-to-embed `.app` bundle saved in `desktop/assets/`.

It handles **Intel (x86_64)** and **Apple Silicon (ARM64)** builds.

---

## Quick Start

```bash
cd Customdesk

# Build Intel only
./build-gigidesk.sh intel

# Build ARM64 only
./build-gigidesk.sh arm64

# Build both (Intel first, then ARM64)
./build-gigidesk.sh all
```

---

## Prerequisites

The script checks these automatically and will abort if anything is missing.

| Requirement | Install / Setup |
|---|---|
| **Rust** (stable) | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
| **Rust targets** | `rustup target add x86_64-apple-darwin aarch64-apple-darwin` |
| **Flutter** (stable) | [flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install) |
| **CocoaPods** | `sudo gem install cocoapods` |
| **vcpkg** | `git clone https://github.com/microsoft/vcpkg ~/vcpkg && ~/vcpkg/bootstrap-vcpkg.sh` |
| **Xcode CLI tools** | `xcode-select --install` |

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `VCPKG_ROOT` | `$HOME/vcpkg` | Path to vcpkg installation |
| `MACOSX_DEPLOYMENT_TARGET` | `10.14` | Minimum macOS version |

You can override them:
```bash
VCPKG_ROOT=/opt/vcpkg ./build-gigidesk.sh all
```

---

## What the Script Does

Each architecture build runs these steps in order:

```
1. Set Architecture        → writes CustomArch.xcconfig (ARCHS / EXCLUDED_ARCHS)
2. Build Rust              → cargo build --features flutter --release --target <target>
3. Copy dylib              → copies liblibrustdesk.dylib → target/release/
4. Reinstall CocoaPods     → clean + pod install in flutter/macos/
5. Build Flutter           → flutter build macos --release (clean DerivedData first)
6. Copy service binary     → embeds the service binary into .app/Contents/MacOS/
7. Verify architectures    → confirms both binaries match expected arch
8. Save .app               → copies to desktop/assets/GIGIdesk-{x64|arm64}.app
```

### Architecture Mapping

| Argument | Rust Target | xcconfig ARCHS | Output File |
|---|---|---|---|
| `intel` / `x64` / `x86_64` | `x86_64-apple-darwin` | `x86_64` | `GIGIdesk-x64.app` |
| `arm64` / `aarch64` / `arm` | `aarch64-apple-darwin` | `arm64` | `GIGIdesk-arm64.app` |

---

## Output

Built `.app` bundles are saved to **two locations**:

### 1. `desktop/assets/` — used by Electron packaging
```
desktop/assets/
├── GIGIdesk-x64.app      # Intel build (~64 MB)
└── GIGIdesk-arm64.app     # ARM64 build (~56 MB)
```

### 2. `Customdesk/builds/` — secure backup in this repo
```
Customdesk/builds/
├── GIGIdesk-x64.app
└── GIGIdesk-arm64.app
```

> `builds/` is gitignored since the `.app` bundles contain large binaries. It serves as a local backup so you always have the last successful build in the Customdesk repo without needing to rebuild.

Each `.app` contains:
```
GIGIdesk.app/Contents/MacOS/
├── GIGIdesk       # Main Flutter + Rust binary
└── service        # Background service binary
```

These are then embedded into the **GIGI Connect** Electron app during `npm run make`.

---

## Typical Build Times

| Build | Cold (first time) | Warm (cached Rust) |
|---|---|---|
| Intel | ~15–20 min | ~3–5 min |
| ARM64 | ~15–20 min | ~3–5 min |
| Both | ~30–40 min | ~6–10 min |

> Rust compilation is the bottleneck. Subsequent builds with only Flutter changes are much faster since Cargo caches compiled crates.

---

## After Building — Making GIGI Connect DMGs

Once both `.app` bundles are in `desktop/assets/`, build the Electron DMGs:

```bash
cd desktop

# Intel DMG
npm run make:intel

# ARM64 DMG
npm run make:arm64
```

Output DMGs land in `desktop/out/make/`.

---

## Troubleshooting

### CocoaPods warnings about custom config
These are **non-fatal** — the build still works. They appear because the Flutter runner uses custom xcconfig files.

### `librustdesk.dylib` architecture mismatch
The script verifies this automatically. If it fails, try a clean Rust build:
```bash
cargo clean
./build-gigidesk.sh <arch>
```

### Flutter build fails with signing errors
Ensure you have valid code signing set up in Xcode, or build unsigned:
```bash
# In flutter/macos/Runner.xcodeproj → Build Settings → set Code Signing Identity to "-"
```

### DerivedData stale cache
The script cleans DerivedData automatically. If you still hit issues:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*
```

### Pod install fails
```bash
cd flutter/macos
rm -rf Pods Podfile.lock
pod repo update
pod install
```

---

## File Reference

| File | Purpose |
|---|---|
| `build-gigidesk.sh` | Main build script (this guide) |
| `flutter/macos/Flutter/CustomArch.xcconfig` | Architecture switch — written by script |
| `Cargo.toml` | Rust package config (`gigidesk`, features: `flutter`) |
| `target/<triple>/release/liblibrustdesk.dylib` | Compiled Rust shared library |
| `target/<triple>/release/service` | Compiled service binary |
| `desktop/assets/GIGIdesk-*.app` | Output — embedded into Electron app |
| `builds/GIGIdesk-*.app` | Output — secure backup in Customdesk repo (gitignored) |

---

---

# GIGIdesk Windows Build Script Guide

## Overview

`build-gigidesk-windows.ps1` automates the entire GIGIdesk Windows build pipeline — from compiling Rust, through Flutter, to a ready-to-embed release folder saved in `gigiChat-desktop/assets/`.

It builds **Windows x64 only** (`x86_64-pc-windows-msvc`).

---

## Quick Start

```powershell
cd Customdesk

# Build Windows x64
.\build-gigidesk-windows.ps1
```

---

## Prerequisites

The script checks these automatically and will abort if anything is missing.

| Requirement | Install / Setup |
|---|---|
| **Rust** (stable, MSVC toolchain) | [rustup.rs](https://rustup.rs) — choose the `x86_64-pc-windows-msvc` host |
| **Rust target** | `rustup target add x86_64-pc-windows-msvc` |
| **Flutter** (stable) | [flutter.dev/docs/get-started/install/windows](https://flutter.dev/docs/get-started/install/windows) |
| **vcpkg** | `git clone https://github.com/microsoft/vcpkg %USERPROFILE%\vcpkg && %USERPROFILE%\vcpkg\bootstrap-vcpkg.bat` |
| **Visual Studio Build Tools 2022** | Required by the MSVC Rust toolchain and Flutter Windows renderer |
| **Windows SDK** | Installed via Visual Studio Installer |

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `VCPKG_ROOT` | `%USERPROFILE%\vcpkg` | Path to vcpkg installation |

You can override before running:
```powershell
$env:VCPKG_ROOT = "C:\tools\vcpkg"
.\build-gigidesk-windows.ps1
```

---

## What the Script Does

```
1. Check prerequisites   → verifies cargo, flutter, rustup, VCPKG_ROOT, Rust target
2. Build Rust            → cargo build --features flutter --release --target x86_64-pc-windows-msvc
3. Copy DLL              → copies librustdesk.dll -> target\release\
4. Build Flutter         → flutter build windows --release  (clean previous build first)
5. Copy DLL to output    → copies librustdesk.dll into Flutter release folder
6. Copy service.exe      → copies service.exe into Flutter release folder
7. Verify output         → confirms GIGIdesk.exe, librustdesk.dll, service.exe exist
8. Save output           → copies Release\ folder to gigiChat-desktop\bin\ and builds\
```

### Architecture

| Target | Rust Triple | Output Folder |
|---|---|---|
| Windows x64 | `x86_64-pc-windows-msvc` | `GIGIdesk-x64\` |

---

## Output

The finished build folder is saved to **two locations**:

### 1. `gigiChat-desktop/bin/` — used by Electron packaging
```
gigiChat-desktop/bin/
└── GIGIdesk-x64/
    ├── GIGIdesk.exe
    ├── librustdesk.dll
    ├── service.exe
    ├── flutter_windows.dll
    └── data/
```

### 2. `Customdesk/builds/` — local backup in this repo
```
Customdesk/builds/
└── GIGIdesk-x64/
    ├── GIGIdesk.exe
    ├── librustdesk.dll
    ├── service.exe
    └── ...
```

> `builds/` is gitignored since the release folders contain large binaries.

---

## Typical Build Times

| Build | Cold (first time) | Warm (cached Rust) |
|---|---|---|
| Windows x64 | ~20–30 min | ~4–6 min |

> Rust compilation (`x86_64-pc-windows-msvc`) is the main bottleneck. Subsequent builds with only Flutter changes are much faster.

---

## After Building — Making GIGI Connect Windows Installers

Once `GIGIdesk-x64\` is in `gigiChat-desktop/bin/`, build the Electron Windows package:

```powershell
cd gigiChat-desktop

# Windows x64 installer
npm run make
```

Output lands in `gigiChat-desktop/out/make/`.

---

## Troubleshooting

### `cargo build` fails with link errors
Ensure the **MSVC Build Tools** are installed and the active Rust toolchain is `stable-x86_64-pc-windows-msvc`:
```powershell
rustup show
rustup default stable-x86_64-pc-windows-msvc
```

### `librustdesk.dll` not found after Rust build
Check that `[lib] crate-type` in `Cargo.toml` includes `cdylib`. The expected output path is:
```
target\x86_64-pc-windows-msvc\release\librustdesk.dll
```

### Flutter build fails
Make sure Visual Studio with the **Desktop development with C++** workload is installed. Run:
```powershell
flutter doctor
```
and resolve any reported issues before re-running the script.

### `VCPKG_ROOT` not found
Either set `$env:VCPKG_ROOT` before running, or install vcpkg at the default path `%USERPROFILE%\vcpkg`.

### PowerShell execution policy
If PowerShell blocks the script, run:
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

---

## File Reference

| File | Purpose |
|---|---|
| `build-gigidesk-windows.ps1` | Windows build script (this section) |
| `Cargo.toml` | Rust package config (`gigidesk`, features: `flutter`) |
| `target\x86_64-pc-windows-msvc\release\librustdesk.dll` | Compiled Rust shared library (Windows) |
| `target\x86_64-pc-windows-msvc\release\service.exe` | Compiled service binary (Windows) |
| `gigiChat-desktop\bin\GIGIdesk-x64\` | Output — embedded into Electron app |
| `builds\GIGIdesk-x64\` | Output — local backup in Customdesk repo (gitignored) |
