#!/bin/bash

echo "=== Testing Pru API POST /payments via nginx (localhost:9999) ==="
echo

# Generate UUID and timestamp for request
uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

echo "Testing POST /payments..."
echo "Payload: correlationId=$uuid, amount=42.50"
curl -X POST \
  -H "Content-Type: application/json" \
  -d "{
    \"correlationId\": \"$uuid\",
    \"amount\": 42.50,
    \"requestedAt\": \"$timestamp\"
  }" \
  http://localhost:9999/payments

echo -e "\n\n=== Test completed ==="