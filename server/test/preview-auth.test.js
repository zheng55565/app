import assert from 'node:assert/strict';
import test from 'node:test';

const { previewCredentialsMatch, previewLoginEnabled } = await import(
  '../src/routes/auth.js'
);

function config({ env = 'development', stationMode = 'mock', enabled = true } = {}) {
  return {
    env,
    station: { mode: stationMode },
    auth: {
      preview: {
        enabled,
        username: 'preview_user',
        password: 'local-test-password',
      },
    },
  };
}

test('preview login is only available for non-production mock station', () => {
  assert.equal(previewLoginEnabled(config()), true);
  assert.equal(previewLoginEnabled(config({ env: 'production' })), false);
  assert.equal(previewLoginEnabled(config({ stationMode: 'newapi' })), false);
  assert.equal(previewLoginEnabled(config({ enabled: false })), false);
});

test('preview login compares both username and password', () => {
  const current = config();
  assert.equal(
    previewCredentialsMatch('preview_user', 'local-test-password', current),
    true
  );
  assert.equal(previewCredentialsMatch('preview_user', 'wrong', current), false);
  assert.equal(previewCredentialsMatch('wrong', 'local-test-password', current), false);
  assert.equal(
    previewCredentialsMatch(
      'preview_user',
      'local-test-password',
      config({ env: 'production' })
    ),
    false
  );
});
