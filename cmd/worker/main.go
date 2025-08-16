package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/signal"
	"sync"
	"syscall"

	"github.com/leandronsp/cebolinha/internal/config"
	"github.com/leandronsp/cebolinha/internal/processor"
	"github.com/leandronsp/cebolinha/internal/store"
	"github.com/redis/go-redis/v9"
)

func main() {
	fmt.Println("🧅 Cebolinha worker starting...")

	// Load configuration
	cfg := config.Load()
	fmt.Printf("🧅 Worker Redis pool size: %d, Worker pool size: %d, Job channel size: %d\n", 
		cfg.RedisPoolSize, cfg.WorkerPoolSize, cfg.JobChannelSize)

	// Initialize Redis client (go-redis handles connection pooling internally)
	redisClient := redis.NewClient(&redis.Options{
		Addr:     "redis:6379",
		DB:       0,
		PoolSize: cfg.RedisPoolSize,
	})

	// Test Redis connection
	ctx := context.Background()
	if err := redisClient.Ping(ctx).Err(); err != nil {
		fmt.Printf("🧅 Failed to connect to Redis: %v\n", err)
		os.Exit(1)
	}

	// Create store instance
	storeInstance := store.New(redisClient)

	// Create job channel (buffered to handle bursts)
	jobs := make(chan processor.PaymentJob, cfg.JobChannelSize)

	// Create context for graceful shutdown
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	// Start worker pool
	var wg sync.WaitGroup
	for i := 0; i < cfg.WorkerPoolSize; i++ {
		wg.Add(1)
		go worker(ctx, &wg, i, jobs, storeInstance, redisClient, cfg)
	}

	// Start Redis subscriber
	wg.Add(1)
	go subscriber(ctx, &wg, jobs, redisClient)

	// Handle graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	// Wait for shutdown signal
	<-sigChan
	fmt.Println("🧅 Shutting down gracefully...")

	// Cancel context to stop all goroutines
	cancel()

	// Close job channel to stop workers
	close(jobs)

	// Wait for all goroutines to finish
	wg.Wait()

	// Close Redis connection
	if err := redisClient.Close(); err != nil {
		fmt.Printf("🧅 Error closing Redis connection: %v\n", err)
	}

	fmt.Println("🧅 Worker shutdown complete")
}

// worker processes payment jobs from the channel
func worker(ctx context.Context, wg *sync.WaitGroup, id int, jobs <-chan processor.PaymentJob, 
	store *store.Store, redisClient *redis.Client, cfg *config.Config) {
	defer wg.Done()

	fmt.Printf("🧅 Payment worker %d started\n", id)

	for {
		select {
		case job, ok := <-jobs:
			if !ok {
				fmt.Printf("🧅 Payment worker %d stopping (channel closed)\n", id)
				return
			}
			processor.Process(ctx, job, store, redisClient, cfg)

		case <-ctx.Done():
			fmt.Printf("🧅 Payment worker %d stopping (context cancelled)\n", id)
			return
		}
	}
}

// subscriber listens to Redis PubSub and sends jobs to the worker pool
func subscriber(ctx context.Context, wg *sync.WaitGroup, jobs chan<- processor.PaymentJob, redisClient *redis.Client) {
	defer wg.Done()

	fmt.Println("🧅 Redis subscriber starting...")

	// Subscribe to payments channel
	pubsub := redisClient.Subscribe(ctx, "payments")
	defer pubsub.Close()

	// Get channel for receiving messages
	ch := pubsub.Channel()

	for {
		select {
		case msg, ok := <-ch:
			if !ok {
				fmt.Println("🧅 Redis subscriber stopping (channel closed)")
				return
			}

			// Parse the payment job
			var job processor.PaymentJob
			if err := json.Unmarshal([]byte(msg.Payload), &job); err != nil {
				fmt.Printf("🧅 Error parsing payment job: %v\n", err)
				continue
			}

			// Send to worker pool (blocking to preserve all payments)
			select {
			case jobs <- job:
				// Successfully sent to worker
			case <-ctx.Done():
				fmt.Println("🧅 Redis subscriber stopping (context cancelled)")
				return
			}

		case <-ctx.Done():
			fmt.Println("🧅 Redis subscriber stopping (context cancelled)")
			return
		}
	}
}