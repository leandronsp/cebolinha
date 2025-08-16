package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/redis/go-redis/v9"
)

// PaymentJob represents a payment job from Redis
type PaymentJob struct {
	CorrelationID string  `json:"correlationId"`
	Amount        float64 `json:"amount"`
	RetryCount    int     `json:"_retry_count,omitempty"`
}

// ProcessorPayload represents the payload sent to payment processors
type ProcessorPayload struct {
	CorrelationID string  `json:"correlationId"`
	Amount        float64 `json:"amount"`
	RequestedAt   string  `json:"requestedAt"`
}

func Process(ctx context.Context, job PaymentJob, store *Store, redisClient *redis.Client, cfg *Config) {
	correlationID := job.CorrelationID
	amount := job.Amount
	requestedAt := time.Now().UTC().Format(time.RFC3339)

	// Try default processor
	if tryProcessor(ctx, "default", correlationID, amount, requestedAt, time.Duration(cfg.DefaultTimeoutMs)*time.Millisecond) {
		store.Save(ctx, correlationID, "default", amount, requestedAt)
		return
	}

	// Try fallback processor
	if tryProcessor(ctx, "fallback", correlationID, amount, requestedAt, time.Duration(cfg.FallbackTimeoutMs)*time.Millisecond) {
		store.Save(ctx, correlationID, "fallback", amount, requestedAt)
	}
}

func tryProcessor(ctx context.Context, processorName, correlationID string, amount float64, requestedAt string, timeout time.Duration) bool {
	payload := ProcessorPayload{
		CorrelationID: correlationID,
		Amount:        amount,
		RequestedAt:   requestedAt,
	}

	payloadJSON, _ := json.Marshal(payload)
	client := &http.Client{Timeout: timeout}
	endpoint := fmt.Sprintf("http://payment-processor-%s:8080/payments", processorName)
	
	req, _ := http.NewRequestWithContext(ctx, "POST", endpoint, bytes.NewBuffer(payloadJSON))
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()

	return resp.StatusCode >= 200 && resp.StatusCode < 300
}
