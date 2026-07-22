#!/usr/bin/env bash
# Downloads MPVKit binary xcframeworks into Packages/MPVKitVendor/Frameworks/.
# Skips frameworks that already exist as valid local directories.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAMEWORKS_DIR="$ROOT/Packages/MPVKitVendor/Frameworks"
BASE_URL="https://github.com/karelrooted/libmpv/releases/download/v0.0.1-beta"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mpv-frameworks.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$FRAMEWORKS_DIR"

is_valid_framework() {
  local dir="$1"
  [[ -d "$dir" && ! -L "$dir" && -f "$dir/Info.plist" ]] || return 1
  find "$dir" \( -name '*.framework' -o -name '*.a' \) -print -quit | grep -q .
}

flatten_xcframework() {
  local dir="$1"
  if [[ -f "$dir/Info.plist" ]]; then
    return 0
  fi
  local inner
  inner="$(find "$dir" -mindepth 1 -maxdepth 1 -name '*.xcframework' -print -quit)"
  if [[ -z "$inner" ]]; then
    echo "no Info.plist or nested xcframework in $dir" >&2
    return 1
  fi
  local tmp="${dir}.flattening"
  rm -rf "$tmp"
  mv "$inner" "$tmp"
  rm -rf "$dir"
  mv "$tmp" "$dir"
}

fix_shallow_macos_framework() {
  local fw="$1"
  local name
  name="$(basename "$fw" .framework)"

  if [[ -d "$fw/Versions" || ! -f "$fw/Info.plist" ]]; then
    return 0
  fi

  echo "version $fw"
  (
    cd "$fw"
    mkdir -p Versions/A/Resources
    for item in Headers Modules PrivateHeaders "$name"; do
      if [[ -e "$item" ]]; then
        mv "$item" Versions/A/
      fi
    done
    mv Info.plist Versions/A/Resources/
    ln -sf A Versions/Current
    for item in Headers Modules PrivateHeaders "$name"; do
      if [[ -e "Versions/A/$item" ]]; then
        ln -sf "Versions/Current/$item" "$item"
      fi
    done
    ln -sf Versions/Current/Resources Resources
  )
}

fix_all_macos_frameworks() {
  find "$FRAMEWORKS_DIR" -path '*/macos-*/*.framework' -print | while read -r fw; do
    fix_shallow_macos_framework "$fw"
  done
}

