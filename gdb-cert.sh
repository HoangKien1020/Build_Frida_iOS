#!/bin/bash

CERT="frida-cert"
TMPDIR=$(mktemp -d)

error() {
    echo error: "$@" 1>&2
    exit 1
}

cleanup() {
    rm -f "$TMPDIR/$CERT.tmpl" "$TMPDIR/$CERT.cer" "$TMPDIR/$CERT.key"
}

trap cleanup EXIT

cat <<EOF >"$TMPDIR/$CERT.tmpl"
[ req ]
default_bits       = 2048
encrypt_key        = no
default_md         = sha512
prompt             = no
distinguished_name = codesign_dn
[ codesign_dn ]
commonName         = "$CERT"
[ codesign_reqext ]
keyUsage           = critical,digitalSignature
extendedKeyUsage   = critical,codeSigning
EOF

echo Generating and installing gdb_codesign certificate

openssl req -new -newkey rsa:2048 -x509 -days 3650 -nodes -config "$TMPDIR/$CERT.tmpl" -extensions codesign_reqext -batch -out "$TMPDIR/$CERT.cer" -keyout "$TMPDIR/$CERT.key" || error "Something went wrong when generating the certificate"

sudo security authorizationdb read com.apple.trust-settings.admin > "$TMPDIR/rights"
sudo security authorizationdb write com.apple.trust-settings.admin allow
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$TMPDIR/$CERT.cer" || error "Something went wrong when installing the certificate"
sudo security authorizationdb write com.apple.trust-settings.admin < "$TMPDIR/rights"

sudo security import "$TMPDIR/$CERT.key" -A -k /Library/Keychains/System.keychain || error "Something went wrong when installing the key"
sudo pkill -f /usr/libexec/taskgated

sleep 5

echo "Checking available identities again after a short delay"
security find-identity -v -p codesigning

CERTID=$(security find-identity -v -p codesigning | grep "$CERT" | awk '{ print $2 }')
echo "MACOS_CERTID=$CERTID" >> $GITHUB_ENV
echo "IOS_CERTID=$CERTID" >> $GITHUB_ENV

exit 0
