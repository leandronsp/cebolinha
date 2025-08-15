#!/bin/bash

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
