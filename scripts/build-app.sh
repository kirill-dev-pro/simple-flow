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
if [ -f "${REPO_ROOT}/Packaging/AppIcon.icns" ]; then
    cp "${REPO_ROOT}/Packaging/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

echo "Signing SimpleFlow.app..."
CERT_NAME="SimpleFlow CodeSign"
if ! security find-identity -p codesigning | grep -q "${CERT_NAME}"; then
    echo "Creating persistent local signing certificate '${CERT_NAME}'..."
    TMP_DIR="$(mktemp -d)"
    cat <<EOF > "${TMP_DIR}/codesign.cnf"
[ req ]
default_bits        = 2048
distinguished_name  = req_distinguished_name
prompt              = no
x509_extensions     = v3_codesign

[ req_distinguished_name ]
CN = ${CERT_NAME}

[ v3_codesign ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:FALSE
EOF

    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
      -keyout "${TMP_DIR}/codesign.key" \
      -out "${TMP_DIR}/codesign.crt" \
      -config "${TMP_DIR}/codesign.cnf" 2>/dev/null

    openssl pkcs12 -export -out "${TMP_DIR}/codesign.p12" \
      -inkey "${TMP_DIR}/codesign.key" \
      -in "${TMP_DIR}/codesign.crt" \
      -password pass:simpleflow \
      -name "${CERT_NAME}" \
      -legacy 2>/dev/null

    security import "${TMP_DIR}/codesign.p12" -k ~/Library/Keychains/login.keychain-db -P simpleflow -A >/dev/null 2>&1 || true
    rm -rf "${TMP_DIR}"
fi

if security find-identity -p codesigning | grep -q "${CERT_NAME}"; then
    codesign --force --deep --sign "${CERT_NAME}" "${APP_BUNDLE}"
else
    codesign --force --sign - "${APP_BUNDLE}"
fi

echo "Built and signed: ${APP_BUNDLE}"
