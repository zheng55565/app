<script setup lang="ts">
import { onBeforeUnmount, onMounted, watch } from 'vue'
import { CloseBold, Promotion } from '@element-plus/icons-vue'

import { useInterstitialAdStore } from '@/stores/interstitialAd'

const ad = useInterstitialAdStore()

function onKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape' && ad.visible) ad.close()
}

watch(() => ad.visible, (visible) => {
  document.body.style.overflow = visible ? 'hidden' : ''
})
onMounted(() => window.addEventListener('keydown', onKeydown))
onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKeydown)
  document.body.style.overflow = ''
})
</script>

<template>
  <Teleport to="body">
    <Transition name="ad-fade">
      <div v-if="ad.visible" class="ad-mask" role="dialog" aria-modal="true" aria-label="插屏广告">
        <section class="ad-modal">
          <button class="close-button" type="button" aria-label="关闭广告" @click="ad.close">
            <el-icon><CloseBold /></el-icon>
          </button>

          <div v-if="ad.loading" class="loading-state" aria-live="polite">
            <el-icon class="loading-icon"><Promotion /></el-icon>
            <el-skeleton animated :rows="3" />
          </div>

          <template v-if="ad.creative">
            <button v-if="ad.canClick" class="creative" type="button" :class="{ pending: ad.loading }" @click="ad.click">
              <img v-if="ad.creative.media_url" :src="ad.creative.media_url" alt="" @load="ad.markCreativeReady" @error="ad.failCreative" />
              <div class="creative-copy">
                <span class="sponsor"><el-icon><Promotion /></el-icon>广告</span>
                <strong>{{ ad.creative.title }}</strong>
                <p>{{ ad.creative.body }}</p>
              </div>
            </button>
            <div v-else class="creative" :class="{ pending: ad.loading }">
              <img v-if="ad.creative.media_url" :src="ad.creative.media_url" alt="" @load="ad.markCreativeReady" @error="ad.failCreative" />
              <div class="creative-copy">
                <span class="sponsor"><el-icon><Promotion /></el-icon>广告</span>
                <strong>{{ ad.creative.title }}</strong>
                <p>{{ ad.creative.body }}</p>
              </div>
            </div>
          </template>
        </section>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.ad-mask { position: fixed; inset: 0; z-index: 3000; display: grid; place-items: center; padding: max(18px, env(safe-area-inset-top)) 18px max(18px, env(safe-area-inset-bottom)); background: rgba(2,12,29,.78); backdrop-filter: blur(9px); }
.ad-modal { position: relative; width: min(392px, 100%); min-height: 390px; overflow: hidden; border: 1px solid rgba(100,200,255,.24); border-radius: 16px; background: linear-gradient(160deg, rgba(22,62,112,.98), rgba(5,25,55,.98)); box-shadow: 0 24px 70px rgba(0,0,0,.42), 0 0 28px rgba(0,170,240,.14); }
.close-button { position: absolute; top: 12px; right: 12px; z-index: 4; display: grid; place-items: center; width: 38px; height: 38px; border: 1px solid rgba(255,255,255,.18); border-radius: 50%; color: #fff; background: rgba(5,25,55,.68); cursor: pointer; transition: transform .16s ease, background .16s ease; }
.close-button:active { transform: scale(.96); }
.close-button:hover { background: rgba(5,25,55,.92); }
.loading-state { position: absolute; inset: 0; z-index: 2; display: flex; flex-direction: column; justify-content: center; gap: 22px; padding: 56px 32px 34px; background: linear-gradient(160deg, #163e70, #051937); }
.loading-icon { align-self: center; color: #00c0f9; font-size: 44px; animation: pulse 1.2s ease-in-out infinite; filter: drop-shadow(0 0 12px rgba(0,192,249,.45)); }
.creative { display: flex; flex-direction: column; width: 100%; min-height: 390px; padding: 0; border: 0; color: inherit; text-align: left; background: transparent; cursor: default; }
button.creative { cursor: pointer; }
.creative.pending { visibility: hidden; }
.creative img { width: 100%; aspect-ratio: 16 / 10; object-fit: cover; background: rgba(5,25,55,.65); }
.creative-copy { position: relative; display: flex; flex: 1; flex-direction: column; justify-content: center; min-height: 220px; padding: 32px 28px 28px; background: radial-gradient(circle at 50% 0, rgba(0,192,249,.16), transparent 64%); }
.creative-copy::before { content: ''; position: absolute; inset: 16px; border: 1px solid rgba(100,200,255,.1); border-radius: 12px; pointer-events: none; }
.sponsor { display: inline-flex; align-items: center; align-self: flex-start; gap: 5px; margin-bottom: 18px; padding: 5px 9px; border: 1px solid rgba(100,200,255,.18); border-radius: 20px; color: #89a8cb; font-size: 12px; }
strong { color: #fff; font-size: 24px; font-weight: 700; letter-spacing: 0; }
p { margin: 10px 0 0; color: #cbe5ff; font-size: 14px; line-height: 1.7; }
.ad-fade-enter-active, .ad-fade-leave-active { transition: opacity .2s ease; }
.ad-fade-enter-active .ad-modal, .ad-fade-leave-active .ad-modal { transition: transform .2s ease, opacity .2s ease; }
.ad-fade-enter-from, .ad-fade-leave-to { opacity: 0; }
.ad-fade-enter-from .ad-modal, .ad-fade-leave-to .ad-modal { opacity: 0; transform: translateY(12px) scale(.98); }
@keyframes pulse { 50% { transform: scale(1.08); opacity: .72; } }
@media (max-width: 420px) { .ad-modal { min-height: 360px; } .creative { min-height: 360px; } strong { font-size: 21px; } }
</style>
