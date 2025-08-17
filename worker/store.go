package main

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/redis/go-redis/v9"
)

type Store struct {
	client *redis.Client
}

func New(client *redis.Client) *Store {
	return &Store{client: client}
}

func (s *Store) Save(ctx context.Context, correlationID, processor string, amount float64, timestamp string) {
	// Parse timestamp to get Unix timestamp for sorted set score
	timestampScore, err := parseTimestampToScore(timestamp)
	if err != nil {
		timestampScore = float64(time.Now().Unix()) // fallback to current time
	}
	
	// Legacy global keys (for backward compatibility)
	totalRequestsKey := fmt.Sprintf("totalRequests:%s", processor)
	totalAmountKey := fmt.Sprintf("totalAmount:%s", processor)
	
	// New sorted set keys for date filtering
	requestsSetKey := fmt.Sprintf("payments:%s:requests", processor)
	amountsSetKey := fmt.Sprintf("payments:%s:amounts", processor)

	// Save to legacy format (for existing queries)
	s.client.IncrBy(ctx, totalRequestsKey, 1)
	s.client.IncrByFloat(ctx, totalAmountKey, amount)
	
	// Save to sorted sets (for date filtering)
	// Use timestamp as score, correlationID as member for requests
	s.client.ZAdd(ctx, requestsSetKey, redis.Z{
		Score:  timestampScore,
		Member: correlationID,
	})
	
	// Use timestamp as score, amount as member for amounts
	s.client.ZAdd(ctx, amountsSetKey, redis.Z{
		Score:  timestampScore,
		Member: fmt.Sprintf("%.2f", amount),
	})
}

// QueryDateRange queries payments within a date range using sorted sets
func (s *Store) QueryDateRange(ctx context.Context, fromDate, toDate string) (map[string]interface{}, error) {
	// Convert dates to Unix timestamps
	fromScore, err := dateToScore(fromDate)
	if err != nil {
		return nil, fmt.Errorf("invalid from date: %v", err)
	}
	
	toScore, err := dateToScore(toDate)
	if err != nil {
		return nil, fmt.Errorf("invalid to date: %v", err)
	}
	
	// Add one day to toScore to make it inclusive
	toScore += 86400 // 24 * 60 * 60 seconds
	
	result := map[string]interface{}{
		"default":  s.queryProcessorRange(ctx, "default", fromScore, toScore),
		"fallback": s.queryProcessorRange(ctx, "fallback", fromScore, toScore),
	}
	
	return result, nil
}

// queryProcessorRange queries a specific processor within a score range
func (s *Store) queryProcessorRange(ctx context.Context, processor string, fromScore, toScore float64) map[string]interface{} {
	requestsSetKey := fmt.Sprintf("payments:%s:requests", processor)
	amountsSetKey := fmt.Sprintf("payments:%s:amounts", processor)
	
	// Count requests in range
	requestCount := s.client.ZCount(ctx, requestsSetKey, 
		fmt.Sprintf("%.0f", fromScore), 
		fmt.Sprintf("%.0f", toScore))
	
	// Get amounts in range and sum them
	amounts := s.client.ZRangeByScore(ctx, amountsSetKey, &redis.ZRangeBy{
		Min: fmt.Sprintf("%.0f", fromScore),
		Max: fmt.Sprintf("%.0f", toScore),
	})
	
	totalAmount := 0.0
	for _, amountStr := range amounts.Val() {
		if amount, err := strconv.ParseFloat(amountStr, 64); err == nil {
			totalAmount += amount
		}
	}
	
	return map[string]interface{}{
		"totalRequests": requestCount.Val(),
		"totalAmount":   totalAmount,
	}
}

// parseTimestampToScore converts RFC3339 timestamp to Unix timestamp
func parseTimestampToScore(timestamp string) (float64, error) {
	t, err := time.Parse(time.RFC3339, timestamp)
	if err != nil {
		return 0, err
	}
	return float64(t.Unix()), nil
}

// dateToScore converts YYYY-MM-DD date to Unix timestamp (start of day)
func dateToScore(dateStr string) (float64, error) {
	t, err := time.Parse("2006-01-02", dateStr)
	if err != nil {
		return 0, err
	}
	return float64(t.Unix()), nil
}
