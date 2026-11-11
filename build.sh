#!/usr/bin/env bash
# Builds 小鱼干打工记.app. With --install, also replaces the copy in /Applications and opens it.
# Your records live in ~/Library/Application Support/XiaoYuGan and are never touched by this script.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="小鱼干打工记"
EXECUTABLE="XiaoYuGan"
OUT="build/${APP_NAME}.app"
INSTALLED="/Applications/${APP_NAME}.app"

echo "[1/4] Building (release)..."
swift build -c release
BIN="$(swift build -c release --show-bin-path)/${EXECUTABLE}"

echo "[2/4] Making the icon..."
if [ ! -f Resources/AppIcon.icns ]; then
    mkdir -p build
    rm -rf build/AppIcon.iconset
    swift tools/make_icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi

echo "[3/4] Assembling ${OUT}..."
rm -rf "${OUT}"
mkdir -p "${OUT}/Contents/MacOS" "${OUT}/Contents/Resources"
cp "${BIN}" "${OUT}/Contents/MacOS/${EXECUTABLE}"
cp Resources/Info.plist "${OUT}/Contents/Info.plist"
cp Resources/index.html Resources/AppIcon.icns "${OUT}/Contents/Resources/"
codesign --force --deep --sign - "${OUT}"

if [ "${1:-}" = "--install" ]; then
    echo "[4/4] Installing to ${INSTALLED}..."
    pkill -x "${EXECUTABLE}" 2>/dev/null || true
    sleep 1
    rm -rf "${INSTALLED}"
    ditto "${OUT}" "${INSTALLED}"
    open "${INSTALLED}"
    echo "Installed and opened ${INSTALLED}"
else
    echo "[4/4] Built ${OUT} (run ./build.sh --install to install it)"
fi
