# GIGIdesk Build Script Guide

## Overview

`build-gigidesk.sh` automates the entire GIGIdesk `.app` build pipeline for macOS — from compiling Rust, through Flutter, to a ready-to-embed `.app` bundle saved in `desktop/bin/`.

It handles **Intel (x86_64)** and **Apple Silicon (ARM64)** builds.

---

## Quick Start

```bash
cd Customdesk

# Build Intel only (staging relay — default, omit the env arg)
./build-gigidesk.sh intel

# Build ARM64 only
./build-gigidesk.sh arm64

# Build both (Intel first, then ARM64)
./build-gigidesk.sh all

# Same, but pointed at the production relay instead
./build-gigidesk.sh intel production
./build-gigidesk.sh arm64 production
./build-gigidesk.sh all production
```

### Environments

The second argument (`staging` | `production`, default `staging`) picks which
RustDesk relay — IP + public key, `libs/hbb_common/src/config.rs` — gets
compiled into the binary via the `env_production` Cargo feature. Staging is
the default so a bare `./build-gigidesk.sh all` never accidentally ships
pointed at production. See the main `README.md`'s Configuration section for
the compile-time mechanism. The build is archived per environment (see
Output below) and picked up automatically by the matching GIGI Squad
`make:staging:*` / `make:production:*` script — see `PACKAGING.md`.

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
8. Save .app               → archives to desktop/bin/gigidesk-archive/GIGIdesk-<env>-{x64|arm64}.app
```

### Architecture Mapping

| Argument | Rust Target | xcconfig ARCHS | Output File |
|---|---|---|---|
| `intel` / `x64` / `x86_64` | `x86_64-apple-darwin` | `x86_64` | `GIGIdesk-<env>-x64.app` |
| `arm64` / `aarch64` / `arm` | `aarch64-apple-darwin` | `arm64` | `GIGIdesk-<env>-arm64.app` |

---

## Output

Built `.app` bundles are archived per environment+arch, so staging and
production builds never overwrite each other:

```
desktop/bin/gigidesk-archive/
├── GIGIdesk-staging-x64.app      # Intel, staging (~64 MB)
├── GIGIdesk-staging-arm64.app    # ARM64, staging (~56 MB)
├── GIGIdesk-production-x64.app
└── GIGIdesk-production-arm64.app
```

`desktop/bin/gigidesk-archive/` is gitignored (whole `bin/` is) since the
`.app` bundles contain large binaries.

GIGI Squad's `make:staging:*` / `make:production:*` scripts run
`scripts/select-gigidesk-build.js` first, which copies the archived build
matching that script's environment into the fixed path Electron Forge
actually bundles: `desktop/bin/GIGIdesk-<arch>.app`. This happens
automatically on every run — you never copy these by hand, and there's no
manual build-order to get wrong.

Each `.app` contains:
```
GIGIdesk.app/Contents/MacOS/
├── GIGIdesk       # Main Flutter + Rust binary
└── service        # Background service binary
```

These are then embedded into the **GIGI Squad** Electron app during `npm run make`.

---

## Typical Build Times

| Build | Cold (first time) | Warm (cached Rust) |
|---|---|---|
| Intel | ~15–20 min | ~3–5 min |
| ARM64 | ~15–20 min | ~3–5 min |
| Both | ~30–40 min | ~6–10 min |

> Rust compilation is the bottleneck. Subsequent builds with only Flutter changes are much faster since Cargo caches compiled crates.

---

## After Building — Making GIGI Squad DMGs

Once both `.app` bundles are in `desktop/bin/`, build the Electron DMGs — **use the
matching environment** (see Environments above):

```bash
cd desktop

# Staging
npm run make:intel     # Intel DMG
npm run make:arm64     # ARM64 DMG

# Production
npm run make:production:intel
npm run make:production:arm64
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
| `Cargo.toml` | Rust package config (`gigidesk`, features: `flutter`, `env_production`) |
| `libs/hbb_common/src/config.rs` | Relay identity constants (`RENDEZVOUS_SERVERS`/`RS_PUB_KEY`), `env_production`-gated |
| `target/<triple>/release/liblibrustdesk.dylib` | Compiled Rust shared library |
| `target/<triple>/release/service` | Compiled service binary |
| `desktop/bin/gigidesk-archive/GIGIdesk-<env>-*.app` | Output — archived per environment+arch, never overwritten |
| `desktop/bin/GIGIdesk-*.app` | Staged build — refreshed automatically for whichever environment is being packaged (see `../desktop/PACKAGING.md`) |

