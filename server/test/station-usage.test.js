import assert from 'node:assert/strict';
import test from 'node:test';

import { config } from '../src/config.js';
import {
  listUsageLogsByLinuxdoId,
  rewardMicrounitsToQuota,
} from '../src/services/stationClient.js';

test('advertising CNY microunits convert to the same quota used by New API', () => {
  assert.equal(rewardMicrounitsToQuota(20000, 70000), 1400);
  assert.equal(rewardMicrounitsToQuota(1000000, 70000), 70000);
});

test('New API consumption logs are scoped to the linked station account', async () => {
  const originalStation = { ...config.station };
  const originalFetch = globalThis.fetch;
  const requests = [];
  Object.assign(config.station, {
    mode: 'newapi',
    baseUrl: 'https://station.example',
    adminToken: 'admin-token',
    adminUserId: '9',
    timeoutMs: 1000,
  });
  globalThis.fetch = async (url, options) => {
    requests.push({ url: String(url), options });
    if (String(url).includes('/api/user/search')) {
      return {
        ok: true,
        json: async () => ({
          success: true,
          data: {
            items: [
              {
                id: 42,
                username: 'linked_user',
                linux_do_id: '12345',
                status: 1,
                quota: 9000,
              },
            ],
          },
        }),
      };
    }
    return {
      ok: true,
      json: async () => ({
        success: true,
        data: {
          total: 2,
          items: [
            { id: 1, username: 'linked_user', type: 2, quota: 1200 },
            { id: 2, username: 'another_user', type: 2, quota: 9999 },
          ],
        },
      }),
    };
  };

  try {
    const result = await listUsageLogsByLinuxdoId('12345', 'linked_user', 50);
    assert.equal(result.total, 2);
    assert.deepEqual(result.items.map((item) => item.id), [1]);
    assert.match(requests[1].url, /\/api\/log\/\?.*type=2/);
    assert.match(requests[1].url, /username=linked_user/);
    assert.equal(requests[1].options.headers.Authorization, 'admin-token');
    assert.equal(requests[1].options.headers['New-Api-User'], '9');
  } finally {
    globalThis.fetch = originalFetch;
    Object.assign(config.station, originalStation);
  }
});
