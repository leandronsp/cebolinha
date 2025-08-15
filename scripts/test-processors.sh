#!/bin/bash

echo "=== Testing Payment Processors ==="
echo

# Generate UUID and timestamp for requests
uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

echo "Testing Default Processor (port 8001)..."
echo "POST /payments"
curl -X POST \
  -H "Content-Type: application/json" \
  -d "{
    \"correlationId\": \"$uuid\",
    \"amount\": 10.50,
    \"requestedAt\": \"$timestamp\"
  }" \
  http://localhost:8001/payments

echo -e "\n\n"

# Generate new UUID for fallback test
uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

echo "Testing Fallback Processor (port 8002)..."
echo "POST /payments"
curl -X POST \
  -H "Content-Type: application/json" \
  -d "{
    \"correlationId\": \"$uuid\",
    \"amount\": 25.75,
    \"requestedAt\": \"$timestamp\"
  }" \
  http://localhost:8002/payments

echo -e "\n\n"

echo "Getting Default Processor Summary..."
echo "GET /admin/payments-summary"
curl -X GET \
  -H "X-Rinha-Token: 123" \
  http://localhost:8001/admin/payments-summary

echo -e "\n\n"

echo "Getting Fallback Processor Summary..."
echo "GET /admin/payments-summary"
curl -X GET \
  -H "X-Rinha-Token: 123" \
  http://localhost:8002/admin/payments-summary

echo -e "\n\n"
echo "=== Test completed ==="