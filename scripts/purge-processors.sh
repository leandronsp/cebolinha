#!/bin/bash

echo "=== Purging Payment Processors Data ==="
echo

echo "Purging Default Processor (port 8001)..."
echo "POST /admin/purge-payments"
curl -X POST \
  -H "X-Rinha-Token: 123" \
  http://localhost:8001/admin/purge-payments

echo -e "\n\n"

echo "Purging Fallback Processor (port 8002)..."
echo "POST /admin/purge-payments"
curl -X POST \
  -H "X-Rinha-Token: 123" \
  http://localhost:8002/admin/purge-payments

echo -e "\n\n"
echo "=== Purge completed ==="