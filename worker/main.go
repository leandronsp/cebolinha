package main

import (
	"context"
	"encoding/json"

	"github.com/redis/go-redis/v9"
)

func main() {
	cfg := Load()
	redisClient := redis.NewClient(&redis.Options{
		Addr:     "redis:6379",
		PoolSize: cfg.RedisPoolSize,
	})
	ctx := context.Background()
	storeInstance := New(redisClient)
	jobs := make(chan PaymentJob, cfg.JobChannelSize)

	for i := 0; i < cfg.WorkerPoolSize; i++ {
		go worker(ctx, i, jobs, storeInstance, redisClient, cfg)
	}
	go subscriber(ctx, jobs, redisClient)
	select {}
}

func worker(ctx context.Context, id int, jobs <-chan PaymentJob, 
	store *Store, redisClient *redis.Client, cfg *Config) {
	for job := range jobs {
		Process(ctx, job, store, redisClient, cfg)
	}
}

func subscriber(ctx context.Context, jobs chan<- PaymentJob, redisClient *redis.Client) {
	pubsub := redisClient.Subscribe(ctx, "payments")
	defer pubsub.Close()

	for msg := range pubsub.Channel() {
		var job PaymentJob
		if json.Unmarshal([]byte(msg.Payload), &job) == nil {
			jobs <- job
		}
	}
}
