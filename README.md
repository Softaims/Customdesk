# GIGIdesk — the remote-desktop engine for GIGI

GIGIdesk is a customized fork of [RustDesk](https://github.com/rustdesk/rustdesk) — the open-source remote desktop tool written in Rust with a Flutter UI. In the GIGI suite it is the remote-control engine: GIGI Squad (the Electron desktop app) bundles, launches, and drives this binary so a caregiver can take remote control of an elder's computer to help them.

This is a fork, not a from-scratch project. Most of the codebase is upstream RustDesk; the GIGI-specific changes are listed below, and the original RustDesk license still applies (see [Upstream & license](#upstream--license)).

- Cargo package: `gigidesk` (`Cargo.toml`), version `1.4.5`, lib still named `librustdesk` for upstream compatibility.
- Active branch: `gigidesk-customUI` (upstream tracking branch: `master`).

## What's customized

Grounded in the fork's commit history and config:

- **Renamed/rebranded to GIGIdesk** — Cargo package `gigidesk`, bundle name `GIGIdesk`, identifier `com.softaims.gigidesk`, GIGI logos in the macOS tray, custom Windows resource metadata (`Cargo.toml`, `src/tray.rs`, `res/`).
- **Self-hosted rendezvous/relay server (the "EIP" server)** — points at a private GIGI-operated RustDesk server instead of the public RustDesk infrastructure. `get_relay_server()` in `src/rendezvous_mediator.rs` was changed to always use the configured server. See [Configuration](#configuration). (commits: "Rustdesk selfhosting configuration", "Configured custom server with EIP")
- **Vendored `hbb_common` into the repo** — the upstream git submodule was removed and the library is now committed directly under `libs/hbb_common/` (commit: "Vendor hbb_common into repo (remove submodule)"), so clones don't need `--recurse-submodules`.
- **GIGI build tooling** — added `build-gigidesk.sh` (macOS Intel/ARM64) and `build-gigidesk-windows.ps1`, plus fixes for build paths and Windows paths (commits: "fixed build path and build issues", "Windows path", "changed route of gigidesk outputs"). The mac build script writes the finished `.app` straight into the GIGI Squad desktop repo's `bin/`.
- **Custom UI / branding work** — GIGI icons, mac tray assets, mac setup, and permanent-password automation for the elder side (commits: "mac icons and setup", "macos setup", "mac builds and permanent password automation").

Everything else (protocol, codecs, screen capture, input simulation, Flutter UI scaffolding) is upstream RustDesk.

## How it fits into GIGI

- **GIGI Squad (`apps/desktop`)** builds GIGIdesk and bundles the resulting binary under its `bin/` directory. Its `make:intel` / `make:arm64` scripts select the GIGIdesk build via a `RUSTDESK_ARCH` switch (`x64` / `arm64`) and package it into the signed Electron app.
- On the **elder's** machine, GIGI Squad runs GIGIdesk in service mode (`gigidesk --server`) and auto-provisions a RustDesk ID + permanent password.
- When a **caregiver** starts a remote session, GIGI Squad launches the bundled GIGIdesk with the elder's credentials via CLI args (roughly `gigidesk --connect <id> <password> --password <password> --relay`) — the session goes through the self-hosted relay.
- The GIGI **backend (`apps/backend`)** records these sessions: `CallSession.callType = REMOTE_DESKTOP` (`apps/backend/prisma/schema.prisma`).

GIGIdesk does not handle GIGI's own signaling — it is the remote-control transport, orchestrated by GIGI Squad.

## Tech stack

- **Rust** core (edition 2021, rust-version 1.75) — protocol, services, platform integration.
- **Flutter** UI under `flutter/` (the legacy Sciter UI in `src/ui/` is deprecated upstream).
- Vendored upstream libs under `libs/`: `hbb_common` (codec/config/network/protobuf), `scrap` (screen capture), `enigo` (input simulation), `clipboard`, `virtual_display`, `remote_printer`.
- C/C++ deps via vcpkg: `libvpx`, `libyuv`, `opus`, `aom`.
- **Self-hosted RustDesk rendezvous/relay server** (no dependency on public RustDesk servers).

## Project structure

```
apps/customdesk/
├── src/                          Rust core
│   ├── server/                   audio / clipboard / input / video services + connections
│   ├── client.rs                 peer connection handling
│   ├── rendezvous_mediator.rs    relay/rendezvous logic (forces the GIGI self-hosted server)
│   ├── platform/                 platform-specific code (incl. privilege scripts)
│   ├── tray.rs                   system tray (GIGI branding)
│   └── ui/                       legacy Sciter UI (deprecated upstream)
├── flutter/                      Flutter UI for desktop + mobile (the modern UI)
├── libs/                         vendored core libraries
│   ├── hbb_common/               codec / config / network / protobuf — config.rs holds server constants
│   ├── scrap/                    screen capture
│   ├── enigo/                    keyboard / mouse input simulation
│   └── clipboard/                cross-platform clipboard
├── res/                          icons / branding / platform resources
├── build.py                      upstream RustDesk build orchestrator
├── build-gigidesk.sh             GIGI macOS build → outputs into ../desktop/bin/
├── build-gigidesk-windows.ps1    GIGI Windows build
├── Cargo.toml                    Rust package (`gigidesk`)
└── BUILDSCRIPT_GUIDE.md / GUIDE.md   build notes
```

`target/`, `flutter/build/`, and `builds/` are build output — ignore them.

## Getting started

```bash
git clone <this repo> apps/customdesk   # hbb_common is vendored — no --recurse-submodules needed
cd apps/customdesk
```

Install the toolchain — **Rust ≥ 1.75**, the **Flutter SDK**, and **vcpkg** with `VCPKG_ROOT` set (then install `libvpx`, `libyuv`, `opus`, `aom`). Full prerequisites and the cross-platform matrix are in [Building](#building). First local build (engine + Flutter UI):

```bash
python3 build.py --flutter --release    # or: cargo build --release  (engine only)
```

## Building

GIGIdesk uses the standard RustDesk build pipeline. For the full cross-platform build matrix and dependency setup, follow the upstream docs:

- RustDesk build docs: https://rustdesk.com/docs/en/dev/build/
- Upstream build script: `build.py` (kept from upstream).

**Prerequisites** (see upstream for full detail):

- Rust toolchain (>= 1.75) and the Flutter SDK.
- vcpkg with `VCPKG_ROOT` set; install `libvpx`, `libyuv`, `opus`, `aom`.
- Platform deps (per upstream): Windows needs extra DLLs + virtual display drivers; macOS needs signing/notarization; Linux needs the listed system libraries.

**GIGI-specific entry points:**

- `./build-gigidesk.sh intel | arm64 | all [staging|production]` — builds the macOS `.app` and archives it into **both** the GIGI Squad desktop repo's `bin/gigidesk-archive/` and this repo's own `builds/<environment>/mac/`, namespaced by environment+arch so staging and production builds never overwrite each other. The environment arg (default `staging`) picks which relay server gets compiled in — see [Configuration](#configuration) and `BUILDSCRIPT_GUIDE.md`.
- `build-gigidesk-windows.ps1 [-Environment staging|production]` — builds the Windows x64 release into **both** `bin/rustdesk-windows-<environment>/` and this repo's own `builds/<environment>/windows/`, same environment selection.
- The bundled macOS/Windows distributables are ultimately produced by **GIGI Squad's** `npm run make:staging:*` / `make:production:*` (macOS) or `build:win:staging` / `build:win:production` / `dist:staging` / `dist:production` (Windows), which automatically stage the matching archived GIGIdesk build before packaging — no manual copying or build-order to get right. Full command reference: **`PACKAGING.md`**.

Quick local check (engine only): `python3 build.py --flutter` (desktop) or `cargo build --release`. See `CLAUDE.md` and `GUIDE.md` for more.

## Deployment

GIGIdesk is **not distributed on its own** — it is built and bundled inside GIGI Squad, which is the installer that ships to end users:

```bash
# Staging
./build-gigidesk.sh all staging                  # macOS Intel + ARM64
cd ../desktop && npm run make:staging:arm64      # or make:staging:intel

# Production
./build-gigidesk.sh all production
cd ../desktop && npm run make:production:arm64   # or make:production:intel
```

`apps/desktop`'s `scripts/select-gigidesk-build.js` runs automatically as part of every make/build/dist script and stages the archived build matching that command's environment — if it isn't built yet, the script fails with the exact command to run. See `PACKAGING.md` for the full command matrix and output layout.

The self-hosted relay/rendezvous server GIGIdesk connects to is operated and deployed separately from this binary — see `docs/infra/production/rustdesk.md` (production current state), `docs/infra/rebuild-guidelines/rustdesk-rebuild.md` (build procedure, both environments), and `docs/rustdesk/README.md` (staging ops) in the meta-repo.

## Configuration

The self-hosted GIGI rendezvous/relay server (the "EIP" server) and its public key are compiled into the binary as constants in:

- **`libs/hbb_common/src/config.rs`** — `RENDEZVOUS_SERVERS` (the GIGI relay/rendezvous host) and `RS_PUB_KEY` (the server public key).
- **`src/rendezvous_mediator.rs`** — `get_relay_server()` forces use of the configured server rather than falling back to a server-provided or public address.

**Two environments, picked at compile time via a Cargo feature** — staging is the default (a plain `cargo build` never accidentally ships pointed at production):

```bash
cargo build --release --features flutter                    # staging (default)
cargo build --release --features flutter,env_production      # production
```

`config.rs` `#[cfg(feature = "env_production")]`-gates both constants to their production values; the `env_production` feature is defined in `libs/hbb_common/Cargo.toml` and forwarded through the top-level `Cargo.toml`. `build-gigidesk.sh`/`build-gigidesk-windows.ps1`'s environment argument sets this feature for you — most people should use those scripts rather than calling `cargo build` directly. Verified by inspecting the actual compiled artifact (not just that it builds) — each feature set embeds its own server address and no other.

The actual host/IP and key are intentionally **not reproduced here** — read them from `config.rs`. Do not commit production secrets to this README or anywhere public. Per-install overrides (custom rendezvous/relay server) are also supported through the standard RustDesk options handled in `config.rs`.

There is **no `.env` file** — GIGIdesk takes no *runtime* environment variables. Server identity is the compile-time constants above (environment-selected via the `env_production` feature), plus the standard RustDesk runtime options. The other environment variable involved is the build-time **`VCPKG_ROOT`** (see [Building](#building)).

## Part of the GIGI suite

GIGI is an elder-care remote-assistance and communication platform. The suite is five independent git repos under the `gigi-root/` workspace meta-repo — each app keeps its own `.git`, and `apps/` is gitignored by the meta-repo (these are **not** submodules).

- `apps/backend` — GIGI backend: NestJS + Prisma + PostgreSQL API and Socket.io signaling.
- `apps/desktop` — GIGI Squad: Electron desktop app for elders and caregivers; launches this engine for remote control.
- `apps/customdesk` — **GIGIdesk (this repo)**: the customized RustDesk remote-desktop engine.
- `apps/mobile` — GIGI SQUAD: Expo React Native mobile companion.
- `apps/landing` — gigi-landing: React + TypeScript + Vite landing and legal pages.

## Upstream & license

GIGIdesk is a **fork of RustDesk**: https://github.com/rustdesk/rustdesk — full credit to the RustDesk project and its contributors for the upstream remote-desktop engine, protocol, and Flutter UI that this fork builds on.

This repository inherits RustDesk's license: **GNU Affero General Public License v3.0 (AGPL-3.0)** — see the [`LICENCE`](./LICENCE) file in this repo. As an AGPL-3.0 work, the same terms (including the network-use source-availability obligations) apply to GIGIdesk and any distribution or networked deployment of it.
