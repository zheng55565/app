import { computed, ref } from 'vue'
import { defineStore } from 'pinia'

import { request } from '@/api/request'

export type AdTrigger = 'rewarded_ad_completed' | 'game_settlement' | 'red_packet_claimed' | string
export type AdEventType = 'impression' | 'click' | 'close' | 'load_failed'

export interface AdCreative {
  id: string
  title: string
  body: string
  media_url: string
  click_url: string
}

interface CreativeResponse {
  enabled: boolean
  creative?: AdCreative
  cooldown_seconds?: number
}

export interface ShowInterstitialOptions {
  trigger: AdTrigger
  placement?: string
  cooldownSeconds?: number
  metadata?: Record<string, unknown>
}

const SESSION_KEY = 'gongyi_ad_session_id'
const COOLDOWN_PREFIX = 'gongyi_ad_last_shown:'

function uuid() {
  return crypto.randomUUID()
}

function sessionId() {
  let value = sessionStorage.getItem(SESSION_KEY)
  if (!value) {
    value = uuid()
    sessionStorage.setItem(SESSION_KEY, value)
  }
  return value
}

export function isCoolingDown(lastShownAt: number, cooldownSeconds: number, now = Date.now()) {
  return lastShownAt > 0 && now - lastShownAt < Math.max(0, cooldownSeconds) * 1000
}

export function safeClickUrl(value: string) {
  try {
    const url = new URL(value, window.location.origin)
    return url.protocol === 'http:' || url.protocol === 'https:' ? url.toString() : ''
  } catch {
    return ''
  }
}

export const useInterstitialAdStore = defineStore('interstitial-ad', () => {
  const visible = ref(false)
  const loading = ref(false)
  const ready = ref(false)
  const creative = ref<AdCreative | null>(null)
  const trigger = ref<AdTrigger>('unknown')
  const placement = ref('global_interstitial')
  const metadata = ref<Record<string, unknown>>({})
  const cooldownSeconds = ref(60)
  let requestInFlight = false

  const canClick = computed(() => Boolean(creative.value && safeClickUrl(creative.value.click_url)))

  async function report(eventType: AdEventType, extra: Record<string, unknown> = {}) {
    const payload = {
      event_id: uuid(),
      creative_id: creative.value?.id || undefined,
      placement: placement.value,
      trigger: trigger.value,
      event_type: eventType,
      session_id: sessionId(),
      occurred_at: new Date().toISOString(),
      metadata: { ...metadata.value, ...extra, route: window.location.pathname },
    }
    try {
      await request('/api/ad-events', {
        method: 'POST',
        auth: false,
        body: payload,
        timeoutMs: 3000,
        keepalive: true,
      })
    } catch {
      // 埋点是尽力上报，永远不能影响页面原业务。
    }
  }

  function reset() {
    visible.value = false
    loading.value = false
    ready.value = false
    creative.value = null
  }

  async function show(options: ShowInterstitialOptions): Promise<boolean> {
    if (visible.value || loading.value || requestInFlight) return false
    const targetPlacement = options.placement || 'global_interstitial'
    const requestedCooldown = Math.max(0, options.cooldownSeconds ?? 60)
    const lastShownAt = Number(localStorage.getItem(`${COOLDOWN_PREFIX}${targetPlacement}`) || 0)
    if (isCoolingDown(lastShownAt, requestedCooldown)) return false

    requestInFlight = true
    trigger.value = options.trigger
    placement.value = targetPlacement
    metadata.value = options.metadata || {}
    cooldownSeconds.value = requestedCooldown
    visible.value = true
    loading.value = true
    ready.value = false
    creative.value = null
    try {
      const response = await request<CreativeResponse>(
        `/api/web-ads/interstitial?placement=${encodeURIComponent(targetPlacement)}`,
        { auth: false, timeoutMs: 5000 },
      )
      if (!response.enabled || !response.creative) {
        reset()
        return false
      }
      creative.value = response.creative
      cooldownSeconds.value = Math.max(0, options.cooldownSeconds ?? response.cooldown_seconds ?? 60)
      if (!response.creative.media_url) queueMicrotask(markCreativeReady)
      return true
    } catch {
      void report('load_failed', { stage: 'request' })
      reset()
      return false
    } finally {
      requestInFlight = false
    }
  }

  function markCreativeReady() {
    if (!visible.value || !creative.value || ready.value) return
    loading.value = false
    ready.value = true
    localStorage.setItem(`${COOLDOWN_PREFIX}${placement.value}`, String(Date.now()))
    void report('impression')
  }

  function failCreative() {
    if (!visible.value) return
    void report('load_failed', { stage: 'media' })
    reset()
  }

  function close() {
    if (!visible.value) return
    void report('close', { visible_ms: 0 })
    reset()
  }

  function click() {
    const url = creative.value ? safeClickUrl(creative.value.click_url) : ''
    if (!url) return
    void report('click')
    window.open(url, '_blank', 'noopener,noreferrer')
  }

  return {
    visible,
    loading,
    ready,
    creative,
    trigger,
    placement,
    cooldownSeconds,
    canClick,
    show,
    close,
    click,
    markCreativeReady,
    failCreative,
  }
})
