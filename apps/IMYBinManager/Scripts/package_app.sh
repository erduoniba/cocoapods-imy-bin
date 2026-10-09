#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="${PROJECT_DIR}/.build/IMYBinManager.app"
CONTENTS_DIR="${APP_DIR}/Contents"

rm -rf "${APP_DIR}"
mkdir -p "${CONTENTS_DIR}/MacOS" "${CONTENTS_DIR}/Resources"
cp "${BIN_DIR}/IMYBinManager" "${CONTENTS_DIR}/MacOS/IMYBinManager"

PLIST="${CONTENTS_DIR}/Info.plist"
plutil -create xml1 "${PLIST}"
plutil -insert CFBundleExecutable -string IMYBinManager "${PLIST}"
plutil -insert CFBundleIdentifier -string com.imy.bin-manager "${PLIST}"
plutil -insert CFBundleName -string IMYBinManager "${PLIST}"
plutil -insert CFBundleDisplayName -string "IMY Bin Manager" "${PLIST}"
plutil -insert CFBundlePackageType -string APPL "${PLIST}"
plutil -insert CFBundleShortVersionString -string 0.1.0 "${PLIST}"
plutil -insert CFBundleVersion -string 1 "${PLIST}"
plutil -insert LSMinimumSystemVersion -string 13.0 "${PLIST}"
plutil -insert NSHighResolutionCapable -bool true "${PLIST}"

codesign --force --deep --sign - "${APP_DIR}"
codesign --verify --deep --strict "${APP_DIR}"

echo "Created ${APP_DIR}"
