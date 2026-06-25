#!/usr/bin/env bash
# Build libchromaprint 1.6.0 as a universal static xcframework for macOS (arm64 + x86_64).
# Run once from the EchoCore/vendor directory; commit the resulting xcframework.
# Requires: cmake, curl, tar (all standard or brew-installable).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.6.0"
SRC_DIR="chromaprint-${VERSION}"
TARBALL="${SRC_DIR}.tar.gz"
XCFW="Chromaprint.xcframework"

if [ -d "$XCFW" ]; then
  echo "✅  $XCFW already exists — delete it to rebuild."
  exit 0
fi

# Download source
if [ ! -f "$TARBALL" ]; then
  curl -L -o "$TARBALL" \
    "https://github.com/acoustid/chromaprint/archive/refs/tags/v${VERSION}.tar.gz"
fi

tar -xzf "$TARBALL"

# Build universal static lib using bundled KissFFT (no FFTW / AVFoundation FFT dep)
cmake -S "$SRC_DIR" -B "build-universal" \
  -DBUILD_TOOLS=OFF \
  -DBUILD_SHARED_LIBS=OFF \
  -DFFT_LIB=kissfft \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="15.0" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="-fvisibility=hidden" \
  -DCMAKE_CXX_FLAGS="-fvisibility=hidden"
cmake --build "build-universal" --target chromaprint -j"$(sysctl -n hw.logicalcpu)"

# Assemble xcframework with universal (arm64 + x86_64) slice
SLICE_ID="macos-arm64_x86_64"
HEADERS_DIR="${XCFW}/${SLICE_ID}/Headers"
mkdir -p "$HEADERS_DIR"
cp "build-universal/src/libchromaprint.a" "${XCFW}/${SLICE_ID}/libchromaprint.a"
cp "${SRC_DIR}/src/chromaprint.h"         "${HEADERS_DIR}/chromaprint.h"

cat > "${HEADERS_DIR}/module.modulemap" <<'MAP'
module CChromaprint {
    header "chromaprint.h"
    export *
}
MAP

cat > "${XCFW}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>AvailableLibraries</key>
  <array>
    <dict>
      <key>HeadersPath</key>
      <string>Headers</string>
      <key>LibraryIdentifier</key>
      <string>macos-arm64_x86_64</string>
      <key>LibraryPath</key>
      <string>libchromaprint.a</string>
      <key>SupportedArchitectures</key>
      <array>
        <string>arm64</string>
        <string>x86_64</string>
      </array>
      <key>SupportedPlatform</key>
      <string>macos</string>
    </dict>
  </array>
  <key>CFBundlePackageType</key>
  <string>XFWK</string>
  <key>XCFrameworkFormatVersion</key>
  <string>1.0</string>
</dict>
</plist>
PLIST

echo "✅  Built ${XCFW} (universal: arm64 + x86_64)"
echo "   Commit the vendor/ directory to the repo."
