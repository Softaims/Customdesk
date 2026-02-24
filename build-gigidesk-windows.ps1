#Requires -Version 5.1
<#
.SYNOPSIS
    Build GIGIdesk for Windows x64.

.DESCRIPTION
    build-gigidesk-windows.ps1 — Build GIGIdesk Windows x64 release.

    Compiles Rust (x86_64-pc-windows-msvc), builds Flutter for Windows,
    copies librustdesk.dll and service.exe into the Flutter output, then
    saves the finished build to desktop/assets/ and Customdesk/builds/.

.EXAMPLE
    .\build-gigidesk-windows.ps1

.NOTES
    Run from the Customdesk\ directory (or anywhere — the script resolves its
    own location automatically).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Configuration ───────────────────────────────────────────────────────────
$ScriptDir   = $PSScriptRoot
$FlutterDir  = Join-Path $ScriptDir 'flutter'
$OutputDir   = Join-Path $ScriptDir '..\gigiChat-desktop\bin'
$BuildsDir   = Join-Path $ScriptDir 'builds'

$RustTarget  = 'x86_64-pc-windows-msvc'
$AppName     = 'GIGIdesk'
$CargoFeatures = 'flutter'

# Flutter Windows release output (Flutter always builds x64 on Windows)
$FlutterRelease = Join-Path $FlutterDir 'build\windows\x64\runner\Release'

# ─── ANSI helpers ────────────────────────────────────────────────────────────
function Write-Info    { param([string]$Msg) Write-Host "  [i]  $Msg" -ForegroundColor Cyan }
function Write-Success { param([string]$Msg) Write-Host "  [+]  $Msg" -ForegroundColor Green }
function Write-Warn    { param([string]$Msg) Write-Host "  [!]  $Msg" -ForegroundColor Yellow }
function Write-Err     { param([string]$Msg) Write-Host "  [x]  $Msg" -ForegroundColor Red }
function Write-Step    { param([string]$Msg) Write-Host "`n--- $Msg ---" -ForegroundColor Magenta }
function Write-Banner  {
    param([string]$Msg)
    $line = '=' * ($Msg.Length + 6)
    Write-Host "`n$line" -ForegroundColor White
    Write-Host "   $Msg" -ForegroundColor White
    Write-Host "$line`n" -ForegroundColor White
}

function Format-Elapsed {
    param([double]$Seconds)
    "{0}m {1}s" -f [math]::Floor($Seconds / 60), ([math]::Floor($Seconds % 60))
}

# ─── Prerequisite Check ─────────────────────────────────────────────────────
function Invoke-CheckPrerequisites {
    Write-Step 'Checking prerequisites'
    $missing = $false

    foreach ($cmd in @('cargo', 'flutter', 'rustup')) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) {
            Write-Info "$cmd -> $($found.Source)"
        } else {
            Write-Err "$cmd not found in PATH"
            $missing = $true
        }
    }

    # Check VCPKG_ROOT
    $vcpkgRoot = $env:VCPKG_ROOT
    if (-not $vcpkgRoot) {
        $vcpkgRoot = Join-Path $env:USERPROFILE 'vcpkg'
    }
    if (Test-Path $vcpkgRoot) {
        Write-Info "VCPKG_ROOT -> $vcpkgRoot"
        $env:VCPKG_ROOT = $vcpkgRoot
    } else {
        Write-Err "VCPKG_ROOT not found at $vcpkgRoot (set the VCPKG_ROOT environment variable)"
        $missing = $true
    }

    # Check Rust target
    $installedTargets = & rustup target list --installed 2>&1
    if ($installedTargets -match [regex]::Escape($RustTarget)) {
        Write-Info "Rust target $RustTarget is installed"
    } else {
        Write-Err "Rust target $RustTarget not installed — run: rustup target add $RustTarget"
        $missing = $true
    }

    if ($missing) {
        Write-Err 'Missing prerequisites. Aborting.'
        exit 1
    }
    Write-Success 'All prerequisites satisfied'
}

# ─── Build Rust ──────────────────────────────────────────────────────────────
function Invoke-BuildRust {
    Write-Step "Building Rust ($RustTarget)"
    Push-Location $ScriptDir
    try {
        Write-Info "cargo build --features $CargoFeatures --release --target $RustTarget"
        & cargo build --features $CargoFeatures --release --target $RustTarget
        if ($LASTEXITCODE -ne 0) { throw "cargo build failed (exit $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
    Write-Success "Rust build complete"
}

# ─── Copy DLL ────────────────────────────────────────────────────────────────
function Copy-Dll {
    Write-Step 'Copying librustdesk.dll -> target\release\'
    Push-Location $ScriptDir
    try {
        $srcDll = "target\$RustTarget\release\librustdesk.dll"
        if (-not (Test-Path $srcDll)) {
            throw "DLL not found: $srcDll"
        }

        $destDir = 'target\release'
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }

        Copy-Item -Path $srcDll -Destination "$destDir\librustdesk.dll" -Force
        Write-Info "Copied to target\release\librustdesk.dll"
    } finally {
        Pop-Location
    }
    Write-Success 'DLL copied'
}

# ─── Build Flutter ───────────────────────────────────────────────────────────
function Invoke-BuildFlutter {
    Write-Step 'Building Flutter Windows (x64 Release)'
    Push-Location $FlutterDir
    try {
        # Clean previous build
        if (Test-Path 'build\windows') {
            Write-Info 'Cleaning previous Flutter Windows build...'
            Remove-Item -Recurse -Force 'build\windows'
        }

        Write-Info 'flutter build windows --release'
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit $LASTEXITCODE)" }

        if (-not (Test-Path $FlutterRelease)) {
            throw "Flutter build output not found at: $FlutterRelease"
        }
    } finally {
        Pop-Location
    }
    Write-Success 'Flutter build complete'
}

