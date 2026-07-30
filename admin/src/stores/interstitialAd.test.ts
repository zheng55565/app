import { beforeEach, describe, expect, it, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'

import { isCoolingDown, useInterstitialAdStore } from './interstitialAd'

describe('interstitial ad store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    localStorage.clear()
    sessionStorage.clear()
    vi.unstubAllGlobals()
  })

  it('enforces the configured cooldown', () => {
    expect(isCoolingDown(10_000, 60, 69_999)).toBe(true)
    expect(isCoolingDown(10_000, 60, 70_000)).toBe(false)
  })

  it('silently closes when creative loading fails', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('offline')))
    const store = useInterstitialAdStore()
    await expect(store.show({ trigger: 'game_settlement' })).resolves.toBe(false)
    expect(store.visible).toBe(false)
    expect(store.loading).toBe(false)
  })

  it('suppresses duplicate show calls while a request is pending', async () => {
    let resolveFetch: ((value: unknown) => void) | undefined
    vi.stubGlobal('fetch', vi.fn(() => new Promise((resolve) => { resolveFetch = resolve })))
    const store = useInterstitialAdStore()
    const first = store.show({ trigger: 'game_settlement' })
    await expect(store.show({ trigger: 'red_packet_claimed' })).resolves.toBe(false)
    resolveFetch?.({ ok: true, json: async () => ({ enabled: false }) })
    await expect(first).resolves.toBe(false)
  })
})
