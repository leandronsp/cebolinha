package config

import (
	"os"
	"strconv"
)

// Config holds all configuration values for the worker
type Config struct {
	RedisURL            string
	RedisPoolSize       int
	WorkerPoolSize      int
	JobChannelSize      int
	MaxAttempts         int
	BackoffSleepMs      int
	DefaultTimeoutMs    int
	FallbackTimeoutMs   int
	MaxRetries          int
}

// Load creates a new Config from environment variables with sensible defaults
func Load() *Config {
	return &Config{
		RedisURL:            getEnv("REDIS_URL", "redis://redis:6379/0"),
		RedisPoolSize:       getEnvAsInt("WORKER_REDIS_POOL_SIZE", 10),
		WorkerPoolSize:      getEnvAsInt("WORKER_POOL_SIZE", 10),
		JobChannelSize:      getEnvAsInt("WORKER_JOB_CHANNEL_SIZE", 1000),
		MaxAttempts:         getEnvAsInt("WORKER_MAX_ATTEMPTS", 3),
		BackoffSleepMs:      getEnvAsInt("WORKER_BACKOFF_SLEEP_MS", 2),
		DefaultTimeoutMs:    getEnvAsInt("WORKER_DEFAULT_TIMEOUT_MS", 300),
		FallbackTimeoutMs:   getEnvAsInt("WORKER_FALLBACK_TIMEOUT_MS", 100),
		MaxRetries:          getEnvAsInt("WORKER_MAX_RETRIES", 3),
	}
}

// getEnv gets an environment variable with a fallback default value
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// getEnvAsInt gets an environment variable as integer with a fallback default value
func getEnvAsInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intVal, err := strconv.Atoi(value); err == nil {
			return intVal
		}
	}
	return defaultValue
}