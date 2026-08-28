# GIGIdesk — Packaging

How to build GIGIdesk (the bundled RustDesk engine) for each environment and
architecture. See `README.md` for prerequisites and the `env_production`
feature flag it controls.

## Commands

macOS (`build-gigidesk.sh <target> [environment]`):

| Command | Arch | Environment |
|---|---|---|
| `./build-gigidesk.sh intel` | Intel (x64) | staging (default) |
| `./build-gigidesk.sh arm64` | Apple Silicon | staging (default) |
| `./build-gigidesk.sh all` | both | staging (default) |
| `./build-gigidesk.sh intel staging` | Intel (x64) | staging |
| `./build-gigidesk.sh arm64 staging` | Apple Silicon | staging |
| `./build-gigidesk.sh intel production` | Intel (x64) | production |
| `./build-gigidesk.sh arm64 production` | Apple Silicon | production |

Windows (`build-gigidesk-windows.ps1 [-Environment <env>]`):

| Command | Environment |
|---|---|
| `.\build-gigidesk-windows.ps1` | staging (default) |
| `.\build-gigidesk-windows.ps1 -Environment staging` | staging |
| `.\build-gigidesk-windows.ps1 -Environment production` | production |

## Output

Every build is saved to **two places**, both archived by environment (and, on
macOS, architecture) so staging and production builds never overwrite each
other:

- `../desktop/bin/gigidesk-archive/GIGIdesk-<environment>-<arch>.app` /
  `../desktop/bin/rustdesk-windows-<environment>/` — read by desktop's build
  pipeline (see below).
- `builds/<environment>/mac/GIGIdesk-<arch>.app` /
  `builds/<environment>/windows/rustdesk-windows/` — a local copy kept in
  this repo. Not read by anything; just a backup, gitignored.

Both scripts print the exact path and size for each copy on success.

## Picked up by desktop automatically

You never copy these into place by hand. `apps/desktop`'s `make`/`build`/`dist`
scripts run `scripts/select-gigidesk-build.js` first, which copies the
`desktop/bin/gigidesk-archive/` (or `rustdesk-windows-<environment>/`) build
matching that command's `GIGI_ENV` into the fixed path Electron
Forge/electron-builder actually bundle. See `../desktop/PACKAGING.md`.

If the matching archive doesn't exist yet, that script fails with the exact
`build-gigidesk` command to run first — build the engine before packaging
desktop, not the other way around.

## Opening a built `.app` directly

Every archived copy shares the same bundle identity (`com.onethreshold.gigidesk`)
regardless of environment/arch — that's required so the real shipped app (which
only ever has one copy installed at a time, at a fixed path) has a stable
identity. A side effect: if you double-click more than one of these archived
`.app` copies directly (as opposed to going through the normal install flow),
macOS can't tell them apart by name and falls back to showing the raw folder
name in the Dock (e.g. "GIGIdesk-production-x64") instead of "GIGIdesk". This
only happens when manually opening files straight out of `gigidesk-archive/`
or `builds/` — the real installed copy at `/Applications/GIGIdesk.app` is
always the only one registered at a time and always shows cleanly.
