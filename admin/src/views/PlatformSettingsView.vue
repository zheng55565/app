<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { Refresh, Select } from '@element-plus/icons-vue'

import { adminApi, type AdSettings, type AiSettings } from '@/api/admin'
import { ApiError } from '@/api/request'

const ad = reactive<AdSettings>({ rewarded_enabled: true, reward_microunits: 20000, daily_max: 6, daily_reward_max_microunits: 120000, device_daily_max: 6, device_reward_max_microunits: 120000, ip_daily_max: 30, ip_reward_max_microunits: 600000 })
const ai = reactive<AiSettings>({ enabled: true, image_models: [] })
const imageModelsText = ref('')
const loading = ref(false)
const savingAd = ref(false)
const savingAi = ref(false)
const error = ref('')
const message = ref('')

async function load() {
  loading.value = true; error.value = ''
  try { const value = await adminApi.settings(); Object.assign(ad, value.ad); Object.assign(ai, value.ai); imageModelsText.value = value.ai.image_models.join('\n') }
  catch (err) { error.value = err instanceof ApiError ? err.message : '配置加载失败' }
  finally { loading.value = false }
}
async function saveAd() { savingAd.value = true; error.value=''; message.value=''; try { const response=await adminApi.updateSettings<AdSettings>('ad',{...ad}); Object.assign(ad,response.value); message.value='广告额度策略已保存，只影响新创建的广告任务' } catch(err){ error.value=err instanceof ApiError?err.message:'保存失败' } finally{savingAd.value=false} }
async function saveAi() { savingAi.value=true; error.value=''; message.value=''; try { const payload={ enabled:ai.enabled, image_models:imageModelsText.value.split(/[\n,]/).map(v=>v.trim()).filter(Boolean) }; const response=await adminApi.updateSettings<AiSettings>('ai',payload); Object.assign(ai,response.value); imageModelsText.value=response.value.image_models.join('\n'); message.value='模型能力配置已保存，App 刷新后生效' } catch(err){ error.value=err instanceof ApiError?err.message:'保存失败' } finally{savingAi.value=false} }
onMounted(load)
</script>

<template>
  <section class="settings-page"><header class="heading"><div><h1 class="page-heading">广告与模型</h1><p class="page-subtitle">额度策略、风控上限和生图模型白名单</p></div><el-button :icon="Refresh" :loading="loading" @click="load">刷新</el-button></header>
    <el-alert v-if="error" :title="error" type="error" :closable="false" show-icon/><el-alert v-if="message" :title="message" type="success" :closable="false" show-icon/>
    <div class="settings-grid">
      <article class="glass-panel panel"><div class="title"><div><h2>激励广告额度</h2><p>只有平台服务器签名回调成功才入账</p></div><el-switch v-model="ad.rewarded_enabled" /></div>
        <div class="field-grid"><label><span>单次奖励微额度</span><el-input-number v-model="ad.reward_microunits" :min="1" :max="100000000" :step="1000"/><small>1,000,000 = 1 元额度</small></label><label><span>账号每日次数</span><el-input-number v-model="ad.daily_max" :min="1" :max="100"/></label><label><span>账号每日额度上限</span><el-input-number v-model="ad.daily_reward_max_microunits" :min="1" :max="1000000000" :step="1000"/></label><label><span>设备每日次数</span><el-input-number v-model="ad.device_daily_max" :min="1" :max="500"/></label><label><span>设备每日额度上限</span><el-input-number v-model="ad.device_reward_max_microunits" :min="1" :max="1000000000" :step="1000"/></label><label><span>IP 每日次数</span><el-input-number v-model="ad.ip_daily_max" :min="1" :max="5000"/></label><label><span>IP 每日额度上限</span><el-input-number v-model="ad.ip_reward_max_microunits" :min="1" :max="10000000000" :step="1000"/></label></div>
        <div class="action"><el-button type="primary" :icon="Select" :loading="savingAd" @click="saveAd">保存广告配置</el-button></div>
      </article>
      <article class="glass-panel panel"><div class="title"><div><h2>AI 与生图模型</h2><p>对话模型从 NewAPI /v1/models 动态获取</p></div><el-switch v-model="ai.enabled" /></div>
        <el-alert title="Claude Opus、GPT、DeepSeek 等文本模型只要中转站真实返回即可使用；生图模型必须加入白名单。" type="info" :closable="false" show-icon/>
        <label class="model-field"><span>生图模型白名单</span><el-input v-model="imageModelsText" type="textarea" :rows="10" placeholder="每行一个模型 ID，例如：&#10;gpt-image-1.5&#10;flux-2-pro"/><small>填写中转站真实模型 ID。纯文本模型不要加入这里。</small></label>
        <div class="action"><el-button type="primary" :icon="Select" :loading="savingAi" @click="saveAi">保存模型配置</el-button></div>
      </article>
    </div>
  </section>
</template>

<style scoped>
.settings-page{display:grid;gap:18px}.heading,.title,.action{display:flex;align-items:center;justify-content:space-between;gap:14px}.settings-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}.panel{padding:18px}.title h2{margin:0;color:#fff;font-size:16px}.title p{margin:5px 0 0;color:var(--muted);font-size:12px}.field-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px;margin:18px 0}.field-grid label,.model-field{display:grid;gap:7px;color:#e6f2ff;font-size:13px}.field-grid small,.model-field small{color:var(--muted)}.field-grid :deep(.el-input-number){width:100%}.model-field{margin-top:16px}.action{justify-content:flex-end;margin-top:16px}@media(max-width:900px){.settings-grid{grid-template-columns:1fr}}@media(max-width:560px){.heading{align-items:flex-start}.field-grid{grid-template-columns:1fr}}
</style>
