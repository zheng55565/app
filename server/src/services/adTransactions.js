export async function claimProviderTransaction(
  client,
  { provider, transactionId, purpose, taskToken, userId }
) {
  const normalizedProvider = String(provider || '').trim();
  const normalizedTransactionId = String(transactionId || '').trim();
  const normalizedTaskToken = String(taskToken || '').trim();
  if (!normalizedTransactionId) return { ok: true, skipped: true };
  if (
    !normalizedProvider || normalizedProvider.length > 60 ||
    normalizedTransactionId.length > 160 ||
    !['home_balance', 'game_recovery'].includes(purpose) ||
    !normalizedTaskToken || normalizedTaskToken.length > 120
  ) {
    return { ok: false, message: '广告交易凭据格式无效' };
  }
  const { rows: inserted } = await client.query(
    `INSERT INTO ad_provider_transactions
       (provider,transaction_id,purpose,task_token,user_id)
     VALUES ($1,$2,$3,$4,$5)
     ON CONFLICT (provider,transaction_id) DO NOTHING
     RETURNING provider`,
    [normalizedProvider, normalizedTransactionId, purpose, normalizedTaskToken, userId]
  );
  if (inserted.length) return { ok: true, duplicated: false };
  const { rows } = await client.query(
    `SELECT purpose,task_token,user_id FROM ad_provider_transactions
     WHERE provider=$1 AND transaction_id=$2`,
    [normalizedProvider, normalizedTransactionId]
  );
  const existing = rows[0];
  const sameTarget = existing && existing.purpose === purpose &&
    existing.task_token === normalizedTaskToken && String(existing.user_id) === String(userId);
  return sameTarget
    ? { ok: true, duplicated: true }
    : { ok: false, message: '该广告交易已经用于其他任务' };
}
