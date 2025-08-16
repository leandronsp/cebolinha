package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
)

// PaymentJob represents a payment job from Redis
type PaymentJob struct {
	CorrelationID string  `json:"correlationId"`
	Amount        float64 `json:"amount"`
	RequestedAt   string  `json:"requestedAt,omitempty"` // Timestamp from API
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
	requestedAt := job.RequestedAt

	// Try default processor
	if tryProcessor(ctx, "default", correlationID, amount, requestedAt, time.Duration(cfg.DefaultTimeoutMs)*time.Millisecond) {
		store.Save(ctx, correlationID, "default", amount, requestedAt)
		return
	}

	// Try fallback processor
	if tryProcessor(ctx, "fallback", correlationID, amount, requestedAt, time.Duration(cfg.FallbackTimeoutMs)*time.Millisecond) {
		store.Save(ctx, correlationID, "fallback", amount, requestedAt)
		return
	}

	// Both processors failed - retry logic
	if job.RetryCount < cfg.MaxRetries {
		job.RetryCount++
		requeueJob(ctx, job, redisClient)
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

func requeueJob(ctx context.Context, job PaymentJob, redisClient *redis.Client) error {
	// Marshal job back to JSON
	jobJSON, err := json.Marshal(job)
	if err != nil {
		return err
	}
	
	// Create message in same format as API: body;timestamp
	message := fmt.Sprintf("%s;%s", string(jobJSON), job.RequestedAt)
	
	// Republish to same "payments" channel
	return redisClient.Publish(ctx, "payments", message).Err()
}
