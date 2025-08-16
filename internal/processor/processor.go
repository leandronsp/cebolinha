package processor

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/leandronsp/cebolinha/internal/config"
	"github.com/leandronsp/cebolinha/internal/store"
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

// Process handles a payment job with retry logic and fallback
func Process(ctx context.Context, job PaymentJob, store *store.Store, redisClient *redis.Client, cfg *config.Config) {
	fmt.Printf("🧅 Received from Redis: %s\n", mustMarshal(job))

	correlationID := job.CorrelationID
	amount := job.Amount

	// Always generate timestamp in worker (ASM API doesn't include timestamps)
	requestedAt := time.Now().UTC().Format(time.RFC3339)
	requestedAt = requestedAt[:len(requestedAt)-1] + "Z" // Ensure Z suffix for consistency

	fmt.Printf("🧅 Parsed: correlationId='%s', amount=%g, requestedAt='%s'\n", 
		correlationID, amount, requestedAt)

	// Only check is_processed for retried payments to avoid latency on first attempts
	if job.RetryCount > 0 && store.IsProcessed(ctx, correlationID) {
		fmt.Printf("🧅 Payment %s already processed (retry %d), skipping\n", 
			correlationID, job.RetryCount)
		return
	}

	// Try default processor with retries
	for attempt := 0; attempt < cfg.MaxAttempts; attempt++ {
		if tryProcessor(ctx, "default", correlationID, amount, requestedAt, 
			time.Duration(cfg.DefaultTimeoutMs)*time.Millisecond) {
			
			// Atomic save - returns true if saved, false if already existed
			saved, err := store.Save(ctx, correlationID, "default", amount, requestedAt)
			if err != nil {
				fmt.Printf("🧅 Error saving payment %s: %v\n", correlationID, err)
			} else if saved {
				fmt.Printf("🧅 Payment %s processed by default (attempt %d)\n", 
					correlationID, attempt+1)
			} else {
				fmt.Printf("🧅 Payment %s already saved by another worker\n", correlationID)
			}
			return
		}

		// Backoff before retry (except on last attempt)
		if attempt < cfg.MaxAttempts-1 {
			sleepMs := time.Duration(cfg.BackoffSleepMs*(attempt+1)) * time.Millisecond
			time.Sleep(sleepMs)
		}
	}

	// Try fallback processor
	if tryProcessor(ctx, "fallback", correlationID, amount, requestedAt, 
		time.Duration(cfg.FallbackTimeoutMs)*time.Millisecond) {
		
		// Atomic save - returns true if saved, false if already existed
		saved, err := store.Save(ctx, correlationID, "fallback", amount, requestedAt)
		if err != nil {
			fmt.Printf("🧅 Error saving payment %s: %v\n", correlationID, err)
		} else if saved {
			fmt.Printf("🧅 Payment %s processed by fallback\n", correlationID)
		} else {
			fmt.Printf("🧅 Payment %s already saved by another worker\n", correlationID)
		}
		return
	}

	// Both processors failed - retry by re-publishing to channel
	if job.RetryCount < cfg.MaxRetries {
		fmt.Printf("🧅 Both processors failed for %s - retrying (%d/%d)\n", 
			correlationID, job.RetryCount+1, cfg.MaxRetries)

		// Increment retry count and republish
		retryJob := job
		retryJob.RetryCount++
		
		retryPayload, _ := json.Marshal(retryJob)
		err := redisClient.Publish(ctx, "payments", string(retryPayload)).Err()
		if err != nil {
			fmt.Printf("🧅 Error republishing payment %s: %v\n", correlationID, err)
		}
	} else {
		fmt.Printf("🧅 Payment %s permanently failed after %d retries\n", 
			correlationID, cfg.MaxRetries)
	}
}

// tryProcessor attempts to process a payment with a specific processor
func tryProcessor(ctx context.Context, processorName, correlationID string, amount float64, requestedAt string, timeout time.Duration) bool {
	endpoint := fmt.Sprintf("http://payment-processor-%s:8080/payments", processorName)
	
	payload := ProcessorPayload{
		CorrelationID: correlationID,
		Amount:        amount,
		RequestedAt:   requestedAt,
	}

	payloadJSON, err := json.Marshal(payload)
	if err != nil {
		fmt.Printf("🧅 Error marshaling payload for %s: %v\n", processorName, err)
		return false
	}

	fmt.Printf("🧅 Sending to %s: %s\n", endpoint, string(payloadJSON))

	// Create HTTP client with timeout
	client := &http.Client{Timeout: timeout}
	
	// Create request with context
	req, err := http.NewRequestWithContext(ctx, "POST", endpoint, bytes.NewBuffer(payloadJSON))
	if err != nil {
		fmt.Printf("🧅 Error creating request for %s: %v\n", processorName, err)
		return false
	}
	
	req.Header.Set("Content-Type", "application/json")

	// Make the request
	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("🧅 Error calling %s: %v\n", processorName, err)
		return false
	}
	defer resp.Body.Close()

	success := resp.StatusCode >= 200 && resp.StatusCode < 300
	fmt.Printf("🧅 Response from %s: %d (success: %t)\n", 
		processorName, resp.StatusCode, success)
	
	return success
}

// mustMarshal marshals a value to JSON, panicking if it fails
func mustMarshal(v interface{}) string {
	data, err := json.Marshal(v)
	if err != nil {
		panic(err)
	}
	return string(data)
}