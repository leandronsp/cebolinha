package main

import (
	"context"
	"encoding/json"

	"github.com/leandronsp/cebolinha/internal/config"
	"github.com/leandronsp/cebolinha/internal/processor"
	"github.com/leandronsp/cebolinha/internal/store"
	"github.com/redis/go-redis/v9"
)

func main() {
	cfg := config.Load()
	redisClient := redis.NewClient(&redis.Options{
		Addr:     "redis:6379",
		PoolSize: cfg.RedisPoolSize,
	})
	ctx := context.Background()
	storeInstance := store.New(redisClient)
	jobs := make(chan processor.PaymentJob, cfg.JobChannelSize)

	for i := 0; i < cfg.WorkerPoolSize; i++ {
		go worker(ctx, i, jobs, storeInstance, redisClient, cfg)
	}
	go subscriber(ctx, jobs, redisClient)
	select {}
}

func worker(ctx context.Context, id int, jobs <-chan processor.PaymentJob, 
	store *store.Store, redisClient *redis.Client, cfg *config.Config) {
	for job := range jobs {
		processor.Process(ctx, job, store, redisClient, cfg)
	}
}

func subscriber(ctx context.Context, jobs chan<- processor.PaymentJob, redisClient *redis.Client) {
	pubsub := redisClient.Subscribe(ctx, "payments")
	defer pubsub.Close()

	for msg := range pubsub.Channel() {
		var job processor.PaymentJob
		if json.Unmarshal([]byte(msg.Payload), &job) == nil {
			jobs <- job
		}
	}
}
