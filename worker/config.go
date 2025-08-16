package main

import (
	"os"
	"strconv"
)

type Config struct {
	RedisPoolSize       int
	WorkerPoolSize      int
	JobChannelSize      int
	DefaultTimeoutMs    int
	FallbackTimeoutMs   int
}

func Load() *Config {
	return &Config{
		RedisPoolSize:       getEnvAsInt("WORKER_REDIS_POOL_SIZE", 50),
		WorkerPoolSize:      getEnvAsInt("WORKER_POOL_SIZE", 50),
		JobChannelSize:      getEnvAsInt("WORKER_JOB_CHANNEL_SIZE", 500),
		DefaultTimeoutMs:    getEnvAsInt("WORKER_DEFAULT_TIMEOUT_MS", 3500),
		FallbackTimeoutMs:   getEnvAsInt("WORKER_FALLBACK_TIMEOUT_MS", 300),
	}
}

func getEnvAsInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intVal, err := strconv.Atoi(value); err == nil {
			return intVal
		}
	}
	return defaultValue
}
