#!/bin/bash

echo "=== Testing Pru API POST /purge-payments via nginx (localhost:9999) ==="
echo

echo "Testing POST /purge-payments..."
curl -X POST http://localhost:9999/purge-payments

echo -e "\n\n=== Purge test completed ==="