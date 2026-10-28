#!/bin/zsh
# Creates a self-signed code-signing identity, "MacMinion Local", once. build.sh signs with it, so
# every build keeps the same designated requirement and macOS remembers permissions such as
# Documents access across builds (ad hoc builds are new apps to macOS every time).
#   tools/make-signing-identity.sh              into your login keychain
#   KEYCHAIN=<file> tools/make-signing-identity.sh   into another keychain (tests)
# Safe to run again: it does nothing when the identity is already there.
set -euo pipefail
name="MacMinion Local"
keychain="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if security find-identity -p codesigning "$keychain" 2>/dev/null | grep -q "\"$name\""; then
  echo "already there: \"$name\" in $keychain"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cat > "$work/cert.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$work/cert.cnf" \
  -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
pass=$(openssl rand -hex 16)
# The Security framework reads only the older PKCS#12 encryption.
openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -name "$name" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -passout "pass:$pass" -out "$work/id.p12"
# -T lets codesign use the key without asking each time.
security import "$work/id.p12" -k "$keychain" -P "$pass" -T /usr/bin/codesign >/dev/null
echo "created \"$name\" in $keychain"
echo "next: ./build.sh, then allow Documents access once more; later builds keep it."
