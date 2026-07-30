import 'dotenv/config';

import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const sqlDir = path.join(scriptDir, '..', 'sql');
const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl) throw new Error('缺少 DATABASE_URL');

const files = (await readdir(sqlDir))
  .map((name) => ({ name, version: Number(/^migrate_v(\d+)\.sql$/.exec(name)?.[1]) }))
  .filter((item) => Number.isInteger(item.version))
  .sort((left, right) => left.version - right.version);

const client = new pg.Client({ connectionString: databaseUrl });
await client.connect();
try {
  for (const file of files) {
    await client.query(await readFile(path.join(sqlDir, file.name), 'utf8'));
    console.log(`[migrate] ${file.name}`);
  }
  const { rows } = await client.query(
    `SELECT column_name FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'ad_tasks'
       AND column_name IN ('client_transaction_id', 'client_completed_at')`
  );
  if (rows.length !== 2) throw new Error('v8 广告交易凭据字段未生效');
  console.log('[migrate] v8 广告交易凭据字段已验证');
  const { rows: auditRows } = await client.query(
    `SELECT table_name FROM information_schema.tables
     WHERE table_schema = 'public' AND table_name = 'ad_callback_audits'`
  );
  if (auditRows.length !== 1) throw new Error('v9 广告回调审计表未生效');
  console.log('[migrate] v9 广告回调审计表已验证');
  const { rows: v10Rows } = await client.query(
    `SELECT table_name FROM information_schema.tables
     WHERE table_schema = 'public'
       AND table_name IN ('admin_audit_logs', 'ad_client_events')`
  );
  if (v10Rows.length !== 2) throw new Error('v10 管理审计或广告埋点表未生效');
  console.log('[migrate] v10 管理审计与广告埋点表已验证');
  const { rows: runtimeRows } = await client.query(
    `SELECT table_name FROM information_schema.tables
     WHERE table_schema = 'public' AND table_name = 'runtime_settings'`
  );
  if (runtimeRows.length !== 1) throw new Error('v11 运行配置表未生效');
  const { rows: snapshotRows } = await client.query(
    `SELECT column_name FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'game_match3_sessions'
       AND column_name = 'rules_snapshot'`
  );
  if (snapshotRows.length !== 1) throw new Error('v12 消消乐规则快照未生效');
  const { rows: resultIdentityRows } = await client.query(
    `SELECT indexname FROM pg_indexes
     WHERE schemaname = 'public' AND tablename = 'game_results'
       AND indexname = 'uniq_game_results_user_game_mode'`
  );
  if (resultIdentityRows.length !== 1) throw new Error('v13 游戏结果身份唯一索引未生效');
  const { rows: providerTransactionRows } = await client.query(
    `SELECT table_name FROM information_schema.tables
     WHERE table_schema = 'public' AND table_name = 'ad_provider_transactions'`
  );
  if (providerTransactionRows.length !== 1) throw new Error('v14 广告交易防重表未生效');
  console.log('[migrate] v11-v14 运营配置、结果身份与广告交易防重已验证');
} finally {
  await client.end();
}
