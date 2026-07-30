import pg from 'pg';
import { config } from './config.js';

export const pool = new pg.Pool({
  connectionString: config.databaseUrl,
  max: config.database.poolMax,
  idleTimeoutMillis: config.database.idleTimeoutMs,
  connectionTimeoutMillis: config.database.connectionTimeoutMs,
  options: `-c timezone=${config.database.timezone}`,
});

pool.on('error', (err) => {
  console.error('[db] 空闲连接异常:', err.message);
});

export const query = (text, params) => pool.query(text, params);

// 在事务中执行回调，自动 COMMIT / ROLLBACK
export async function withTransaction(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
