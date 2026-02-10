# RustDesk Development Environment Setup Guide

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Prerequisites](#prerequisites)
3. [macOS Setup](#macos-setup)
4. [Windows Setup](#windows-setup)
5. [Building the Project](#building-the-project)
6. [Troubleshooting](#troubleshooting)
7. [Additional Resources](#additional-resources)

---

## Project Overview

**RustDesk** is an open-source remote desktop application written in Rust with a Flutter-based UI for both desktop and mobile platforms.

### Technology Stack

| Component | Technology |
|-----------|------------|
| Core Application | Rust |
| Desktop/Mobile UI | Flutter |
| Legacy UI (Deprecated) | Sciter |
| Video Codecs | libvpx, aom, libyuv |
| Audio Codec | Opus |
| Package Manager | vcpkg (C++ dependencies) |

### Project Structure

```
Customdesk/
├── src/                    # Main Rust application code
│   ├── server/             # Audio/clipboard/input/video services
│   ├── client.rs           # Peer connection handling
│   ├── platform/           # Platform-specific code
│   └── ui/                 # Legacy Sciter UI (deprecated)
├── flutter/                # Flutter UI for desktop & mobile
│   ├── lib/desktop/        # Desktop-specific Flutter code
│   ├── lib/mobile/         # Mobile-specific Flutter code
│   └── lib/common/         # Shared Flutter components
├── libs/                   # Core Rust libraries
│   ├── hbb_common/         # Video codec, config, network utils
│   ├── scrap/              # Screen capture
│   ├── enigo/              # Keyboard/mouse control
│   └── clipboard/          # Cross-platform clipboard
├── res/                    # Resources and build scripts
├── build.py                # Main build script
└── Cargo.toml              # Rust package manifest
```

### Minimum Rust Version

- **Rust 1.75** or later

### Flutter Version

- **Flutter SDK ^3.1.0** or later

---

## Prerequisites

Before setting up the development environment, ensure you have:

- **Git** installed and configured
- **Internet connection** for downloading dependencies
- At least **20 GB** of free disk space
- Administrator/sudo privileges

---

## macOS Setup

### Step 1: Install Xcode Command Line Tools

Open Terminal and run:

```bash
xcode-select --install
```

If prompted, click **Install** and agree to the license.

### Step 2: Install Homebrew

If not already installed:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Add Homebrew to PATH (for Apple Silicon Macs):

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

### Step 3: Install System Dependencies

```bash
brew install cmake nasm yasm ninja llvm pkg-config wget curl zip unzip
```

### Step 4: Install Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

Select option **1** for default installation. Then reload the shell:

```bash
source "$HOME/.cargo/env"
```

Verify installation:

```bash
rustc --version
cargo --version
```

### Step 5: Install vcpkg

```bash
cd ~
git clone https://github.com/microsoft/vcpkg
cd vcpkg
git checkout 2023.04.15
./bootstrap-vcpkg.sh
```

Set the environment variable (add to `~/.zshrc` or `~/.bashrc`):

```bash
echo 'export VCPKG_ROOT="$HOME/vcpkg"' >> ~/.zshrc
echo 'export PATH="$VCPKG_ROOT:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### Step 6: Install vcpkg Dependencies

```bash
cd $VCPKG_ROOT
./vcpkg install libvpx libyuv opus aom
```

> **Note:** This step may take 15-30 minutes depending on your system.

### Step 7: Install Flutter SDK

```bash
cd ~
git clone https://github.com/flutter/flutter.git -b stable
```

Add Flutter to PATH:

```bash
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Verify and accept licenses:

```bash
flutter doctor
flutter doctor --android-licenses
```

### Step 8: Download Sciter Library (Legacy UI)

> **Note:** This is optional if you're only building the Flutter version.

```bash
cd /path/to/Customdesk
mkdir -p target/debug
wget https://raw.githubusercontent.com/c-smile/sciter-sdk/master/bin.osx/libsciter.dylib
mv libsciter.dylib target/debug/
```

### Step 9: Clone and Setup the Project

```bash
cd /path/to/Customdesk
git submodule update --init --recursive
```

Install Flutter dependencies:

```bash
cd flutter
flutter pub get
cd ..
```

### Step 10: Verify macOS Setup

```bash
# Check Rust
rustc --version

# Check vcpkg
echo $VCPKG_ROOT

# Check Flutter
flutter doctor

# Check cmake
cmake --version
```

---

## Windows Setup

### Step 1: Install Visual Studio Build Tools

Download and install **Visual Studio 2022** (Community Edition is free):

- [Download Visual Studio](https://visualstudio.microsoft.com/downloads/)

During installation, select:

- ☑️ **Desktop development with C++**
- ☑️ **Windows 10/11 SDK** (latest version)
- ☑️ **MSVC v143 - VS 2022 C++ x64/x86 build tools**

### Step 2: Install Git for Windows

Download and install:

- [Git for Windows](https://git-scm.com/download/win)

Use default installation options.

### Step 3: Install Rust

Download and run the Rust installer:

- [Rust Installer (rustup-init.exe)](https://www.rust-lang.org/tools/install)

Open a **new** Command Prompt or PowerShell and verify:

```powershell
rustc --version
cargo --version
```

### Step 4: Install Required Tools

Install using **winget** (Windows Package Manager):

```powershell
winget install Kitware.CMake
winget install NASM.NASM
winget install yasm.yasm
winget install Ninja-build.Ninja
winget install LLVM.LLVM
```

Or download manually:

| Tool | Download Link |
|------|---------------|
| CMake | [cmake.org/download](https://cmake.org/download/) |
| NASM | [nasm.us](https://www.nasm.us/pub/nasm/releasebuilds/) |
| YASM | [yasm.tortall.net](http://yasm.tortall.net/Download.html) |
| LLVM | [releases.llvm.org](https://releases.llvm.org/) |

**Add tools to System PATH:**

1. Press `Win + R`, type `sysdm.cpl`, press Enter
2. Go to **Advanced** → **Environment Variables**
3. Under **System variables**, find `Path` and click **Edit**
4. Add paths to installed tools (e.g., `C:\Program Files\CMake\bin`)

### Step 5: Install vcpkg

Open **PowerShell** (as Administrator):

```powershell
cd C:\
git clone https://github.com/microsoft/vcpkg
cd vcpkg
git checkout 2023.04.15
.\bootstrap-vcpkg.bat
```

Set environment variable permanently:

```powershell
[Environment]::SetEnvironmentVariable("VCPKG_ROOT", "C:\vcpkg", "User")
```

**Restart PowerShell**, then verify:

```powershell
echo $env:VCPKG_ROOT
```

### Step 6: Install vcpkg Dependencies

```powershell
cd C:\vcpkg
.\vcpkg install libvpx:x64-windows-static libyuv:x64-windows-static opus:x64-windows-static aom:x64-windows-static
```

> **Note:** This step may take 30-60 minutes.

### Step 7: Install Flutter SDK

Option A - Using Git:

```powershell
cd C:\
git clone https://github.com/flutter/flutter.git -b stable
```

Option B - Download ZIP from [flutter.dev](https://docs.flutter.dev/get-started/install/windows)

Add Flutter to PATH:

1. Press `Win + R`, type `sysdm.cpl`, press Enter
2. Go to **Advanced** → **Environment Variables**
3. Under **User variables**, find `Path` and click **Edit**
4. Add `C:\flutter\bin`

Verify and accept licenses:

```powershell
flutter doctor
flutter doctor --android-licenses
```

### Step 8: Download Sciter Library (Legacy UI)

> **Note:** This is optional if you're only building the Flutter version.

```powershell
cd C:\path\to\Customdesk
mkdir -p target\debug
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/c-smile/sciter-sdk/master/bin.win/x64/sciter.dll" -OutFile "target\debug\sciter.dll"
```

### Step 9: Clone and Setup the Project

```powershell
cd C:\path\to\Customdesk
git submodule update --init --recursive
```

Install Flutter dependencies:

```powershell
cd flutter
flutter pub get
cd ..
```

### Step 10: Verify Windows Setup

```powershell
# Check Rust
rustc --version

# Check vcpkg
echo $env:VCPKG_ROOT

# Check Flutter
flutter doctor

# Check cmake
cmake --version

# Check Visual Studio
where cl.exe
```

---

## Building the Project

### Build Commands Summary

| Build Type | Command |
|------------|---------|
| Debug (Sciter UI) | `cargo run` |
| Release (Sciter UI) | `cargo build --release` |
| Flutter Desktop | `python3 build.py --flutter` |
| Flutter Desktop (Release) | `python3 build.py --flutter --release` |
| Flutter with HW Codec | `python3 build.py --flutter --hwcodec` |
| VRAM Support (Windows) | `python3 build.py --flutter --vram` |

### Building on macOS

#### Option 1: Sciter UI (Legacy)

```bash
cd /path/to/Customdesk
VCPKG_ROOT=$HOME/vcpkg cargo run
```

#### Option 2: Flutter UI (Recommended)

```bash
cd /path/to/Customdesk
python3 build.py --flutter
```

For release build:

```bash
python3 build.py --flutter --release
```

#### Option 3: With Hardware Codec Support

```bash
python3 build.py --flutter --hwcodec
```

### Building on Windows

Open **Developer Command Prompt for VS 2022** or **PowerShell**.

#### Option 1: Sciter UI (Legacy)

```powershell
cd C:\path\to\Customdesk
$env:VCPKG_ROOT = "C:\vcpkg"
cargo run
```

#### Option 2: Flutter UI (Recommended)

```powershell
cd C:\path\to\Customdesk
python build.py --flutter
```

For release build:

```powershell
python build.py --flutter --release
```

#### Option 3: With Hardware Codec & VRAM Support

```powershell
python build.py --flutter --hwcodec --vram
```

### Build Output Locations

| Platform | Output Directory |
|----------|------------------|
| macOS | `flutter/build/macos/Build/Products/Release/` |
| Windows | `flutter/build/windows/x64/runner/Release/` |
| Linux | `flutter/build/linux/x64/release/bundle/` |
| Rust Binary | `target/release/rustdesk` (or `rustdesk.exe`) |

---

## Troubleshooting

### Common Issues

#### 1. vcpkg Dependencies Not Found

**Error:** `Could not find package libvpx`

**Solution:**

```bash
# macOS
cd $VCPKG_ROOT && ./vcpkg install libvpx libyuv opus aom

# Windows
cd $env:VCPKG_ROOT && .\vcpkg install libvpx:x64-windows-static libyuv:x64-windows-static opus:x64-windows-static aom:x64-windows-static
```

#### 2. Rust Version Too Old

**Error:** `rustc 1.XX is too old`

**Solution:**

```bash
rustup update stable
```

#### 3. Flutter Doctor Issues

**Error:** `[✗] Flutter`

**Solution:**

```bash
flutter doctor -v
flutter upgrade
```

#### 4. Git Submodules Not Initialized

**Error:** `Submodule 'xxx' not found`

**Solution:**

```bash
git submodule update --init --recursive
```

#### 5. Windows: MSVC Not Found

**Error:** `link.exe not found`

**Solution:**
- Open **Visual Studio Installer**
- Ensure **Desktop development with C++** workload is installed
- Use **Developer Command Prompt for VS 2022** instead of regular PowerShell

#### 6. macOS: Sciter Library Not Found

**Error:** `dyld: Library not loaded: libsciter.dylib`

**Solution:**

```bash
mkdir -p target/debug
wget -O target/debug/libsciter.dylib https://raw.githubusercontent.com/c-smile/sciter-sdk/master/bin.osx/libsciter.dylib
```

#### 7. Permission Denied on macOS

**Error:** `Permission denied`

**Solution:**

```bash
chmod +x build.py
chmod +x flutter/build_*.sh
```

### Environment Variable Checklist

| Variable | macOS | Windows |
|----------|-------|---------|
| `VCPKG_ROOT` | `$HOME/vcpkg` | `C:\vcpkg` |
| `PATH` (Flutter) | `$HOME/flutter/bin` | `C:\flutter\bin` |
| `PATH` (Rust) | `$HOME/.cargo/bin` | `%USERPROFILE%\.cargo\bin` |

---

## Additional Resources

### Official Documentation

- [RustDesk Build Documentation](https://rustdesk.com/docs/en/dev/build/)
- [Rust Installation Guide](https://www.rust-lang.org/tools/install)
- [Flutter Installation Guide](https://docs.flutter.dev/get-started/install)
- [vcpkg Documentation](https://vcpkg.io/en/getting-started.html)

### Community & Support

- **Discord:** [discord.gg/nDceKgxnkV](https://discord.gg/nDceKgxnkV)
- **GitHub Issues:** [github.com/rustdesk/rustdesk/issues](https://github.com/rustdesk/rustdesk/issues)
- **FAQ:** [github.com/rustdesk/rustdesk/wiki/FAQ](https://github.com/rustdesk/rustdesk/wiki/FAQ)

### Feature Flags Reference

| Feature | Description | Platform |
|---------|-------------|----------|
| `hwcodec` | Hardware video encoding/decoding | All |
| `vram` | VRAM optimization | Windows only |
| `flutter` | Enable Flutter UI | All |
| `screencapturekit` | ScreenCaptureKit support | macOS only |
| `unix-file-copy-paste` | File clipboard support | Unix |

---

## Quick Reference Card

### macOS Quick Setup

```bash
# 1. Install dependencies
xcode-select --install
brew install cmake nasm yasm ninja llvm pkg-config wget

# 2. Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"

# 3. Install vcpkg
cd ~ && git clone https://github.com/microsoft/vcpkg && cd vcpkg
git checkout 2023.04.15 && ./bootstrap-vcpkg.sh
export VCPKG_ROOT="$HOME/vcpkg"
./vcpkg install libvpx libyuv opus aom

# 4. Install Flutter
cd ~ && git clone https://github.com/flutter/flutter.git -b stable
export PATH="$HOME/flutter/bin:$PATH"

# 5. Build
cd /path/to/Customdesk
git submodule update --init --recursive
python3 build.py --flutter
```

### Windows Quick Setup

```powershell
# 1. Install Visual Studio with C++ workload
# 2. Install tools
winget install Kitware.CMake NASM.NASM Ninja-build.Ninja LLVM.LLVM

# 3. Install Rust (download rustup-init.exe from rust-lang.org)

# 4. Install vcpkg
cd C:\ && git clone https://github.com/microsoft/vcpkg && cd vcpkg
git checkout 2023.04.15 && .\bootstrap-vcpkg.bat
[Environment]::SetEnvironmentVariable("VCPKG_ROOT", "C:\vcpkg", "User")
.\vcpkg install libvpx:x64-windows-static libyuv:x64-windows-static opus:x64-windows-static aom:x64-windows-static

# 5. Install Flutter
cd C:\ && git clone https://github.com/flutter/flutter.git -b stable
# Add C:\flutter\bin to PATH

# 6. Build
cd C:\path\to\Customdesk
git submodule update --init --recursive
python build.py --flutter
```

---

**Document Version:** 1.0  
**Last Updated:** February 2026  
**RustDesk Version:** 1.4.5
