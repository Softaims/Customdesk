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

Every build is archived by environment (and, on macOS, architecture), so
running staging and production builds never overwrites the other:

- macOS: `../desktop/bin/gigidesk-archive/GIGIdesk-<environment>-<arch>.app`
- Windows: `../desktop/bin/rustdesk-windows-<environment>/`

Both scripts print the exact path and size on success.

## Picked up by desktop automatically

You never copy these into place by hand. `apps/desktop`'s `make`/`build`/`dist`
scripts run `scripts/select-gigidesk-build.js` first, which copies the archived
build matching that command's `GIGI_ENV` into the fixed path Electron
Forge/electron-builder actually bundle. See `../desktop/PACKAGING.md`.

If the matching archive doesn't exist yet, that script fails with the exact
`build-gigidesk` command to run first — build the engine before packaging
desktop, not the other way around.
