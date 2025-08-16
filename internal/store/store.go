package store

import (
	"context"
	"fmt"

	"github.com/redis/go-redis/v9"
)

type Store struct {
	client *redis.Client
}

func New(client *redis.Client) *Store {
	return &Store{client: client}
}

func (s *Store) Save(ctx context.Context, correlationID, processor string, amount float64, timestamp string) {
	totalRequestsKey := fmt.Sprintf("totalRequests:%s", processor)
	totalAmountKey := fmt.Sprintf("totalAmount:%s", processor)

	s.client.IncrBy(ctx, totalRequestsKey, 1)
	s.client.IncrByFloat(ctx, totalAmountKey, amount)
}