# zip_name|sha256|dest_dir_name
FRAMEWORKS=(
  "Libass.xcframework.zip|f854fd3da12111c34ddc6129fcbaec2f3dfc03b3d0f26227412b2c251ae15824|Libass.xcframework"
  "Libavcodec.xcframework.zip|e6e4a406894da67cf2daf884f640cf80385457b5aa39cf89cd196d93acefdac4|Libavcodec.xcframework"
  "Libavdevice.xcframework.zip|aa056fe7c7ed78bb29c3b4d86df5c085486b8395405ead293336f5c648e62b27|Libavdevice.xcframework"
  "Libavfilter.xcframework.zip|820c916ef48609607fa4dd7c5d8008d6ea9a76c8dc08f804e8a964dd2c2e3e8b|Libavfilter.xcframework"
  "Libavformat.xcframework.zip|91f48ed37f7360ea1fa83d09d1e26cb156b74192b5de2b9417a115aad9d7e1dd|Libavformat.xcframework"
  "Libavutil.xcframework.zip|94faef320167b059fe438aa998ef3d138b078e3adf6f6fff57791fc3e9902191|Libavutil.xcframework"
  "Libbluray.xcframework.zip|f6e1055e4907cc5fac718302a9a39038c8dc0137ab9f8787b43cd87736909601|Libbluray.xcframework"
  "Libcrypto.xcframework.zip|af4795290f4d1c83546d7a6c4ddfa74d7cc0352f16096ca7ba1b49f3eac8bf10|Libcrypto.xcframework"
  "Libdav1d.xcframework.zip|91a447147c25477ec6f84d26f0e35245bcb6a9aa47e348f988d4f66fe8d8e6ad|Libdav1d.xcframework"
  "Libdovi.xcframework.zip|68b09f68af5ea8c0c1c5ee8e5143064e2bf8d9f849854505b7eb6082252bdeb0|Libdovi.xcframework"
  "Libeffcee.xcframework.zip|d8b4c9673f5d0530ea8240ec235915cba6bffe72bf553ef454fe6a5f3bfd0826|Libeffcee.xcframework"
  "Libfreetype.xcframework.zip|e1f32bbd569fc29b7bc15bb1e2a13698444f4233450d6e33d3a897829ab3cfe1|Libfreetype.xcframework"
  "Libfribidi.xcframework.zip|393c928cac7c895c3da328eb58cd2030d7ec47936be38972c4359260dcaebb3c|Libfribidi.xcframework"
  "Libglslang.xcframework.zip|7d7843df4099313350d3e0aadf7f8f024d1b026f5b3d29362b442ff708204ec4|Libglslang.xcframework"
  "Libgmp.xcframework.zip|fd15de28241de7af2d5940926bf2888ed6c812922773cdc67fda5be6088eafab|Libgmp.xcframework"
  "Libgnutls.xcframework.zip|2ef4a1fa9af4940ea4aff19ec8bd2d072a8db56dc537f7ee4017de13da6c2d7f|Libgnutls.xcframework"
  "Libharfbuzz.xcframework.zip|9e85337f12224632f8d519bace2565b03958f5fbcdd73da691b9ff41d94d57bd|Libharfbuzz.xcframework"
  "Libhogweed.xcframework.zip|2e03033324786b8eeefb20e5f4edbe249e2dad142e24bd62f1ff0af23977739b|Libhogweed.xcframework"
  "Liblcms2.xcframework.zip|764ba49fb9dbfd300cc83fe74ee9090edec6d0cce2c9bd679b2a80b592d471df|Liblcms2.xcframework"
  "Libluajit-5.1.xcframework.zip|0eae84fc010b1730581f942a883389f29862f9e7911301a7065d4f363b25c6ac|Libluajit-5.1.xcframework"
  "Libmpv.xcframework.zip|169dca1c5d19e4749b5f0e7a889d3bc1cbb2b180902c761585de87063ff55a4a|Libmpv.xcframework"
  "Libnettle.xcframework.zip|03810283d4750a57b006c237cfb1e68caadc9a6304716af62ec4e24b33a01627|Libnettle.xcframework"
  "Libnfs.xcframework.zip|0f7bd725190226ab8ebaf0c053f3b8289f8609c217fb4ffcff8245af0e2cf361|Libnfs.xcframework"
  "Libplacebo.xcframework.zip|751b20844a64cdba660ee8f49c316a6a27ab40a4c277350a8f33ce9086f5b707|Libplacebo.xcframework"
  "Libpng.xcframework.zip|218220d82b3028041a0f11c033bbd32dbdf742f10c3d4b77a76f31f479eefd97|Libpng.xcframework"
  "Libreadline.xcframework.zip|4325cd6b78455ecf35eab505063afea6bd4ed3b1c3cb6ae2ffc92632855d4347|Libreadline.xcframework"
  "Libshaderc_combined.xcframework.zip|bcaf0d034c7b5d56209ad5ba36c08349a4c3bcf9807ff42734592b4c2b0cefa7|Libshaderc_combined.xcframework"
  "Libsmbclient.xcframework.zip|7d28045335067ec6d72f294fe34b5a8069bc1e122d970e8f5d7a59a1fe8df957|Libsmbclient.xcframework"
  "Libssl.xcframework.zip|0815b270f6740e8c4b4e4ba0093ebbe05b7f8c9dee8b5655af83fb70a8af2272|Libssl.xcframework"
  "Libswresample.xcframework.zip|715f05f1bf368588a75d3f5ef2d906f58fa8d31d9a9158f5af69962046aaf43f|Libswresample.xcframework"
  "Libswscale.xcframework.zip|11db9fb6e176b58007d1b46e4a5dc537933f91585b0080996870cd686b928bd4|Libswscale.xcframework"
  "Libuchardet.xcframework.zip|8da536a83136d2e5a859e72755a74a44b84db4cca7714153c305d2c5853e3633|Libuchardet.xcframework"
  "MoltenVK.xcframework.zip|846b1b8a4b86a55cd11c81686f5f7928779ba0f1e3f2c933320375b4588fca04|MoltenVK.xcframework"
)

download_one() {
  local zip_name="$1"
  local checksum="$2"
  local dest_name="$3"
  local dest_path="$FRAMEWORKS_DIR/$dest_name"

  if is_valid_framework "$dest_path"; then
    echo "skip  $dest_name (already present)"
    return 0
  fi

  echo "fetch $dest_name"
  local zip_path="$TMP_DIR/$zip_name"
  curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 \
    -o "$zip_path" "$BASE_URL/$zip_name"

  local actual
  actual="$(shasum -a 256 "$zip_path" | awk '{print $1}')"
  if [[ "$actual" != "$checksum" ]]; then
    echo "checksum mismatch for $zip_name" >&2
    echo "  expected: $checksum" >&2
    echo "  actual:   $actual" >&2
    return 1
  fi

  local extract_dir="$TMP_DIR/extract-${dest_name}"
  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  unzip -q "$zip_path" -d "$extract_dir"

  local extracted
  extracted="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -name '*.xcframework' -print -quit)"
  if [[ -z "$extracted" ]]; then
    echo "no xcframework found in $zip_name" >&2
    return 1
  fi

  rm -rf "$dest_path"
  mv "$extracted" "$dest_path"
  flatten_xcframework "$dest_path"

  if ! is_valid_framework "$dest_path"; then
    echo "extracted $dest_name is not a valid xcframework" >&2
    return 1
  fi

  echo "done  $dest_name"
}

failed=0
for entry in "${FRAMEWORKS[@]}"; do
  IFS='|' read -r zip checksum dest <<< "$entry"
  if ! download_one "$zip" "$checksum" "$dest"; then
    failed=1
  fi
done

echo
if [[ "$failed" -ne 0 ]]; then
  echo "Some frameworks failed to download." >&2
  exit 1
fi

echo "All MPVKit frameworks are present in $FRAMEWORKS_DIR"
fix_all_macos_frameworks
"$ROOT/Scripts/patch_luajit_macos_arm64.sh"
echo "Next: reopen Kinema.xcodeproj and resolve packages (File → Packages → Reset Package Caches if needed)."
