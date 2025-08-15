#!/bin/bash

echo "=== Testing Pru API GET /payments-summary via nginx (localhost:9999) ==="
echo

echo "Testing GET /payments-summary..."
curl -X GET http://localhost:9999/payments-summary

echo -e "\n\n=== Test completed ==="