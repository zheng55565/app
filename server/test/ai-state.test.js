import assert from 'node:assert/strict';
import test from 'node:test';

import { config } from '../src/config.js';
import { shouldStartNewSegment } from '../src/services/conversationStore.js';
import { decryptCredential, encryptCredential } from '../src/services/credentialVault.js';

test('AI credential vault encrypts with authenticated encryption', () => {
  const original = config.ai.credentialEncryptionKey;
  config.ai.credentialEncryptionKey = 'test-key-material-that-is-longer-than-32-characters';
  try {
    const encrypted = encryptCredential('sk-secret-value');
    assert.notEqual(encrypted.ciphertext, 'sk-secret-value');
    assert.equal(
      decryptCredential({
        key_ciphertext: encrypted.ciphertext,
        key_iv: encrypted.iv,
        key_auth_tag: encrypted.authTag,
      }),
      'sk-secret-value'
    );
  } finally {
    config.ai.credentialEncryptionKey = original;
  }
});

test('conversation segmentation waits for context then detects topic changes', () => {
  assert.equal(
    shouldStartNewSegment('Flutter Windows 构建错误', 'Flutter Windows 打包修复', 6),
    false
  );
  assert.equal(
    shouldStartNewSegment('Flutter Windows 构建错误', '广告额度风控和多账号限制', 6),
    true
  );
  assert.equal(
    shouldStartNewSegment('Flutter Windows 构建错误', '广告额度风控和多账号限制', 2),
    false
  );
});
