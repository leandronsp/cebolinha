use serde_json::Value;
use std::sync::Arc;
use std::thread;
use std::time::Duration;

mod queue;
mod redis_pool;
mod store;

use queue::Queue;
use redis_pool::ConnectionPool;
use store::Store;

fn main() {
    println!("🧅 Cebolinha worker starting...");

    // Configuration from environment variables
    let redis_pool_size: usize = std::env::var("WORKER_REDIS_POOL_SIZE")
        .unwrap_or_else(|_| "10".to_string())
        .parse()
        .expect("Invalid WORKER_REDIS_POOL_SIZE");

    let thread_pool_size: usize = std::env::var("WORKER_THREAD_POOL_SIZE")
        .unwrap_or_else(|_| "10".to_string())
        .parse()
        .expect("Invalid WORKER_THREAD_POOL_SIZE");

    println!(
        "🧅 Worker Redis pool size: {}, Thread pool size: {}",
        redis_pool_size, thread_pool_size
    );

    // Initialize Redis connection pool
    let redis_pool = Arc::new(
        ConnectionPool::new("redis://redis:6379/0", redis_pool_size)
            .expect("Failed to create Redis connection pool"),
    );

    let payment_queue = Arc::new(Queue::new());

    for i in 0..thread_pool_size {
        let queue = payment_queue.clone();
        let pool = redis_pool.clone();
        thread::spawn(move || {
            println!("🧅 Payment worker {} started", i);
            loop {
                let payload = queue.pop();
                process_payment(payload, pool.clone());
            }
        });
    }

    // Redis subscriber thread
    let queue_clone = payment_queue.clone();
    thread::spawn(move || {
        let client =
            redis::Client::open("redis://redis:6379/0").expect("Failed to connect to Redis");
        let mut conn = client
            .get_connection()
            .expect("Failed to get Redis connection");
        let mut pubsub = conn.as_pubsub();
        pubsub
            .subscribe("payments")
            .expect("Failed to subscribe to payments");

        loop {
            let msg = pubsub.get_message().expect("Failed to get message");
            if let Ok(payload) = msg.get_payload::<String>() {
                if let Ok(data) = serde_json::from_str::<Value>(&payload) {
                    queue_clone.push(data);
                }
            }
        }
    });

    // Keep main thread alive
    loop {
        thread::sleep(Duration::from_secs(1));
    }
}

fn process_payment(payload: Value, pool: Arc<ConnectionPool>) {
    let correlation_id = payload["correlationId"].as_str().unwrap_or("");
    let amount = payload["amount"].as_f64().unwrap_or(0.0);

    // Set requestedAt if it's missing (ASM doesn't add timestamps)
    let requested_at = if let Some(timestamp) = payload["requestedAt"].as_str() {
        timestamp.to_string()
    } else {
        // Generate current timestamp in RFC3339 format
        chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
    };

    // Configuration from environment variables
    let max_attempts: usize = std::env::var("WORKER_MAX_ATTEMPTS")
        .unwrap_or_else(|_| "3".to_string())
        .parse()
        .unwrap_or(3);

    let backoff_sleep_ms: u64 = std::env::var("WORKER_BACKOFF_SLEEP_MS")
        .unwrap_or_else(|_| "2".to_string())
        .parse()
        .unwrap_or(2);

    let default_timeout_ms: u64 = std::env::var("WORKER_DEFAULT_TIMEOUT_MS")
        .unwrap_or_else(|_| "300".to_string())
        .parse()
        .unwrap_or(300);

    let fallback_timeout_ms: u64 = std::env::var("WORKER_FALLBACK_TIMEOUT_MS")
        .unwrap_or_else(|_| "100".to_string())
        .parse()
        .unwrap_or(100);

    let max_retries: usize = std::env::var("WORKER_MAX_RETRIES")
        .unwrap_or_else(|_| "3".to_string())
        .parse()
        .unwrap_or(3);

    // Get current retry count from payload or default to 0
    let current_retry_count = payload["_retry_count"].as_u64().unwrap_or(0) as usize;

    let store = Store::new(pool.clone());

    // Only check is_processed for retried payments to avoid latency on first attempts
    if current_retry_count > 0 && store.is_processed(correlation_id) {
        println!(
            "🧅 Payment {} already processed (retry {}), skipping",
            correlation_id, current_retry_count
        );
        return;
    }

    for attempt in 0..max_attempts {
        if try_processor(
            "default",
            &payload,
            Duration::from_millis(default_timeout_ms),
        ) {
            // Atomic save - returns true if saved, false if already existed
            match store.save(correlation_id, "default", amount, &requested_at) {
                Ok(true) => {
                    println!(
                        "🧅 Payment {} processed by default (attempt {})",
                        correlation_id,
                        attempt + 1
                    );
                }
                Ok(false) => {
                    println!(
                        "🧅 Payment {} already saved by another worker",
                        correlation_id
                    );
                }
                Err(e) => {
                    eprintln!("🧅 Error saving payment {}: {}", correlation_id, e);
                }
            }
            return;
        }

        if attempt < max_attempts - 1 {
            std::thread::sleep(Duration::from_millis(
                backoff_sleep_ms * (attempt + 1) as u64,
            ));
        }
    }

    if try_processor(
        "fallback",
        &payload,
        Duration::from_millis(fallback_timeout_ms),
    ) {
        // Atomic save - returns true if saved, false if already existed
        match store.save(correlation_id, "fallback", amount, requested_at) {
            Ok(true) => {
                println!("🧅 Payment {} processed by fallback", correlation_id);
            }
            Ok(false) => {
                println!(
                    "🧅 Payment {} already saved by another worker",
                    correlation_id
                );
            }
            Err(e) => {
                eprintln!("🧅 Error saving payment {}: {}", correlation_id, e);
            }
        }
        return;
    }

    // Both processors failed - retry by re-publishing to channel
    if current_retry_count < max_retries {
        println!(
            "🧅 Both processors failed for {} - retrying ({}/{})",
            correlation_id,
            current_retry_count + 1,
            max_retries
        );

        if let Ok(mut conn) = pool.get() {
            let _ = redis::cmd("PUBLISH")
                .arg("payments")
                .arg(payload.to_string())
                .query::<i32>(&mut *conn);
        }
    } else {
        eprintln!(
            "🧅 Payment {} permanently failed after {} retries",
            correlation_id, max_retries
        );
    }
}

fn try_processor(processor_name: &str, payload: &Value, timeout: Duration) -> bool {
    let endpoint = format!("http://payment-processor-{}:8080/payments", processor_name);

    match ureq::post(&endpoint)
        .timeout(timeout)
        .set("Content-Type", "application/json")
        .send_string(&payload.to_string())
    {
        Ok(response) => response.status() >= 200 && response.status() < 300,
        Err(_) => false,
    }
}
