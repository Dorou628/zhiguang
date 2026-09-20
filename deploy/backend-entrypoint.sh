#!/bin/sh
set -eu
umask 077
mkdir -p /app/keys
if [ ! -s /app/keys/private.pem ]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out /app/keys/private.pem.tmp 2>/dev/null
  mv /app/keys/private.pem.tmp /app/keys/private.pem
fi
# Derive the public key from the persistent private key on each start.
openssl pkey -in /app/keys/private.pem -pubout -out /app/keys/public.pem.tmp 2>/dev/null
mv /app/keys/public.pem.tmp /app/keys/public.pem
exec java -jar /app/app.jar
