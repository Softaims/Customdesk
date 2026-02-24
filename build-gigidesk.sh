#!/usr/bin/env bash
#
# build-gigidesk.sh — Build GIGIdesk .app for Intel and/or ARM64
#
# Usage:
#   ./build-gigidesk.sh intel        # Build x86_64 only
#   ./build-gigidesk.sh arm64        # Build arm64 only
#   ./build-gigidesk.sh all          # Build both (Intel first, then ARM64)
#
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLUTTER_DIR="$SCRIPT_DIR/flutter"
XCCONFIG="$FLUTTER_DIR/macos/Flutter/CustomArch.xcconfig"
OUTPUT_DIR="$SCRIPT_DIR/../desktop/assets"
BUILDS_DIR="$SCRIPT_DIR/builds"

MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.14}"
VCPKG_ROOT="${VCPKG_ROOT:-$HOME/vcpkg}"
export MACOSX_DEPLOYMENT_TARGET VCPKG_ROOT

APP_NAME="GIGIdesk"
CARGO_FEATURES="flutter"

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ─── Helpers ─────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}ℹ${NC}  $*"; }
success() { echo -e "${GREEN}✅${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠️${NC}  $*"; }
error()   { echo -e "${RED}❌${NC} $*" >&2; }
step()    { echo -e "\n${CYAN}${BOLD}━━━ $* ━━━${NC}"; }
banner()  { echo -e "\n${BOLD}╔══════════════════════════════════════════════╗\n║  $*\n╚══════════════════════════════════════════════╝${NC}\n"; }

elapsed() {
  local secs=$1
  printf '%dm %ds' $((secs / 60)) $((secs % 60))
}

# ─── Prerequisite Check ─────────────────────────────────────────────────────
check_prerequisites() {
  step "Checking prerequisites"
  local missing=0

  for cmd in cargo flutter pod file; do
    if command -v "$cmd" &>/dev/null; then
      info "$cmd → $(command -v "$cmd")"
    else
      error "$cmd not found in PATH"
      missing=1
    fi
  done

  if [[ ! -d "$VCPKG_ROOT" ]]; then
    error "VCPKG_ROOT not found at $VCPKG_ROOT"
    missing=1
  else
    info "VCPKG_ROOT → $VCPKG_ROOT"
  fi

  # Check Rust targets
  if ! rustup target list --installed | grep -q "x86_64-apple-darwin"; then
    warn "x86_64-apple-darwin target not installed — run: rustup target add x86_64-apple-darwin"
    missing=1
  fi
  if ! rustup target list --installed | grep -q "aarch64-apple-darwin"; then
    warn "aarch64-apple-darwin target not installed — run: rustup target add aarch64-apple-darwin"
    missing=1
  fi

  if [[ $missing -ne 0 ]]; then
    error "Missing prerequisites. Aborting."
    exit 1
  fi
  success "All prerequisites satisfied"
}

# ─── Set Architecture in xcconfig ────────────────────────────────────────────
set_arch_xcconfig() {
  local arch="$1"
  local excluded

  if [[ "$arch" == "x86_64" ]]; then
    excluded="arm64"
  else
    excluded="x86_64"
  fi

  cat > "$XCCONFIG" <<EOF
ARCHS = $arch
EXCLUDED_ARCHS = $excluded
EOF
  info "CustomArch.xcconfig → ARCHS=$arch  EXCLUDED_ARCHS=$excluded"
}

# ─── Build Rust ──────────────────────────────────────────────────────────────
build_rust() {
  local arch="$1"
  step "Building Rust ($arch)"

  cd "$SCRIPT_DIR"

  local target_flag=""
  if [[ "$arch" == "x86_64" ]]; then
    target_flag="--target x86_64-apple-darwin"
  else
    target_flag="--target aarch64-apple-darwin"
  fi

  info "cargo build --features $CARGO_FEATURES --release $target_flag"
  cargo build --features "$CARGO_FEATURES" --release $target_flag

  success "Rust build complete ($arch)"
}

# ─── Copy dylib ──────────────────────────────────────────────────────────────
copy_dylib() {
  local arch="$1"
  step "Copying dylib ($arch)"

  cd "$SCRIPT_DIR"

  local src_dir
  if [[ "$arch" == "x86_64" ]]; then
    src_dir="target/x86_64-apple-darwin/release"
  else
    src_dir="target/aarch64-apple-darwin/release"
  fi

  cp "$src_dir/liblibrustdesk.dylib" "target/release/librustdesk.dylib"
  cp "$src_dir/liblibrustdesk.dylib" "target/release/liblibrustdesk.dylib"

  local actual_arch
  actual_arch=$(file "target/release/librustdesk.dylib" | grep -o 'x86_64\|arm64')
  info "librustdesk.dylib → $actual_arch"

  if [[ "$arch" == "x86_64" && "$actual_arch" != "x86_64" ]] || \
     [[ "$arch" == "arm64" && "$actual_arch" != "arm64" ]]; then
    error "Architecture mismatch! Expected $arch but got $actual_arch"
    exit 1
  fi

  success "dylib copied and verified"
}

# ─── CocoaPods ───────────────────────────────────────────────────────────────
reinstall_pods() {
  step "Reinstalling CocoaPods"
  cd "$FLUTTER_DIR/macos"
  rm -rf Pods Podfile.lock
  pod install
  success "CocoaPods installed"
}

