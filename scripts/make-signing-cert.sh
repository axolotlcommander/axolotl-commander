#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 The Axolotl Commander Authors
# Creates a self-signed code signing certificate for releases without an Apple Developer ID.
# Usage: scripts/make-signing-cert.sh [output-folder]   (default: ~/axolotl-signing)
#
# Releases signed with the same certificate keep the folder access users granted (Downloads,
# Documents, disks…) across updates. macOS still asks users to allow the app once per download
# (System Settings → Privacy & Security → Open Anyway), because the certificate is not from Apple.
#
# Keep the output folder private and backed up: a release signed with a different certificate
# makes every user grant folder access again. Never commit it.
set -eu
OUT="${1:-$HOME/axolotl-signing}"
NAME="Axolotl Commander Release Signing"
OPENSSL=/usr/bin/openssl   # LibreSSL: writes a .p12 that `security import` accepts
if [ -e "$OUT/signing.p12" ]; then
  echo "$OUT/signing.p12 already exists; refusing to replace it." >&2
  exit 1
fi
mkdir -p "$OUT"
chmod 700 "$OUT"
CONF="$OUT/openssl.cnf"
cat > "$CONF" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
PASSWORD="$("$OPENSSL" rand -base64 24)"
"$OPENSSL" req -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
  -keyout "$OUT/key.pem" -out "$OUT/cert.pem" -config "$CONF" 2>/dev/null
"$OPENSSL" pkcs12 -export -inkey "$OUT/key.pem" -in "$OUT/cert.pem" -name "$NAME" \
  -out "$OUT/signing.p12" -passout "pass:$PASSWORD"
rm "$OUT/key.pem" "$CONF"
printf '%s\n' "$PASSWORD" > "$OUT/password.txt"
base64 -i "$OUT/signing.p12" > "$OUT/signing.p12.base64"
chmod 600 "$OUT"/*
cat <<EOF
Created in $OUT:
  signing.p12         certificate and private key (keep it private, back it up)
  password.txt        its password
  signing.p12.base64  the same .p12 as base64, for the GitHub secret
  cert.pem            the certificate alone (public)

Add these repository secrets (Settings → Secrets and variables → Actions):
  MACOS_CERTIFICATE_P12       contents of signing.p12.base64
  MACOS_CERTIFICATE_PASSWORD  contents of password.txt
  MACOS_SIGNING_IDENTITY      $NAME
Leave the NOTARY_* secrets unset: notarization needs an Apple Developer ID.
EOF
