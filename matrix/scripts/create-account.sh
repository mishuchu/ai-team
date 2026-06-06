#!/bin/bash
# Matrix Account Creation Script
# Automates user registration via Dendrite Admin API

set -e

# Configuration
MATRIX_SERVER="${MATRIX_SERVER:-http://localhost:8008}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS}"
SHARED_SECRET="${SHARED_SECRET}"
NEW_USER="${1}"
NEW_PASS="${2}"

if [ -z "$NEW_USER" ] || [ -z "$NEW_PASS" ]; then
    echo "Usage: $0 <username> <password>"
    exit 1
fi

# Get nonce
echo "[*] Getting registration nonce..."
NONCE=$(curl -s -X GET "${MATRIX_SERVER}/_synapse/admin/v1/register" | python3 -c "import sys, json; print(json.load(sys.stdin)['nonce'])")

# Generate MAC (HMAC-SHA1)
echo "[*] Generating MAC..."
CONTENT=$(printf '%s\0%s\0%s\0notadmin' "$NONCE" "$NEW_USER" "$NEW_PASS")
MAC=$(printf '%s' "$CONTENT" | openssl sha1 -hmac "$SHARED_SECRET" | awk '{print $2}')

# Create account
echo "[*] Creating user @${NEW_USER}:matrix-homeserver..."
RESPONSE=$(curl -s -X POST "${MATRIX_SERVER}/_synapse/admin/v1/register" \
    -H "Content-Type: application/json" \
    -d "{\"nonce\":\"${NONCE}\",\"username\":\"${NEW_USER}\",\"password\":\"${NEW_PASS}\",\"admin\":false,\"mac\":\"${MAC}\"}")

echo "[*] Response:"
echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"

# Extract access token if needed
ACCESS_TOKEN=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token', 'N/A'))" 2>/dev/null)
echo "[*] Access token: ${ACCESS_TOKEN:0:20}..."