# ─── Copy DLL into Flutter output ────────────────────────────────────────────
function Copy-DllToFlutterOutput {
    Write-Step 'Copying librustdesk.dll -> Flutter release output'
    $srcDll = Join-Path $ScriptDir "target\$RustTarget\release\librustdesk.dll"

    if (-not (Test-Path $srcDll)) {
        throw "DLL not found: $srcDll"
    }

    Copy-Item -Path $srcDll -Destination (Join-Path $FlutterRelease 'librustdesk.dll') -Force
    Write-Success 'librustdesk.dll copied into Flutter output'
}

# ─── Copy service.exe into Flutter output ────────────────────────────────────
function Copy-ServiceBinary {
    Write-Step 'Copying service.exe -> Flutter release output'
    $srcService = Join-Path $ScriptDir "target\$RustTarget\release\service.exe"

    if (-not (Test-Path $srcService)) {
        throw "service.exe not found: $srcService"
    }

    Copy-Item -Path $srcService -Destination (Join-Path $FlutterRelease 'service.exe') -Force
    Write-Success 'service.exe copied into Flutter output'
}

# ─── Verify build output ─────────────────────────────────────────────────────
function Invoke-Verify {
    Write-Step 'Verifying build output'
    $ok = $true

    $checks = @(
        (Join-Path $FlutterRelease "$AppName.exe"),
        (Join-Path $FlutterRelease 'librustdesk.dll'),
        (Join-Path $FlutterRelease 'service.exe')
    )

    foreach ($f in $checks) {
        if (Test-Path $f) {
            $sizeKB = [math]::Round((Get-Item $f).Length / 1KB, 1)
            Write-Info "$(Split-Path $f -Leaf) -> ${sizeKB} KB"
        } else {
            Write-Err "Missing: $f"
            $ok = $false
        }
    }

    if (-not $ok) { throw 'Verification failed — one or more output files are missing.' }
    Write-Success 'All output files verified'
}

# ─── Save build output ───────────────────────────────────────────────────────
function Save-BuildOutput {
    Write-Step 'Saving build output'

    $label      = 'x64'
    $destName   = "$AppName-$label"

    # 1) desktop/assets  — embedded into Electron app
    $destDesktop = Join-Path $OutputDir $destName
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
    if (Test-Path $destDesktop) { Remove-Item -Recurse -Force $destDesktop }
    Copy-Item -Recurse -Path $FlutterRelease -Destination $destDesktop
    $sizeMB = [math]::Round((Get-ChildItem $destDesktop -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
    Write-Success "$destName -> gigiChat-desktop\assets\ (${sizeMB} MB)"

    # 2) Customdesk/builds  — local backup
    if (-not (Test-Path $BuildsDir)) { New-Item -ItemType Directory -Path $BuildsDir -Force | Out-Null }
    $destBuilds = Join-Path $BuildsDir $destName
    if (Test-Path $destBuilds) { Remove-Item -Recurse -Force $destBuilds }
    Copy-Item -Recurse -Path $FlutterRelease -Destination $destBuilds
    Write-Success "$destName -> builds\ (backup)"
}

# ─── Main ────────────────────────────────────────────────────────────────────
function Main {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Banner "Building $AppName for Windows x64"

    Invoke-CheckPrerequisites

    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    Invoke-BuildRust
    Copy-Dll
    Invoke-BuildFlutter
    Copy-DllToFlutterOutput
    Copy-ServiceBinary
    Invoke-Verify
    Save-BuildOutput

    $sw.Stop()
    $elapsed = $sw.Elapsed.TotalSeconds

    Write-Host ''
    Write-Banner "Build complete in $(Format-Elapsed $elapsed)"

    Write-Host 'Output:' -ForegroundColor White
    $outFolder = Join-Path $OutputDir "$AppName-x64"
    if (Test-Path $outFolder) {
        Get-ChildItem $outFolder -File | Select-Object Name, @{N='Size';E={ "$([math]::Round($_.Length/1KB,1)) KB" }} |
            Format-Table -AutoSize
    }
}

Main
