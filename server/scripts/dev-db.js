// 本地测试用：启动内嵌 PostgreSQL 并初始化 schema
// 用法: node scripts/dev-db.js   （保持运行，Ctrl+C 停止）
import EmbeddedPostgres from 'embedded-postgres';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const pg = new EmbeddedPostgres({
  databaseDir: path.join(__dirname, '..', '.pgdata'),
  user: 'postgres',
  password: 'postgres',
  port: 5433,
  persistent: true,
});

const dbName = 'linuxdo_ad_reward';

async function main() {
  await pg.initialise().catch(() => {}); // 已初始化过会报错，忽略
  await pg.start();
  const client = pg.getPgClient();
  await client.connect();
  const { rows } = await client.query(`SELECT 1 FROM pg_database WHERE datname = $1`, [dbName]);
  if (rows.length === 0) {
    await client.query(`CREATE DATABASE ${dbName}`);
  }
  await client.end();

  // 对目标库执行 schema
  const { default: pgLib } = await import('pg');
  const db = new pgLib.Client({
    connectionString: `postgres://postgres:postgres@localhost:5433/${dbName}`,
  });
  await db.connect();
  const schema = readFileSync(path.join(__dirname, '..', 'sql', 'schema.sql'), 'utf8');
  await db.query(schema);
  // v2 迁移（幂等，可重复执行）
  const migrateV2 = readFileSync(path.join(__dirname, '..', 'sql', 'migrate_v2.sql'), 'utf8');
  await db.query(migrateV2);
  await db.end();

  console.log(`[dev-db] PostgreSQL 已就绪: postgres://postgres:postgres@localhost:5433/${dbName}`);
  console.log('[dev-db] 按 Ctrl+C 停止');
}

process.on('SIGINT', async () => {
  await pg.stop();
  process.exit(0);
});

main().catch(async (err) => {
  console.error('[dev-db] 启动失败:', err);
  await pg.stop().catch(() => {});
  process.exit(1);
});
