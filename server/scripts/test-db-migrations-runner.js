// 一次性验证 schema + v2 至 v6 能在空数据库上连续执行。
import EmbeddedPostgres from 'embedded-postgres';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const databaseDir = process.env.MIGRATION_TEST_DATABASE_DIR;
if (!databaseDir) throw new Error('缺少MIGRATION_TEST_DATABASE_DIR');
const port = 55433;
const pg = new EmbeddedPostgres({
  databaseDir,
  user: 'postgres',
  password: 'postgres',
  port,
  persistent: false,
});

try {
  await pg.initialise();
  await pg.start();
  const admin = pg.getPgClient();
  await admin.connect();
  await admin.query('CREATE DATABASE migration_test');
  await admin.end();

  const { default: pgLib } = await import('pg');
  const db = new pgLib.Client({
    connectionString: `postgres://postgres:postgres@127.0.0.1:${port}/migration_test`,
  });
  await db.connect();
  for (const file of [
    'schema.sql',
    'migrate_v2.sql',
    'migrate_v3.sql',
    'migrate_v4.sql',
    'migrate_v5.sql',
    'migrate_v6.sql',
    'migrate_v7.sql',
    'migrate_v8.sql',
    'migrate_v9.sql',
    'migrate_v10.sql',
    'migrate_v11.sql',
    'migrate_v12.sql',
    'migrate_v13.sql',
    'migrate_v14.sql',
  ]) {
    await db.query(await readFile(path.join(__dirname, '..', 'sql', file), 'utf8'));
  }
  const { rows } = await db.query(
    `SELECT
       to_regclass('public.daily_ad_subject_limits') IS NOT NULL AS has_subject_limits,
       to_regclass('public.api_request_leases') IS NOT NULL AS has_ai_leases,
       to_regclass('public.user_ai_credentials') IS NOT NULL AS has_ai_credentials,
       to_regclass('public.ai_conversations') IS NOT NULL AS has_ai_conversations,
       to_regclass('public.ai_document_jobs') IS NOT NULL AS has_document_jobs,
       to_regclass('public.game_wallets') IS NOT NULL AS has_game_wallets,
       to_regclass('public.game_results') IS NOT NULL AS has_game_results,
       to_regclass('public.game_match3_sessions') IS NOT NULL AS has_match3_sessions,
       to_regclass('public.game_recovery_ad_tasks') IS NOT NULL AS has_recovery_tasks,
       to_regclass('public.ad_callback_audits') IS NOT NULL AS has_callback_audits,
       to_regclass('public.admin_audit_logs') IS NOT NULL AS has_admin_audits,
       to_regclass('public.ad_client_events') IS NOT NULL AS has_ad_events,
       to_regclass('public.runtime_settings') IS NOT NULL AS has_runtime_settings,
       EXISTS (
         SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='ad_tasks'
           AND column_name='client_transaction_id'
       ) AS has_client_ad_evidence,
       EXISTS (
         SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='game_match3_sessions'
           AND column_name='rules_snapshot'
       ) AS has_match3_rules_snapshot,
       to_regclass('public.uniq_game_results_user_game_mode') IS NOT NULL
         AS has_game_result_role_identity,
       to_regclass('public.ad_provider_transactions') IS NOT NULL
         AS has_provider_transactions`
  );
  if (
    !rows[0].has_subject_limits ||
    !rows[0].has_ai_leases ||
    !rows[0].has_ai_credentials ||
    !rows[0].has_ai_conversations ||
    !rows[0].has_document_jobs ||
    !rows[0].has_game_wallets ||
    !rows[0].has_game_results ||
    !rows[0].has_match3_sessions ||
    !rows[0].has_recovery_tasks ||
    !rows[0].has_callback_audits ||
    !rows[0].has_admin_audits ||
    !rows[0].has_ad_events ||
    !rows[0].has_runtime_settings ||
    !rows[0].has_match3_rules_snapshot ||
    !rows[0].has_game_result_role_identity ||
    !rows[0].has_provider_transactions ||
    !rows[0].has_client_ad_evidence
  ) {
    throw new Error('v3至v8关键表或字段不存在');
  }
  await db.end();
  console.log('[migration-test] schema + v2 至 v14 通过');
} finally {
  await pg.stop().catch(() => {});
}