---

---

# GIGIdesk Windows Build Script Guide

## Overview

`build-gigidesk-windows.ps1` automates the entire GIGIdesk Windows build pipeline — from compiling Rust, through Flutter, to a ready-to-embed release folder saved in `gigiChat-desktop\bin\`.

It builds **Windows x64 only** (`x86_64-pc-windows-msvc`).

---

## Quick Start

```powershell
cd Customdesk

# Build Windows x64 (staging relay — default, omit -Environment)
.\build-gigidesk-windows.ps1

# Same, but pointed at the production relay instead
.\build-gigidesk-windows.ps1 -Environment production
```

### Environments

Same mechanism as the macOS script (see its Environments section above) —
`-Environment` (default `staging`) sets the `env_production` Cargo feature,
which picks the relay identity compiled into `librustdesk.dll` from
`libs/hbb_common/src/config.rs`. The build is archived per environment (see
Output below) and picked up automatically by the matching GIGI Squad
`build:win:staging` / `build:win:production` / `dist:staging` /
`dist:production` script — see `../desktop/PACKAGING.md`.

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
8. Save output           → archives Release\ folder to desktop\bin\rustdesk-windows-<Environment>\
```

### Architecture

| Target | Rust Triple | Output Folder |
|---|---|---|
| Windows x64 | `x86_64-pc-windows-msvc` | `rustdesk-windows-<Environment>\` |

---

## Output

The finished build folder is archived per environment, so staging and
production builds never overwrite each other:

```
desktop/bin/
├── rustdesk-windows-staging/
│   ├── GIGIdesk.exe
│   ├── librustdesk.dll
│   ├── service.exe
│   ├── flutter_windows.dll
│   └── data/
└── rustdesk-windows-production/
    └── ... (same layout)
```

`desktop/bin/` is gitignored since the release folders contain large binaries.

GIGI Squad's `build:win:staging` / `build:win:production` / `dist:staging` /
`dist:production` scripts run `scripts/select-gigidesk-build.js` first, which
copies the archived folder matching that script's environment into the fixed
path electron-builder actually bundles: `desktop/bin/rustdesk-windows/`. This
happens automatically on every run.

---

## Typical Build Times

| Build | Cold (first time) | Warm (cached Rust) |
|---|---|---|
| Windows x64 | ~20–30 min | ~4–6 min |

> Rust compilation (`x86_64-pc-windows-msvc`) is the main bottleneck. Subsequent builds with only Flutter changes are much faster.

---

## After Building — Making GIGI Squad Windows Installers

Once `GIGIdesk-x64\` is in `gigiChat-desktop/bin/`, build the Electron Windows package —
**use the matching environment** (see Environments above):

```powershell
cd gigiChat-desktop

# Staging — Windows x64 installer
npm run make

# Production — set GIGI_ENV first (PowerShell inline VAR=value syntax
# doesn't work on Windows the way it does in the macOS npm scripts)
$env:GIGI_ENV = 'production'
npm run make
```

Output lands in `gigiChat-desktop/out/make/`. See `../desktop/README.md`'s Environments
section for the electron-builder path (`npm run dist` / `dist:production`) too — either
packager works on Windows, this section covers the Electron Forge one since it's what
the existing Windows guide already used.

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
| `Cargo.toml` | Rust package config (`gigidesk`, features: `flutter`, `env_production`) |
| `libs\hbb_common\src\config.rs` | Relay identity constants, `env_production`-gated |
| `target\x86_64-pc-windows-msvc\release\librustdesk.dll` | Compiled Rust shared library (Windows) |
| `target\x86_64-pc-windows-msvc\release\service.exe` | Compiled service binary (Windows) |
| `desktop\bin\rustdesk-windows-<Environment>\` | Output — archived per environment, never overwritten |
| `desktop\bin\rustdesk-windows\` | Staged build — refreshed automatically for whichever environment is being packaged (see `..\desktop\PACKAGING.md`) |
