# Windows setup — building GIGIdesk from a clean machine

How to take a **fresh Windows 10/11 x64 box** to a finished GIGIdesk Windows
build (`rustdesk-windows-<environment>/`) that `apps/desktop` can package into
the GIGI Squad installer.

Scope is this repo only — the Rust engine plus the Flutter Windows UI. Packaging
the Electron installer (Node, Watch Together / castLabs EVS, NSIS, Authenticode
signing) is the desktop repo's job: see
[`../desktop/docs/windows-setup.md`](../desktop/docs/windows-setup.md).

Related docs in this repo: [`BUILDSCRIPT_GUIDE.md`](./BUILDSCRIPT_GUIDE.md)
(what the build script does, step by step), [`PACKAGING.md`](./PACKAGING.md)
(command/output matrix), [`README.md`](./README.md) (fork overview and the
compile-time relay configuration).

---

## 0. What you end up with

```text
apps/desktop/bin/rustdesk-windows-staging/      ← read by desktop's build pipeline
apps/customdesk/builds/staging/windows/         ← local backup copy (nothing reads it)
```

containing `gigidesk.exe`, `librustdesk.dll`, `service.exe`, `flutter_windows.dll`
and `data/`.

Budget, on a reasonably fast machine:

| Step | Cold (first run) |
|---|---|
| Tool installs (VS, Rust, LLVM, Flutter) | 40–60 min, mostly download |
| `vcpkg install` (builds ffmpeg from source) | 45–90 min |
| Bridge codegen | 3–5 min |
| `build-gigidesk-windows.ps1` | 20–30 min (warm rebuilds: 4–6 min) |

Disk: keep **~60 GB free**. `target/` alone reaches ~8 GB, and vcpkg's
`installed/` + `buildtrees/` for a static triplet is bigger than that.

---

## 1. Machine prerequisites

| Requirement | Notes |
|---|---|
| Windows 10 / 11 **x64** | ARM64 Windows is not a supported target — the Rust triple is hardcoded to `x86_64-pc-windows-msvc` |
| 16 GB RAM | 8 GB will build, slowly; LTO-linking `librustdesk.dll` is the memory peak |
| Administrator access | Only for installing tools and setting machine-level environment variables. The build itself runs unelevated |
| Network access to | github.com (many Cargo deps are git dependencies), crates.io, pub.dev, Flutter artifact storage, vcpkg's download mirrors |

Enable long paths before cloning — Rust's `target/` plus vcpkg's `buildtrees/`
go well past 260 characters. From an **elevated** PowerShell:

```powershell
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' `
  -Name LongPathsEnabled -Value 1 -PropertyType DWORD -Force
git config --global core.longpaths true
```

Also exclude your build roots from Defender real-time scanning if you can — it
roughly halves cold Rust build time:

```powershell
Add-MpPreference -ExclusionPath 'C:\gigi', 'C:\vcpkg', 'C:\src\flutter', "$env:USERPROFILE\.cargo"
```

---

## 2. Source layout — both repos are required

`build-gigidesk-windows.ps1` writes its output into the **desktop repo's** `bin/`
directory, and resolves it as a sibling of this repo (`..\gigiChat-desktop\` or
`..\desktop\`). If neither exists the script aborts with
`Could not locate desktop project directory` before compiling anything. So clone
both, side by side, with these directory names:

```text
C:\gigi\
└── apps\
    ├── customdesk\     Softaims/Customdesk,       branch gigidesk-customUI
    └── desktop\        Softaims/gigiChat-desktop, branch main
