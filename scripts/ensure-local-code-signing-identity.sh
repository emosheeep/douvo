#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="${DOUVO_LOCAL_CODESIGN_IDENTITY:-Douvo Local Code Signing}"
LOCAL_CODESIGN_DIR="${DOUVO_LOCAL_CODESIGN_DIR:-$HOME/Library/Application Support/Douvo/CodeSigning}"
KEYCHAIN="${CODESIGN_KEYCHAIN:-${DOUVO_CODESIGN_KEYCHAIN:-$LOCAL_CODESIGN_DIR/douvo-local-code-signing.keychain-db}}"
KEYCHAIN_PASSWORD_FILE="${DOUVO_LOCAL_CODESIGN_PASSWORD_FILE:-$LOCAL_CODESIGN_DIR/keychain-password}"
DAYS="${DOUVO_LOCAL_CODESIGN_DAYS:-3650}"

if [[ -z "$IDENTITY_NAME" || "$IDENTITY_NAME" == *"/"* || "$IDENTITY_NAME" == *$'\n'* ]]; then
  echo "error: invalid local code-signing identity name" >&2
  exit 1
fi

find_identity_hash() {
  security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null \
    | awk -v name="$IDENTITY_NAME" 'index($0, "\"" name "\"") { print $2; exit }'
}

if [[ ! -f "$KEYCHAIN" ]]; then
  mkdir -p "$(dirname "$KEYCHAIN")"
  chmod 700 "$(dirname "$KEYCHAIN")"
  KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"
  umask 077
  printf '%s\n' "$KEYCHAIN_PASSWORD" >"$KEYCHAIN_PASSWORD_FILE"
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
else
  if [[ ! -f "$KEYCHAIN_PASSWORD_FILE" ]]; then
    IDENTITY_HASH="$(find_identity_hash)"
    if [[ -n "$IDENTITY_HASH" ]]; then
      printf '%s\n' "$IDENTITY_HASH"
      exit 0
    fi
    echo "error: keychain exists but password file is missing: $KEYCHAIN_PASSWORD_FILE" >&2
    echo "Set CODESIGN_KEYCHAIN to an unlocked keychain or remove the stale local signing keychain." >&2
    exit 1
  fi
  KEYCHAIN_PASSWORD="$(<"$KEYCHAIN_PASSWORD_FILE")"
fi

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"

IDENTITY_HASH="$(find_identity_hash)"
if [[ -n "$IDENTITY_HASH" ]]; then
  printf '%s\n' "$IDENTITY_HASH"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

KEY="$TMP_DIR/key.pem"
CERT="$TMP_DIR/cert.pem"
P12="$TMP_DIR/identity.p12"
P12_PASSWORD="$(openssl rand -hex 24)"
PKCS12_ARGS=()

if openssl pkcs12 -help 2>&1 | grep -q -- "-legacy"; then
  PKCS12_ARGS+=(-legacy)
fi

echo "Creating local code-signing identity '$IDENTITY_NAME' in dedicated keychain $KEYCHAIN" >&2

openssl req \
  -newkey rsa:2048 \
  -nodes \
  -keyout "$KEY" \
  -x509 \
  -sha256 \
  -days "$DAYS" \
  -out "$CERT" \
  -subj "/CN=$IDENTITY_NAME" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,digitalSignature,keyCertSign" \
  -addext "extendedKeyUsage=codeSigning" >/dev/null 2>&1

openssl pkcs12 \
  "${PKCS12_ARGS[@]}" \
  -export \
  -inkey "$KEY" \
  -in "$CERT" \
  -name "$IDENTITY_NAME" \
  -out "$P12" \
  -passout "pass:$P12_PASSWORD" >/dev/null 2>&1

security import "$P12" \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null

security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN" >/dev/null 2>&1

security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$CERT" >/dev/null

IDENTITY_HASH="$(find_identity_hash)"
if [[ -z "$IDENTITY_HASH" ]]; then
  echo "error: created identity was not accepted by macOS code-signing policy" >&2
  exit 1
fi

printf '%s\n' "$IDENTITY_HASH"
