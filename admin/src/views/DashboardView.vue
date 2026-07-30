<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { User, VideoPlay, Coin, Warning, Refresh, Promotion, Trophy, Pointer } from '@element-plus/icons-vue'

import { adminApi, type Overview } from '@/api/admin'
import { ApiError } from '@/api/request'
import { useInterstitialAdStore } from '@/stores/interstitialAd'
import { formatMicrounits } from '@/utils/format'

const data = ref<Overview | null>(null)
const loading = ref(false)
const error = ref('')
const ad = useInterstitialAdStore()

const stats = computed(() => [
  { label: '总用户', value: data.value?.users_total ?? '-', hint: `活跃 ${data.value?.users_active ?? '-'}`, icon: User, tone: 'blue' },
  { label: '今日广告任务', value: data.value?.ad_tasks_today ?? '-', hint: `到账 ${data.value?.rewarded_today ?? '-'}`, icon: VideoPlay, tone: 'cyan' },
  { label: '今日奖励额度', value: data.value ? `¥${formatMicrounits(data.value.reward_microunits_today)}` : '-', hint: '服务端回调入账', icon: Coin, tone: 'green' },
  { label: '回调异常', value: data.value?.callback_failures_today ?? '-', hint: '今日未通过回调', icon: Warning, tone: 'red' },
])

async function load() {
  loading.value = true
  error.value = ''
  try { data.value = await adminApi.overview() }
  catch (err) { error.value = err instanceof ApiError ? err.message : '总览加载失败' }
  finally { loading.value = false }
}

function previewAd() {
  void ad.show({ trigger: 'admin_preview', cooldownSeconds: 0, metadata: { source: 'dashboard' } })
}

onMounted(load)
</script>

<template>
  <section class="dashboard">
    <header class="heading-row">
      <div><h1 class="page-heading">运营总览</h1><p class="page-subtitle">用户、广告回调与游戏运行数据</p></div>
      <div class="heading-actions">
        <el-button :icon="Promotion" @click="previewAd">预览插屏</el-button>
        <el-button type="primary" :icon="Refresh" :loading="loading" @click="load">刷新</el-button>
      </div>
    </header>
    <el-alert v-if="error" :title="error" type="error" :closable="false" show-icon />
    <div class="stats-grid">
      <article v-for="item in stats" :key="item.label" class="stat glass-panel" :class="item.tone">
        <div class="stat-icon"><el-icon><component :is="item.icon" /></el-icon></div>
        <div><span>{{ item.label }}</span><strong>{{ item.value }}</strong><small>{{ item.hint }}</small></div>
      </article>
    </div>
    <div class="signal-grid">
      <section class="glass-panel signal-panel">
        <header><div><h2>网页插屏漏斗</h2><p>今日客户端埋点</p></div><el-icon><Pointer /></el-icon></header>
        <div class="funnel">
          <div><span>曝光</span><strong>{{ data?.impressions_today ?? '-' }}</strong></div>
          <div class="arrow">→</div>
          <div><span>点击</span><strong>{{ data?.clicks_today ?? '-' }}</strong></div>
          <div class="rate"><span>点击率</span><strong>{{ data && data.impressions_today ? `${((data.clicks_today / data.impressions_today) * 100).toFixed(1)}%` : '0.0%' }}</strong></div>
        </div>
      </section>
      <section class="glass-panel signal-panel">
        <header><div><h2>游戏运行</h2><p>今日服务端结算</p></div><el-icon><Trophy /></el-icon></header>
        <div class="game-count"><strong>{{ data?.game_rounds_today ?? '-' }}</strong><span>局</span></div>
        <div class="health-line"><span class="status-dot" />结算服务正常</div>
      </section>
    </div>
  </section>
</template>

<style scoped>
.dashboard { display: grid; gap: 20px; }
.heading-row { display: flex; align-items: center; justify-content: space-between; gap: 16px; }
.heading-actions { display: flex; gap: 8px; }
.stats-grid { display: grid; grid-template-columns: repeat(4, minmax(0,1fr)); gap: 14px; }
.stat { display: flex; align-items: center; gap: 14px; min-height: 126px; padding: 20px; }
.stat-icon { display: grid; flex: 0 0 44px; width: 44px; height: 44px; place-items: center; border: 1px solid var(--line); border-radius: 12px; color: var(--primary); background: rgba(0,153,232,.12); font-size: 22px; }
.stat.green .stat-icon { color: var(--success); background: rgba(46,213,115,.1); }.stat.red .stat-icon { color: var(--danger); background: rgba(255,71,87,.1); }
.stat span, .stat small { display: block; color: var(--muted); font-size: 12px; }.stat strong { display: block; margin: 5px 0 4px; color: #fff; font-size: 24px; letter-spacing: 0; }
.signal-grid { display: grid; grid-template-columns: 1.65fr 1fr; gap: 14px; }
.signal-panel { min-height: 230px; padding: 20px; }
.signal-panel header { display: flex; align-items: center; justify-content: space-between; }.signal-panel h2 { margin: 0; color: #fff; font-size: 16px; }.signal-panel p { margin: 5px 0 0; color: var(--muted); font-size: 12px; }.signal-panel header>.el-icon { color: var(--primary); font-size: 24px; }
.funnel { display: grid; grid-template-columns: 1fr auto 1fr 1.2fr; align-items: center; gap: 18px; margin-top: 38px; }.funnel>div:not(.arrow) { padding: 15px; border-left: 2px solid var(--primary); background: rgba(0,153,232,.08); }.funnel span { display: block; color: var(--muted); font-size: 12px; }.funnel strong { display: block; margin-top: 6px; color: #fff; font-size: 22px; }.funnel .arrow { color: var(--muted); }.funnel .rate { border-color: var(--success); }
.game-count { margin-top: 34px; color: #fff; }.game-count strong { font-size: 44px; }.game-count span { margin-left: 7px; color: var(--muted); font-size: 14px; }.health-line { margin-top: 22px; color: #cbe5ff; font-size: 13px; }
@media (max-width: 1120px) { .stats-grid { grid-template-columns: repeat(2, minmax(0,1fr)); } }
@media (max-width: 720px) { .heading-row { align-items: flex-start; flex-direction: column; }.heading-actions { width: 100%; }.heading-actions .el-button { flex: 1; }.stats-grid, .signal-grid { grid-template-columns: 1fr; }.stat { min-height: 105px; }.funnel { grid-template-columns: 1fr 1fr; }.funnel .arrow { display: none; } }
</style>
