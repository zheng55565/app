import assert from 'node:assert/strict';
import test from 'node:test';

import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';

import {
  adminAuthReady,
  adminCredentialsMatch,
  signAdminToken,
} from '../src/middleware/adminAuth.js';
import { parsePagination } from '../src/routes/admin.js';

function fakeConfig(overrides = {}) {
  return {
    admin: {
      enabled: true,
      username: 'operator',
      passwordHash: '$2a$12$abcdefghijklmnopqrstuu00000000000000000000000000000',
      jwtSecret: 'admin-secret-that-is-long-enough-for-tests',
      jwtExpiresIn: '8h',
      ...overrides,
    },
  };
}

test('admin auth remains unavailable until every independent credential is configured', () => {
  assert.equal(adminAuthReady(fakeConfig()), true);
  assert.equal(adminAuthReady(fakeConfig({ enabled: false })), false);
  assert.equal(adminAuthReady(fakeConfig({ passwordHash: '' })), false);
  assert.equal(adminAuthReady(fakeConfig({ jwtSecret: '' })), false);
});

test('admin credential comparison checks username and bcrypt password', async () => {
  const passwordHash = await bcrypt.hash('correct-password', 4);
  const current = fakeConfig({ passwordHash });
  assert.equal(await adminCredentialsMatch('operator', 'correct-password', current), true);
  assert.equal(await adminCredentialsMatch('someone', 'correct-password', current), false);
  assert.equal(await adminCredentialsMatch('operator', 'wrong-password', current), false);
});

test('admin JWT is restricted to the admin audience and scope', () => {
  const current = fakeConfig();
  const token = signAdminToken('operator', current);
  const payload = jwt.verify(token, current.admin.jwtSecret, {
    issuer: 'gongyi-admin',
    audience: 'gongyi-admin-web',
  });
  assert.equal(payload.scope, 'admin');
  assert.equal(payload.sub, 'admin:operator');
});

test('admin pagination clamps unsafe values', () => {
  assert.deepEqual(parsePagination({ page: '-3', page_size: '5000' }), {
    page: 1,
    pageSize: 100,
    offset: 0,
  });
  assert.deepEqual(parsePagination({ page: '3', page_size: '25' }), {
    page: 3,
    pageSize: 25,
    offset: 50,
  });
});
