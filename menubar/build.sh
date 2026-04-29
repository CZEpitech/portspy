#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Portspy"
BIN_NAME="PortspyBar"
BUILD_CONFIG="release"
APP_DIR=".build/$APP_NAME.app"

echo "[portspybar] swift build ($BUILD_CONFIG, universal)"
swift build -c "$BUILD_CONFIG" --arch arm64 --arch x86_64

BIN_PATH="$(swift build -c $BUILD_CONFIG --arch arm64 --arch x86_64 --show-bin-path)/$BIN_NAME"

echo "[portspybar] wrap into $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$BIN_NAME"
cp Info.plist "$APP_DIR/Contents/Info.plist"

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "[portspybar] done -> $APP_DIR"
echo "[portspybar] launch with: open $APP_DIR"
