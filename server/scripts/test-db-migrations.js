// embedded-postgres 在部分启动失败场景会以 0 退出。父进程必须看到明确的
// 成功标记才把迁移测试判为通过，避免部署流水线出现假阳性。
import { spawn } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const runner = path.join(__dirname, 'test-db-migrations-runner.js');
const databaseDir = await mkdtemp(path.join(os.tmpdir(), 'gongyi-migration-test-'));
const child = spawn(process.execPath, [runner], {
  cwd: path.join(__dirname, '..'),
  env: { ...process.env, MIGRATION_TEST_DATABASE_DIR: databaseDir },
  stdio: ['inherit', 'pipe', 'pipe'],
});

let stdout = '';
child.stdout.on('data', (chunk) => {
  const text = chunk.toString();
  stdout += text;
  process.stdout.write(text);
});
child.stderr.on('data', (chunk) => process.stderr.write(chunk));

const exitCode = await new Promise((resolve, reject) => {
  child.once('error', reject);
  child.once('close', (code) => resolve(code ?? 1));
});
await rm(databaseDir, { recursive: true, force: true }).catch(() => {});

const successMarker = '[migration-test] schema + v2 至 v14 通过';
if (exitCode !== 0 || !stdout.includes(successMarker)) {
  console.error('[migration-test] 未完成数据库迁移验证');
  process.exitCode = exitCode || 1;
}