```

```powershell
New-Item -ItemType Directory -Force C:\gigi\apps | Out-Null
Set-Location C:\gigi\apps
git clone -b gigidesk-customUI https://github.com/Softaims/Customdesk.git customdesk
git clone -b main              https://github.com/Softaims/gigiChat-desktop.git desktop
```

Neither repo may be cloned inside the other. `hbb_common` is vendored into this
repo, so **no `--recurse-submodules`** is needed (the `git submodule update`
step in the older `devSetup.md` is stale).

PowerShell blocks unsigned local scripts by default; allow them once for your
user:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

---

## 3. Visual Studio 2022 (C++ toolchain)

Install **Visual Studio 2022** (Community is fine) or the standalone Build
Tools, with:

- **Desktop development with C++** workload
- **MSVC v143 — VS 2022 C++ x64/x86 build tools**
- **Windows 10 SDK** or **Windows 11 SDK** (latest)
- **C++ CMake tools for Windows**

Required by three separate things: the MSVC Rust toolchain's linker, the C/C++
compiled into the engine (`src/platform/windows.cc`,
`libs/clipboard/src/windows/wf_cliprdr.c` via the `cc` crate), and Flutter's
Windows runner.

---

## 4. Rust

Install rustup from <https://rustup.rs> and take the default **MSVC** host.

```powershell
rustup default stable-x86_64-pc-windows-msvc
rustup target add x86_64-pc-windows-msvc
rustc --version    # must be >= 1.75 (Cargo.toml's rust-version floor)
```

Make sure the host toolchain really is `x86_64` and not `i686` — `libs/scrap`'s
build script only supports a 64-bit build, and a 32-bit host toolchain produces
confusing link errors about symbol prefixes.

Two notes on versions:

- Upstream RustDesk CI pins **1.75**; the shipped macOS GIGIdesk builds were made
  with a current stable (1.93). The lockfile is pinned conservatively enough that
  both work. Start on current stable; if a dependency fails to compile, pin with
  `rustup override set 1.75.0` inside `apps\customdesk`.
- `.cargo/config.toml` sets `git-fetch-with-cli = true`, so Cargo shells out to
  `git` for the 40+ git dependencies. Git must be on `PATH` and able to reach
  GitHub non-interactively (use HTTPS, or an SSH agent that is already
  unlocked) — otherwise `cargo build` hangs on a credential prompt.

---

## 5. LLVM / libclang

`libs/scrap` generates its libvpx / aom / libyuv FFI bindings with **bindgen
0.65**, which needs `libclang.dll` at build time and finds it via `LIBCLANG_PATH`.

Install **LLVM 15.0.6 x64** — the version upstream CI uses, and the safest match
for bindgen 0.65 (newer LLVM usually works, but this is the proven one):
<https://github.com/llvm/llvm-project/releases/tag/llvmorg-15.0.6> →
`LLVM-15.0.6-win64.exe`.

From an **elevated** PowerShell:

```powershell
[Environment]::SetEnvironmentVariable('LIBCLANG_PATH', 'C:\Program Files\LLVM\bin', 'Machine')
```

Then open a new shell and confirm `Test-Path "$env:LIBCLANG_PATH\libclang.dll"`
is `True`.

---

## 6. Flutter

Use **Flutter stable 3.35 or newer**. This is not the upstream RustDesk pin —
the fork's committed `flutter/pubspec.lock` resolves against
`dart >=3.9.0` / `flutter >=3.35.0`, so Flutter 3.24.x cannot resolve it.

```powershell
New-Item -ItemType Directory -Force C:\src | Out-Null
Set-Location C:\src
git clone -b stable https://github.com/flutter/flutter.git
```

Add `C:\src\flutter\bin` to `PATH` (elevated, machine-wide):

```powershell
[Environment]::SetEnvironmentVariable(
  'Path',
  [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';C:\src\flutter\bin',
  'Machine'
)
```

New shell, then:

```powershell
flutter config --enable-windows-desktop
flutter precache --windows
flutter doctor -v
```

Every item under **Visual Studio — develop Windows apps** must be green before
you continue. Android/Chrome warnings are irrelevant here.

> **Skip two upstream-CI-only steps.** `.github/workflows/flutter-build.yml`
> applies `.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff` and
> swaps in RustDesk's custom prebuilt Windows engine. Both exist solely to keep
> upstream's Flutter **3.24.5** pin working; they do not apply to a 3.35+ SDK
> (the patch won't apply, and the prebuilt engine is version-specific). The GIGI
> build script does neither.

---

## 7. vcpkg (native C/C++ dependencies)

The engine statically links libvpx, aom, libyuv and opus. Two hard constraints,
both baked into the source:

- **Triplet must be `x64-windows-static`.** `libs/scrap/build.rs` hardcodes that
  name on Windows, and `.cargo/config.toml` compiles with
  `-Ctarget-feature=+crt-static`, so a dynamic triplet mismatches the CRT and
  fails at link time.
- **Libraries must land in `%VCPKG_ROOT%\installed\x64-windows-static`.** That's
  where `build.rs` looks (unless you override `VCPKG_INSTALLED_ROOT`).

Pin vcpkg to the commit that matches this repo's `vcpkg.json` baseline:

```powershell
Set-Location C:\
git clone https://github.com/microsoft/vcpkg.git
Set-Location C:\vcpkg
git checkout 120deac3062162151622ca4860575a33844ba10b
.\bootstrap-vcpkg.bat -disableMetrics
```

Elevated, once:

```powershell
[Environment]::SetEnvironmentVariable('VCPKG_ROOT', 'C:\vcpkg', 'Machine')
```

New shell, then install **from this repo's root** so vcpkg reads `vcpkg.json`
(its pinned baseline *and* the patched overlay ports in `res/vcpkg/`):

```powershell
Set-Location C:\gigi\apps\customdesk
$env:VCPKG_DEFAULT_HOST_TRIPLET = 'x64-windows-static'
& "$env:VCPKG_ROOT\vcpkg.exe" install `
  --triplet x64-windows-static `
  --x-install-root="$env:VCPKG_ROOT\installed"
```

`VCPKG_DEFAULT_HOST_TRIPLET` matters: the manifest lists most ports twice
(`"host": true` and `"host": false`), and without it the host copies build a
second time as `x64-windows`, roughly doubling an already long install.

This is the slow part, mainly because the manifest pulls in **ffmpeg** (with the
`amf` / `nvcodec` / `qsv` features) through `res/vcpkg/ffmpeg`. Nothing in a
default GIGIdesk build links ffmpeg — it's only needed for the optional
`hwcodec` / `vram` features — but manifest mode installs the whole manifest
regardless. If you're only ever building the default feature set and want the
hour back, classic mode installs just what's linked:

```powershell
& "$env:VCPKG_ROOT\vcpkg.exe" install `
  libvpx:x64-windows-static libyuv:x64-windows-static `
  aom:x64-windows-static   opus:x64-windows-static `
  --overlay-ports="C:\gigi\apps\customdesk\res\vcpkg"
```

Classic mode defaults to `%VCPKG_ROOT%\installed\<triplet>`, which is already
the path `build.rs` wants. Keep `--overlay-ports` — RustDesk patches these ports,
and the stock vcpkg versions are not interchangeable. Versions still come from
the pinned vcpkg checkout, so they match the manifest baseline.

---

## 8. One-time repo prep: generate the Flutter ⇄ Rust bridge

**A clean clone cannot compile.** The `flutter_rust_bridge` glue is generated,
not committed — `src/bridge_generated.rs` and `src/bridge_generated.io.rs` are
gitignored by `.gitignore`, and `flutter/lib/generated_bridge.dart` /
`generated_bridge.freezed.dart` by `flutter/.gitignore`. `src/lib.rs` declares
`mod bridge_generated;` under the `flutter` feature, and three Dart models
import the generated bindings, so without this step Rust fails with a missing
module and Flutter fails with unresolved imports.

The generator version is not optional: `Cargo.toml` pins
`flutter_rust_bridge = "=1.80"`, so the codegen must be **1.80.1**.

```powershell
Set-Location C:\gigi\apps\customdesk

cargo install cargo-expand --version 1.0.95 --locked
cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid --locked

Set-Location .\flutter
flutter pub get
Set-Location ..

flutter_rust_bridge_codegen `
  --rust-input .\src\flutter_ffi.rs `
  --dart-output .\flutter\lib\generated_bridge.dart `
  --c-output .\flutter\macos\Runner\bridge_generated.h
```

The `--c-output` header is only consumed by the macOS/iOS builds, but the
generator expects the flag; the path exists in a fresh clone, so leave it as is.

Confirm all four files now exist:

```powershell
'src\bridge_generated.rs', 'src\bridge_generated.io.rs',
'flutter\lib\generated_bridge.dart', 'flutter\lib\generated_bridge.freezed.dart' |
  ForEach-Object { '{0,-46} {1}' -f $_, (Test-Path $_) }
```

**Fallback.** The generated files are platform-independent. If codegen misbehaves
on Windows, copy those four files from a machine that has already built this
branch (a Mac dev box, or the `bridge-artifact` from a
`.github/workflows/bridge.yml` run) into the same paths. Either way they stay
untracked — never commit them.

Re-run codegen whenever `src/flutter_ffi.rs` changes.

---

## 9. Verify the toolchain

```powershell
git --version
rustc --version; cargo --version; rustup target list --installed
flutter --version
Test-Path "$env:VCPKG_ROOT\vcpkg.exe"
Test-Path "$env:VCPKG_ROOT\installed\x64-windows-static\lib\vpx.lib"
Test-Path "$env:LIBCLANG_PATH\libclang.dll"
```

---

## 10. Build

```powershell
Set-Location C:\gigi\apps\customdesk

# Staging relay (the default — a bare invocation never ships pointed at production)
.\build-gigidesk-windows.ps1

# Production relay
.\build-gigidesk-windows.ps1 -Environment production
```

`-Environment` selects the `env_production` Cargo feature, which is what decides
the relay identity compiled into the binary — `RENDEZVOUS_SERVERS`, `RS_PUB_KEY`
and `GIGI_WS_DOMAIN` in `libs/hbb_common/src/config.rs`. There is no runtime
switch and no `.env`: **staging and production are different binaries.**

The script (see `BUILDSCRIPT_GUIDE.md` for detail) checks prerequisites, then:

1. `cargo build --features flutter[,env_production] --release --target x86_64-pc-windows-msvc`
2. copies `librustdesk.dll` into `target\release\`
3. wipes `flutter\build\windows` and runs `flutter build windows --release`
4. copies `librustdesk.dll` and `service.exe` into the Flutter Release folder
5. verifies the three expected artifacts exist
6. archives the folder to `..\desktop\bin\rustdesk-windows-<env>\` **and**
   `builds\<env>\windows\rustdesk-windows\`

Run it from a normal, unelevated PowerShell. If execution policy still blocks it:

```powershell
powershell -ExecutionPolicy Bypass -File .\build-gigidesk-windows.ps1
```

---

## 11. Check what you built

The Flutter runner's binary name is lowercase — `flutter/windows/CMakeLists.txt`
sets `BINARY_NAME "gigidesk"`, and the desktop app looks for exactly
`gigidesk.exe` (`src/services/rustdesk.service.js`,
`src/services/background-agent.service.js`). Cargo also produces its own
`target\...\release\gigidesk.exe`; that one is *not* what ships — the shipped
executable is the Flutter runner, with the Rust side arriving as
`librustdesk.dll`.

```powershell
Get-ChildItem ..\desktop\bin\rustdesk-windows-staging |
  Where-Object Name -in 'gigidesk.exe','librustdesk.dll','service.exe','flutter_windows.dll'
```

Confirm the relay that actually got compiled in — worth doing at least once per
environment, since a wrong-environment build looks completely normal:

```powershell
$dll = 'target\x86_64-pc-windows-msvc\release\librustdesk.dll'
# Read the expected host for this environment out of libs\hbb_common\src\config.rs
# (RENDEZVOUS_SERVERS). Don't paste relay addresses or keys into docs or tickets.
$expected = '<host from config.rs for the environment you just built>'
[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($dll)).Contains($expected)
```

`True` for the environment you asked for, and `False` for the other one, is the
result you want.

---

## 12. Next step — package the installer

Nothing ships GIGIdesk on its own. Build the engine first, then hand off to the
desktop repo, which stages the archive matching its own `GIGI_ENV` via
`scripts/select-gigidesk-build.js`:

```powershell
Set-Location C:\gigi\apps\desktop
npm ci
npm run build:win:staging      # or build:win:production / dist:staging / dist:production
```

If that fails with `No <env> RustDesk Windows build found`, the matching
`build-gigidesk-windows.ps1` run above hasn't happened yet. Full installer,
castLabs EVS and signing instructions:
[`../desktop/docs/windows-setup.md`](../desktop/docs/windows-setup.md).

---

## 13. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Could not locate desktop project directory` | The sibling `..\desktop\` (or `..\gigiChat-desktop\`) clone is missing — see §2 |
| `cargo` / `flutter` / `rustup` not found by the script | `PATH` was set after the shell opened. Open a new PowerShell |
| `VCPKG_ROOT not found at ...` | Set the machine variable to `C:\vcpkg` and reopen the shell. The script falls back to `%USERPROFILE%\vcpkg` |
| `Rust target x86_64-pc-windows-msvc not installed` | `rustup target add x86_64-pc-windows-msvc` |
| `Unable to find libclang` / bindgen panics | `LIBCLANG_PATH` unset or pointing somewhere without `libclang.dll` (§5) |
| `Couldn't find VCPKG_ROOT, also can't fallback to homebrew` | Same as above — `build.rs` only falls back to Homebrew on Apple Silicon |
| Link errors about `vpx` / `aom` / `yuv` / `opus`, or CRT mismatch (`LNK2038`) | Wrong vcpkg triplet. Must be `x64-windows-static`, installed under `%VCPKG_ROOT%\installed` (§7) |
| `cannot find module bridge_generated` / Dart can't resolve `generated_bridge.dart` | Bridge codegen not run (§8) |
| `cargo expand` complains it needs nightly | `rustup toolchain install nightly`, then re-run codegen |
| `cargo build` stalls with no output | A git dependency is waiting on a credential prompt (`git-fetch-with-cli = true`). Fix GitHub auth, or switch to HTTPS |
| `flutter pub get` fails on SDK constraints | Flutter older than 3.35 — see §6 |
| `flutter doctor` reports no Windows toolchain | Missing VS **Desktop development with C++** workload (§3) |
| Paths truncated / `filename too long` mid-build | Long-path support not enabled (§1) |
| `link.exe` out of memory on `librustdesk.dll` | Release profile uses `lto = true`, `codegen-units = 1`. Close other apps, or temporarily relax LTO in `Cargo.toml` for local iteration only |
| PowerShell refuses to run the `.ps1` | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`, or invoke with `-ExecutionPolicy Bypass` |

Upstream references:

- [RustDesk Windows build docs](https://rustdesk.com/docs/en/dev/build/windows/)
- [Flutter Windows setup](https://docs.flutter.dev/platform-integration/windows/setup)
- [vcpkg getting started](https://vcpkg.io/en/getting-started)
