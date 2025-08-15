use crate::queue::Queue;
use redis::{Client, Connection, RedisResult};
use std::ops::{Deref, DerefMut};
use std::sync::Arc;

pub struct ConnectionPool {
    queue: Arc<Queue<Connection>>,
    client: Client,
    max_connections: usize,
}

impl ConnectionPool {
    pub fn new(redis_url: &str, size: usize) -> RedisResult<Self> {
        let client = Client::open(redis_url)?;
        let queue = Arc::new(Queue::new());

        // Pre-allocate connections
        for _ in 0..size {
            let conn = client.get_connection()?;
            queue.push(conn);
        }

        Ok(ConnectionPool {
            queue,
            client,
            max_connections: size,
        })
    }

    pub fn get(&self) -> RedisResult<PooledConnection> {
        // Just get a connection without testing
        let conn = self.queue.pop();
        Ok(PooledConnection::new(conn, self.queue.clone()))
    }

}

pub struct PooledConnection {
    conn: Option<Connection>,
    pool: Arc<Queue<Connection>>,
}

impl PooledConnection {
    fn new(conn: Connection, pool: Arc<Queue<Connection>>) -> Self {
        PooledConnection {
            conn: Some(conn),
            pool,
        }
    }
}

impl Drop for PooledConnection {
    fn drop(&mut self) {
        if let Some(conn) = self.conn.take() {
            self.pool.push(conn);
        }
    }
}

impl Deref for PooledConnection {
    type Target = Connection;

    fn deref(&self) -> &Self::Target {
        self.conn
            .as_ref()
            .expect("Connection should always be available")
    }
}

impl DerefMut for PooledConnection {
    fn deref_mut(&mut self) -> &mut Self::Target {
        self.conn
            .as_mut()
            .expect("Connection should always be available")
    }
}

