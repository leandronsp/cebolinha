use redis::{Commands, RedisResult};
use serde_json::{json, Value};
use std::sync::Arc;
use crate::redis_pool::ConnectionPool;

#[allow(dead_code)]
pub struct Store {
    pool: Arc<ConnectionPool>,
}

impl Store {
    pub fn new(pool: Arc<ConnectionPool>) -> Self {
        Store { pool }
    }

    pub fn save(&self, correlation_id: &str, processor: &str, amount: f64, timestamp: &str) -> RedisResult<bool> {
        let mut conn = self.pool.get()?;
        
        // Atomic check-and-set using SETNX (set if not exists)
        let was_set: bool = conn.set_nx(format!("processed:{}", correlation_id), 1)?;
        
        if !was_set {
            // Already processed by another worker
            return Ok(false);
        }
        
        // Set expiration and save payment data
        let payment_data = json!({
            "processor": processor,
            "correlationId": correlation_id,
            "amount": amount,
            "timestamp": timestamp
        });

        let timestamp_score = chrono::DateTime::parse_from_rfc3339(timestamp)
            .unwrap()
            .timestamp_millis() as f64 / 1000.0;

        redis::pipe()
            .atomic()
            .expire(format!("processed:{}", correlation_id), 3600)
            .zadd("payments_log", payment_data.to_string(), timestamp_score)
            .incr(format!("totalRequests:{}", processor), 1)
            .incr(format!("totalAmount:{}", processor), amount)
            .query::<()>(&mut *conn)?;

        Ok(true)
    }

    pub fn summary(&self, from: Option<&str>, to: Option<&str>) -> RedisResult<Value> {
        if from.is_some() || to.is_some() {
            self.calculate_filtered_summary(from, to)
        } else {
            let mut conn = self.pool.get()?;
            let mut summary = json!({});

            for processor in &["default", "fallback"] {
                let total_requests: i64 = conn.get(format!("totalRequests:{}", processor)).unwrap_or(0);
                let total_amount: f64 = conn.get(format!("totalAmount:{}", processor)).unwrap_or(0.0);

                summary[processor] = json!({
                    "totalRequests": total_requests,
                    "totalAmount": (total_amount * 100.0).round() / 100.0
                });
            }

            Ok(summary)
        }
    }

    fn calculate_filtered_summary(&self, from: Option<&str>, to: Option<&str>) -> RedisResult<Value> {
        let from_score = from
            .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
            .map(|dt| dt.timestamp_millis() as f64 / 1000.0)
            .unwrap_or(f64::NEG_INFINITY);

        let to_score = to
            .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
            .map(|dt| dt.timestamp_millis() as f64 / 1000.0)
            .unwrap_or(f64::INFINITY);

        let mut conn = self.pool.get()?;
        let payments: Vec<String> = conn.zrangebyscore("payments_log", from_score, to_score)?;

        let mut summary = json!({
            "default": {"totalRequests": 0, "totalAmount": 0.0},
            "fallback": {"totalRequests": 0, "totalAmount": 0.0}
        });

        for payment_json in payments {
            if let Ok(payment) = serde_json::from_str::<Value>(&payment_json) {
                let processor = payment["processor"].as_str().unwrap_or("");
                let amount = payment["amount"].as_f64().unwrap_or(0.0);

                if let Some(proc_summary) = summary[processor].as_object_mut() {
                    if let Some(requests) = proc_summary.get_mut("totalRequests") {
                        *requests = json!(requests.as_i64().unwrap_or(0) + 1);
                    }
                    if let Some(total) = proc_summary.get_mut("totalAmount") {
                        *total = json!(total.as_f64().unwrap_or(0.0) + amount);
                    }
                }
            }
        }

        for processor in &["default", "fallback"] {
            if let Some(proc_summary) = summary[processor].as_object_mut() {
                if let Some(total) = proc_summary.get_mut("totalAmount") {
                    *total = json!((total.as_f64().unwrap_or(0.0) * 100.0).round() / 100.0);
                }
            }
        }

        Ok(summary)
    }

    pub fn purge_all(&self) -> RedisResult<()> {
        let mut conn = self.pool.get()?;
        redis::cmd("FLUSHDB").query::<()>(&mut *conn)?;
        Ok(())
    }

    pub fn is_processed(&self, correlation_id: &str) -> bool {
        match self.pool.get() {
            Ok(mut conn) => conn.get::<_, Option<String>>(format!("processed:{}", correlation_id))
                .unwrap_or(None)
                .is_some(),
            Err(_) => false,
        }
    }
}