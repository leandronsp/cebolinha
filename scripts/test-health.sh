#!/bin/bash

echo "=== Testing Payment Processor Health Endpoints ==="
echo

echo "Checking Default Processor Health (port 8001)..."
echo "GET /payments/service-health"
curl -X GET http://localhost:8001/payments/service-health

echo -e "\n\n"

echo "Checking Fallback Processor Health (port 8002)..."
echo "GET /payments/service-health"
curl -X GET http://localhost:8002/payments/service-health

echo -e "\n\n"
echo "=== Health check completed ==="