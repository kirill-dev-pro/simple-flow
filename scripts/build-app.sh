#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

CONFIGURATION="${1:-debug}"
case "${CONFIGURATION}" in
    debug|Debug)
        SWIFT_BUILD_CONFIG="debug"
        ;;
    release|Release)
        SWIFT_BUILD_CONFIG="release"
        ;;
    *)
        echo "Usage: $0 [debug|release]" >&2
        exit 1
        ;;
esac

echo "Building SimpleFlow (${SWIFT_BUILD_CONFIG})..."
swift build -c "${SWIFT_BUILD_CONFIG}"

BIN_DIR="$(swift build -c "${SWIFT_BUILD_CONFIG}" --show-bin-path)"
EXECUTABLE="${BIN_DIR}/SimpleFlow"
APP_BUNDLE="${REPO_ROOT}/.build/SimpleFlow.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${EXECUTABLE}" "${MACOS_DIR}/SimpleFlow"
cp "${REPO_ROOT}/Packaging/Info.plist" "${CONTENTS_DIR}/Info.plist"

echo "Signing SimpleFlow.app..."
codesign --force --sign - "${APP_BUNDLE}"

echo "Built and signed: ${APP_BUNDLE}"
