#!/bin/bash
set -euo pipefail

CERTIFICATE_PATH="${CERTIFICATE_PATH:-${HOME}/keys/developer인증서.p12}"
PRIVATE_KEY_PATH="${PRIVATE_KEY_PATH:-${HOME}/keys/AuthKey_QJW24W7F76.p8}"
PROVISIONING_PROFILE_PATH="${PROVISIONING_PROFILE_PATH:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-4CL25TC734}"
APPSTORE_CONNECT_KEY_ID="${APPSTORE_CONNECT_KEY_ID:-QJW24W7F76}"
APPSTORE_CONNECT_ISSUER_ID="${APPSTORE_CONNECT_ISSUER_ID:-889a8253-618e-4e3a-84ff-73ac167fd81e}"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required: https://cli.github.com/" >&2
  exit 1
fi

if ! gh auth token >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated. Run: gh auth login -h github.com" >&2
  exit 1
fi

if [ ! -f "${CERTIFICATE_PATH}" ]; then
  echo "Developer ID certificate not found: ${CERTIFICATE_PATH}" >&2
  exit 1
fi

if [ ! -f "${PRIVATE_KEY_PATH}" ]; then
  echo "App Store Connect private key not found: ${PRIVATE_KEY_PATH}" >&2
  exit 1
fi

if [ -z "${DEVELOPER_ID_CERTIFICATE_PASSWORD:-}" ]; then
  read -r -s -p "Developer ID .p12 password: " DEVELOPER_ID_CERTIFICATE_PASSWORD
  echo ""
fi

base64 < "${CERTIFICATE_PATH}" | gh secret set DEVELOPER_ID_CERTIFICATE_P12_BASE64
printf "%s" "${DEVELOPER_ID_CERTIFICATE_PASSWORD}" | gh secret set DEVELOPER_ID_CERTIFICATE_PASSWORD
printf "%s" "${APPLE_TEAM_ID}" | gh secret set APPLE_TEAM_ID
printf "%s" "${APPSTORE_CONNECT_KEY_ID}" | gh secret set APPSTORE_CONNECT_KEY_ID
printf "%s" "${APPSTORE_CONNECT_ISSUER_ID}" | gh secret set APPSTORE_CONNECT_ISSUER_ID
base64 < "${PRIVATE_KEY_PATH}" | gh secret set APPSTORE_CONNECT_PRIVATE_KEY_BASE64

if [ -n "${PROVISIONING_PROFILE_PATH}" ]; then
  if [ ! -f "${PROVISIONING_PROFILE_PATH}" ]; then
    echo "Developer ID provisioning profile not found: ${PROVISIONING_PROFILE_PATH}" >&2
    exit 1
  fi
  base64 < "${PROVISIONING_PROFILE_PATH}" | gh secret set DEVELOPER_ID_PROVISIONING_PROFILE_BASE64
fi

echo "Release signing and notarization secrets are configured."
