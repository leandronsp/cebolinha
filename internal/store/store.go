package store

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"time"

	"github.com/redis/go-redis/v9"
)

// Store provides Redis operations for payment data
type Store struct {
	client *redis.Client
}

// PaymentData represents the structure saved to Redis
type PaymentData struct {
	Processor     string  `json:"processor"`
	CorrelationID string  `json:"correlationId"`
	Amount        float64 `json:"amount"`
	Timestamp     string  `json:"timestamp"`
}

// Summary represents the payment summary response
type Summary struct {
	Default  ProcessorSummary `json:"default"`
	Fallback ProcessorSummary `json:"fallback"`
}

// ProcessorSummary represents summary data for a processor
type ProcessorSummary struct {
	TotalRequests int64   `json:"totalRequests"`
	TotalAmount   float64 `json:"totalAmount"`
}

// New creates a new Store instance
func New(client *redis.Client) *Store {
	return &Store{client: client}
}

// Save atomically saves payment data using Redis transactions
// Returns true if saved, false if already processed
func (s *Store) Save(ctx context.Context, correlationID, processor string, amount float64, timestamp string) (bool, error) {
	// Parse timestamp to get score for ZADD
	parsedTime, err := time.Parse(time.RFC3339, timestamp)
	if err != nil {
		return false, fmt.Errorf("failed to parse timestamp: %w", err)
	}
	timestampScore := float64(parsedTime.UnixMilli()) / 1000.0

	// Create payment data JSON
	paymentData := PaymentData{
		Processor:     processor,
		CorrelationID: correlationID,
		Amount:        amount,
		Timestamp:     timestamp,
	}
	
	paymentJSON, err := json.Marshal(paymentData)
	if err != nil {
		return false, fmt.Errorf("failed to marshal payment data: %w", err)
	}

	// Atomic check-and-set using SETNX
	processedKey := fmt.Sprintf("processed:%s", correlationID)
	totalRequestsKey := fmt.Sprintf("totalRequests:%s", processor)
	totalAmountKey := fmt.Sprintf("totalAmount:%s", processor)

	// Check if already processed using SETNX
	wasSet, err := s.client.SetNX(ctx, processedKey, 1, time.Hour).Result()
	if err != nil {
		return false, fmt.Errorf("failed to check if payment was already processed: %w", err)
	}

	if !wasSet {
		// Already processed by another worker
		return false, nil
	}

	// Use transaction to save payment data
	_, err = s.client.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
		// Add to payments log with timestamp score
		pipe.ZAdd(ctx, "payments_log", redis.Z{
			Score:  timestampScore,
			Member: string(paymentJSON),
		})
		
		// Increment counters
		pipe.IncrBy(ctx, totalRequestsKey, 1)
		pipe.IncrByFloat(ctx, totalAmountKey, amount)
		
		return nil
	})

	if err != nil {
		return false, fmt.Errorf("failed to save payment data: %w", err)
	}

	return true, nil
}

// Summary gets payment summary for processors
func (s *Store) Summary(ctx context.Context, from, to *string) (*Summary, error) {
	if from != nil || to != nil {
		return s.calculateFilteredSummary(ctx, from, to)
	}

	// Get simple summary from counters (faster path)
	summary := &Summary{}
	
	for _, processor := range []string{"default", "fallback"} {
		totalRequestsKey := fmt.Sprintf("totalRequests:%s", processor)
		totalAmountKey := fmt.Sprintf("totalAmount:%s", processor)
		
		totalRequests, _ := s.client.Get(ctx, totalRequestsKey).Int64()
		totalAmount, _ := s.client.Get(ctx, totalAmountKey).Float64()
		
		// Round to 2 decimal places
		totalAmount = math.Round(totalAmount*100) / 100
		
		if processor == "default" {
			summary.Default = ProcessorSummary{
				TotalRequests: totalRequests,
				TotalAmount:   totalAmount,
			}
		} else {
			summary.Fallback = ProcessorSummary{
				TotalRequests: totalRequests,
				TotalAmount:   totalAmount,
			}
		}
	}

	return summary, nil
}

// calculateFilteredSummary calculates summary for a date range using ZRANGEBYSCORE
func (s *Store) calculateFilteredSummary(ctx context.Context, from, to *string) (*Summary, error) {
	var fromScore, toScore float64 = math.Inf(-1), math.Inf(1)
	
	if from != nil {
		if parsedTime, err := time.Parse(time.RFC3339, *from); err == nil {
			fromScore = float64(parsedTime.UnixMilli()) / 1000.0
		}
	}
	
	if to != nil {
		if parsedTime, err := time.Parse(time.RFC3339, *to); err == nil {
			toScore = float64(parsedTime.UnixMilli()) / 1000.0
		}
	}

	// Get payments in range
	payments, err := s.client.ZRangeByScore(ctx, "payments_log", &redis.ZRangeBy{
		Min: fmt.Sprintf("%f", fromScore),
		Max: fmt.Sprintf("%f", toScore),
	}).Result()
	
	if err != nil {
		return nil, fmt.Errorf("failed to get payments from log: %w", err)
	}

	// Initialize summary
	summary := &Summary{
		Default:  ProcessorSummary{TotalRequests: 0, TotalAmount: 0.0},
		Fallback: ProcessorSummary{TotalRequests: 0, TotalAmount: 0.0},
	}

	// Process each payment
	for _, paymentJSON := range payments {
		var payment PaymentData
		if err := json.Unmarshal([]byte(paymentJSON), &payment); err != nil {
			continue // Skip invalid entries
		}

		if payment.Processor == "default" {
			summary.Default.TotalRequests++
			summary.Default.TotalAmount += payment.Amount
		} else if payment.Processor == "fallback" {
			summary.Fallback.TotalRequests++
			summary.Fallback.TotalAmount += payment.Amount
		}
	}

	// Round amounts to 2 decimal places
	summary.Default.TotalAmount = math.Round(summary.Default.TotalAmount*100) / 100
	summary.Fallback.TotalAmount = math.Round(summary.Fallback.TotalAmount*100) / 100

	return summary, nil
}

// IsProcessed checks if a payment has already been processed
func (s *Store) IsProcessed(ctx context.Context, correlationID string) bool {
	processedKey := fmt.Sprintf("processed:%s", correlationID)
	exists, _ := s.client.Exists(ctx, processedKey).Result()
	return exists > 0
}

// PurgeAll clears all payment data from Redis
func (s *Store) PurgeAll(ctx context.Context) error {
	return s.client.FlushDB(ctx).Err()
}