# ─── Build Flutter ───────────────────────────────────────────────────────────
build_flutter() {
  local arch="$1"
  step "Building Flutter macOS ($arch)"

  cd "$FLUTTER_DIR"

  # Clean previous build & DerivedData
  rm -rf build/macos
  rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*

  flutter build macos --release

  local app_path="build/macos/Build/Products/Release/$APP_NAME.app"
  if [[ ! -d "$app_path" ]]; then
    error "Flutter build failed — $APP_NAME.app not found"
    exit 1
  fi

  success "Flutter build complete"
}

# ─── Copy service binary ────────────────────────────────────────────────────
copy_service() {
  local arch="$1"
  step "Copying service binary ($arch)"

  cd "$SCRIPT_DIR"

  local src_dir
  if [[ "$arch" == "x86_64" ]]; then
    src_dir="target/x86_64-apple-darwin/release"
  else
    src_dir="target/aarch64-apple-darwin/release"
  fi

  local app_macos="$FLUTTER_DIR/build/macos/Build/Products/Release/$APP_NAME.app/Contents/MacOS"
  cp -rf "$src_dir/service" "$app_macos/"

  success "Service binary copied"
}

# ─── Verify architectures ───────────────────────────────────────────────────
verify_app() {
  local arch="$1"
  step "Verifying $APP_NAME.app ($arch)"

  local app_macos="$FLUTTER_DIR/build/macos/Build/Products/Release/$APP_NAME.app/Contents/MacOS"
  local expected
  [[ "$arch" == "x86_64" ]] && expected="x86_64" || expected="arm64"

  local main_arch service_arch
  main_arch=$(file "$app_macos/$APP_NAME" | grep -o 'x86_64\|arm64')
  service_arch=$(file "$app_macos/service" | grep -o 'x86_64\|arm64')

  info "$APP_NAME binary → $main_arch"
  info "service binary   → $service_arch"

  if [[ "$main_arch" != "$expected" ]]; then
    error "$APP_NAME binary is $main_arch, expected $expected"
    exit 1
  fi
  if [[ "$service_arch" != "$expected" ]]; then
    error "service binary is $service_arch, expected $expected"
    exit 1
  fi

  success "All binaries verified as $expected"
}

# ─── Save .app ───────────────────────────────────────────────────────────────
save_app() {
  local arch="$1"
  step "Saving $APP_NAME.app"

  local label
  [[ "$arch" == "x86_64" ]] && label="x64" || label="arm64"

  local src="$FLUTTER_DIR/build/macos/Build/Products/Release/$APP_NAME.app"

  # 1) Save to desktop/assets (embedded into Electron app)
  local dest_desktop="$OUTPUT_DIR/$APP_NAME-$label.app"
  rm -rf "$dest_desktop"
  cp -R "$src" "$dest_desktop"
  local size
  size=$(du -sh "$dest_desktop" | cut -f1)
  success "$APP_NAME-$label.app → desktop/assets/ ($size)"

  # 2) Save to Customdesk/builds (secure backup in this repo)
  mkdir -p "$BUILDS_DIR"
  local dest_builds="$BUILDS_DIR/$APP_NAME-$label.app"
  rm -rf "$dest_builds"
  cp -R "$src" "$dest_builds"
  success "$APP_NAME-$label.app → builds/ (backup)"
}

# ─── Full build pipeline for one architecture ───────────────────────────────
build_arch() {
  local arch="$1"
  local start_time=$SECONDS

  banner "Building $APP_NAME for $arch"

  set_arch_xcconfig "$arch"
  build_rust "$arch"
  copy_dylib "$arch"
  reinstall_pods
  build_flutter "$arch"
  copy_service "$arch"
  verify_app "$arch"
  save_app "$arch"

  local duration=$(( SECONDS - start_time ))
  success "🎉 $arch build finished in $(elapsed $duration)"
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
  local target="${1:-}"

  if [[ -z "$target" ]]; then
    echo "Usage: $0 <intel|arm64|all>"
    echo ""
    echo "  intel   Build x86_64 (Intel Mac) .app"
    echo "  arm64   Build aarch64 (Apple Silicon) .app"
    echo "  all     Build both architectures"
    exit 1
  fi

  local total_start=$SECONDS

  check_prerequisites
  mkdir -p "$OUTPUT_DIR"

  case "$target" in
    intel|x64|x86_64)
      build_arch "x86_64"
      ;;
    arm64|aarch64|arm)
      build_arch "arm64"
      ;;
    all|both)
      build_arch "x86_64"
      build_arch "arm64"
      ;;
    *)
      error "Unknown target: $target"
      echo "Valid targets: intel, arm64, all"
      exit 1
      ;;
  esac

  local total_duration=$(( SECONDS - total_start ))

  echo ""
  banner "Build complete in $(elapsed $total_duration)"

  echo -e "${BOLD}Output:${NC}"
  ls -lh "$OUTPUT_DIR"/$APP_NAME-*.app/Contents/MacOS/$APP_NAME 2>/dev/null | \
    awk '{print "  " $NF " (" $5 ")"}'
  echo ""
}

main "$@"
