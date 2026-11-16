#!/bin/zsh
# Creates a self-signed code-signing identity in the login keychain so that
# macOS privacy grants (Accessibility, Screen Recording) survive rebuilds.
# The key is non-extractable and no app is pre-authorized to use it, so every
# signing asks for approval (choose "Allow", never "Always Allow"); otherwise any
# local process could sign code that inherits tabSS's privacy grants.
set -euo pipefail

name="${1:?usage: create-signing-cert.sh <certificate name>}"
keychain="$HOME/Library/Keychains/login.keychain-db"
openssl=/usr/bin/openssl  # system LibreSSL; its PKCS#12 output is importable by `security`
security=/usr/bin/security

identities="$("$security" find-identity -p codesigning "$keychain")"
if [[ "$identities" == *"\"$name\""* ]]; then
    echo "Code-signing identity '$name' already exists."
    exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
trap 'exit 1' INT TERM HUP

# Throwaway password protecting the transient key files; passed via fd, not argv.
password="$("$openssl" rand -hex 24)"
exec 3<<<"$password" 4<<<"$password" 5<<<"$password"

cat > "$work/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

"$openssl" req -x509 -newkey rsa:3072 -days 3650 -config "$work/cert.cnf" \
    -keyout "$work/key.pem" -passout fd:3 -out "$work/cert.pem"

"$openssl" pkcs12 -export -inkey "$work/key.pem" -passin fd:4 -in "$work/cert.pem" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -name "$name" -out "$work/identity.p12" -passout fd:5

# -T "" trusts no app (not even `security` itself). -P briefly exposes the throwaway password in argv;
# the alternative is a GUI prompt for a password nobody knows.
"$security" import "$work/identity.p12" -k "$keychain" -P "$password" -x -T ""
echo "Created code-signing identity '$name'."
