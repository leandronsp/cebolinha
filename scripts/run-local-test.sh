#!/usr/bin/env bash

# Run the official Rinha test locally with proper scoring

echo "🐦 Starting local Rinha test..."

# Clean up any previous results
rm -f partial-results.json k6.logs docker-compose.logs error.logs

# Wait for backend to be ready
echo "Waiting for backend to be ready..."
success=1
max_attempts=15
attempt=1
while [ $success -ne 0 ] && [ $max_attempts -ge $attempt ]; do
    curl -f -s http://localhost:9999/payments-summary > /dev/null
    success=$?
    echo "Health check attempt $attempt of $max_attempts..."
    sleep 2
    ((attempt++))
done

if [ $success -eq 0 ]; then
    echo "Backend is ready! Starting k6 test..."
    
    # Run the official k6 test with 550 requests
    MAX_REQUESTS=550
    PARTICIPANT="ovelha"
    TOKEN=$(uuidgen)
    
    k6 run -e MAX_REQUESTS=$MAX_REQUESTS -e PARTICIPANT=$PARTICIPANT -e TOKEN=$TOKEN rinha-test/rinha.js
    
    # Display results
    if [ -f partial-results.json ]; then
        echo ""
        echo "=== RESULTADOS DA RINHA ==="
        echo ""
        cat partial-results.json | jq -r '
            "Participante: " + .participante,
            "P99: " + .p99.valor,
            "Bônus por desempenho: " + (.p99.bonus * 100 | tostring) + "%",
            "",
            "Multa:",
            "  - Porcentagem: " + (.multa.porcentagem * 100 | tostring) + "%",
            "  - Total: $" + (.multa.total | tostring),
            "  - Inconsistências: " + (.multa.composicao.total_inconsistencias | tostring),
            "",
            "Pagamentos:",
            "  - Default: " + (.pagamentos_realizados_default.num_pagamentos | tostring) + " ($" + (.pagamentos_realizados_default.total_bruto | tostring) + ")",
            "  - Fallback: " + (.pagamentos_realizados_fallback.num_pagamentos | tostring) + " ($" + (.pagamentos_realizados_fallback.total_bruto | tostring) + ")",
            "",
            "Total Bruto: $" + (.total_bruto | tostring),
            "Total Taxas: $" + (.total_taxas | tostring),
            "",
            "=============================",
            "LUCRO FINAL: $" + (.total_liquido | tostring),
            "============================="
        '
        
        # Save a summary
        echo ""
        echo "Full results saved to partial-results.json"
    else
        echo "Error: No results file generated"
    fi
else
    echo "Backend failed to respond after $max_attempts attempts"
    echo "[$(date)] Backend não respondeu após $max_attempts tentativas" > error.logs
fi

echo "Test complete!"
