#!/usr/bin/env bash
# Builds LuaJIT for macOS arm64 and merges it into Libluajit-5.1.xcframework.
# Upstream libmpv v0.0.1-beta only ships macos-x86_64 for LuaJIT.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XCFW="$ROOT/Packages/MPVKitVendor/Frameworks/Libluajit-5.1.xcframework"
OLD_SLICE="$XCFW/macos-x86_64"
NEW_SLICE="$XCFW/macos-arm64_x86_64"
LUAJIT_VERSION="v2.1"
LUAJIT_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kinema-luajit-arm64.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ ! -d "$XCFW" ]]; then
  echo "Missing $XCFW — run Scripts/download_mpv_frameworks.sh first." >&2
  exit 1
fi

if [[ -d "$NEW_SLICE" ]]; then
  if lipo -info "$NEW_SLICE/libluajit-5.1.a" 2>/dev/null | grep -q arm64; then
    echo "Libluajit macOS slice already includes arm64."
    exit 0
  fi
fi

if [[ ! -d "$OLD_SLICE" && ! -d "$NEW_SLICE" ]]; then
  echo "No macOS LuaJIT slice found in $XCFW." >&2
  exit 1
fi

SOURCE_SLICE="${OLD_SLICE}"
if [[ ! -d "$SOURCE_SLICE" ]]; then
  SOURCE_SLICE="$NEW_SLICE"
fi

echo "Building LuaJIT $LUAJIT_VERSION for macOS arm64..."
git clone --depth 1 --branch "$LUAJIT_VERSION" https://github.com/LuaJIT/LuaJIT.git "$WORK_DIR/LuaJIT"
(
  cd "$WORK_DIR/LuaJIT"
  make clean >/dev/null 2>&1 || true
  make -j"$(sysctl -n hw.ncpu)" CC="clang -arch arm64" MACOSX_DEPLOYMENT_TARGET="$LUAJIT_DEPLOYMENT_TARGET"
)

ARM64_LIB="$WORK_DIR/LuaJIT/src/libluajit.a"
if ! lipo -info "$ARM64_LIB" | grep -q arm64; then
  echo "LuaJIT build did not produce an arm64 library." >&2
  exit 1
fi

echo "Merging macOS x86_64 + arm64 LuaJIT slices..."
rm -rf "$NEW_SLICE"
cp -R "$SOURCE_SLICE" "$NEW_SLICE"
lipo -create \
  "$SOURCE_SLICE/libluajit-5.1.a" \
  "$ARM64_LIB" \
  -output "$NEW_SLICE/libluajit-5.1.a"

if [[ "$SOURCE_SLICE" != "$NEW_SLICE" ]]; then
  rm -rf "$OLD_SLICE"
fi

python3 <<PY
import plistlib
from pathlib import Path

path = Path("$XCFW") / "Info.plist"
with path.open("rb") as fh:
    data = plistlib.load(fh)

updated = False
for lib in data.get("AvailableLibraries", []):
    if lib.get("SupportedPlatform") != "macos":
        continue
    lib["LibraryIdentifier"] = "macos-arm64_x86_64"
    lib["SupportedArchitectures"] = ["arm64", "x86_64"]
    updated = True

if not updated:
    raise SystemExit("No macOS library entry found in Libluajit Info.plist")

with path.open("wb") as fh:
    plistlib.dump(data, fh)
PY

lipo -info "$NEW_SLICE/libluajit-5.1.a"
echo "Patched $XCFW with macOS arm64 + x86_64 LuaJIT."
