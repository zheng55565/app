<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { Refresh, Select } from '@element-plus/icons-vue'

import { adminApi, type GameResult, type GameSettings, type SettingAudit } from '@/api/admin'
import { ApiError } from '@/api/request'
import { formatDate } from '@/utils/format'

const defaults: GameSettings = {
  rps_enabled: true, mine_enabled: true, battle_enabled: true, match3_enabled: true,
  rps_payout_basis_points: 15000, mine_liability_basis_points: 15000,
  mine_fee_basis_points: 1000, battle_fee_basis_points: 1000,
  battle_min_eliminated: 2, battle_max_eliminated: 3,
  battle_opponent_min_count: 1, battle_opponent_max_count: 2,
  battle_opponent_min_stake: 5, battle_opponent_max_stake: 30,
  match3_clear_reward_points: 1, match3_chest_again_basis_points: 9000,
  match3_chest_1_basis_points: 500, match3_chest_5_basis_points: 400,
  match3_chest_10_basis_points: 100,
}
const form = reactive<GameSettings>({ ...defaults })
const results = ref<GameResult[]>([])
const audits = ref<SettingAudit[]>([])
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const message = ref('')
const gameType = ref('')

const gameNames: Record<string, string> = { rps: '石头剪刀布', mine: '扫雷红包', battle: '八房生存', match3: '宝石消消乐' }
const resultNames: Record<string, string> = { win: '胜利', loss: '失败', draw: '平局', claimed: '安全领取', refund: '退款' }
const points = (raw: string | number) => (Number(raw || 0) / 1_000_000).toFixed(2)

async function load() {
  loading.value = true; error.value = ''
  try {
    const [settings, history, audit] = await Promise.all([
      adminApi.settings(),
      adminApi.gameResults({ page: 1, page_size: 30, game_type: gameType.value }),
      adminApi.settingAudits({ page: 1, page_size: 10 }),
    ])
    Object.assign(form, settings.game)
    results.value = history.items
    audits.value = audit.items
  } catch (err) { error.value = err instanceof ApiError ? err.message : '游戏运营数据加载失败' }
  finally { loading.value = false }
}

async function save() {
  saving.value = true; error.value = ''; message.value = ''
  try {
    const response = await adminApi.updateSettings<GameSettings>('game', { ...form })
    Object.assign(form, response.value)
    message.value = '游戏参数已保存，仅对保存后的新对局生效'
    await load()
  } catch (err) { error.value = err instanceof ApiError ? err.message : '保存失败' }
  finally { saving.value = false }
}

onMounted(load)
</script>

<template>
  <section class="operations-page">
    <header class="heading">
      <div><h1 class="page-heading">游戏运营</h1><p class="page-subtitle">全局规则、对手参数、对局流水与修改审计</p></div>
      <el-button :icon="Refresh" :loading="loading" @click="load">刷新</el-button>
    </header>
    <el-alert v-if="error" :title="error" type="error" :closable="false" show-icon />
    <el-alert v-if="message" :title="message" type="success" :closable="false" show-icon />
    <el-alert title="不能指定某个用户输赢。石头剪刀布与八房结果仍由服务端随机生成并记录规则快照。" type="warning" :closable="false" show-icon />

    <div class="settings-grid">
      <article class="glass-panel setting-panel">
        <div class="panel-title"><div><h2>游戏开关与赔率</h2><p>关闭只阻止新下注，历史和已结算记录仍可查看</p></div></div>
        <div class="switch-list">
          <label><span>石头剪刀布</span><el-switch v-model="form.rps_enabled" /></label>
          <label><span>扫雷红包</span><el-switch v-model="form.mine_enabled" /></label>
          <label><span>八房生存局</span><el-switch v-model="form.battle_enabled" /></label>
          <label><span>宝石消消乐</span><el-switch v-model="form.match3_enabled" /></label>
        </div>
        <div class="field-grid">
          <label><span>猜拳赢家总到账倍率</span><el-input-number v-model="form.rps_payout_basis_points" :min="10000" :max="30000" :step="500" /><small>15000 = 1.50 倍</small></label>
          <label><span>扫雷中雷赔付倍率</span><el-input-number v-model="form.mine_liability_basis_points" :min="10000" :max="30000" :step="500" /><small>15000 = 1.50 倍</small></label>
          <label><span>扫雷发布者手续费</span><el-input-number v-model="form.mine_fee_basis_points" :min="0" :max="3000" :step="100" /><small>1000 = 10%</small></label>
          <label><span>八房失败池手续费</span><el-input-number v-model="form.battle_fee_basis_points" :min="0" :max="3000" :step="100" /><small>1000 = 10%</small></label>
        </div>
      </article>

      <article class="glass-panel setting-panel">
        <div class="panel-title"><div><h2>八房与消消乐</h2><p>参数在新建回合时固化，进行中的回合不受影响</p></div></div>
        <div class="field-grid">
          <label><span>最少淘汰房间</span><el-input-number v-model="form.battle_min_eliminated" :min="1" :max="7" /></label>
          <label><span>最多淘汰房间</span><el-input-number v-model="form.battle_max_eliminated" :min="1" :max="7" /></label>
          <label><span>每房最少对手</span><el-input-number v-model="form.battle_opponent_min_count" :min="0" :max="5" /></label>
          <label><span>每房最多对手</span><el-input-number v-model="form.battle_opponent_max_count" :min="0" :max="5" /></label>
          <label><span>对手最少投入</span><el-input-number v-model="form.battle_opponent_min_stake" :min="1" :max="1000" /></label>
          <label><span>对手最多投入</span><el-input-number v-model="form.battle_opponent_max_stake" :min="1" :max="1000" /></label>
          <label><span>首次通关奖励积分</span><el-input-number v-model="form.match3_clear_reward_points" :min="0" :max="100" /></label>
          <label><span>宝箱再接再厉概率</span><el-input-number v-model="form.match3_chest_again_basis_points" :min="0" :max="10000" :step="100" /></label>
          <label><span>宝箱 1 分概率</span><el-input-number v-model="form.match3_chest_1_basis_points" :min="0" :max="10000" :step="100" /></label>
          <label><span>宝箱 5 分概率</span><el-input-number v-model="form.match3_chest_5_basis_points" :min="0" :max="10000" :step="100" /></label>
          <label><span>宝箱 10 分概率</span><el-input-number v-model="form.match3_chest_10_basis_points" :min="0" :max="10000" :step="100" /></label>
        </div>
        <p class="sum-note" :class="{ invalid: form.match3_chest_again_basis_points + form.match3_chest_1_basis_points + form.match3_chest_5_basis_points + form.match3_chest_10_basis_points !== 10000 }">宝箱概率合计：{{ ((form.match3_chest_again_basis_points + form.match3_chest_1_basis_points + form.match3_chest_5_basis_points + form.match3_chest_10_basis_points) / 100).toFixed(0) }}%</p>
      </article>
    </div>
    <div class="save-row"><el-button type="primary" :icon="Select" :loading="saving" @click="save">保存游戏配置</el-button></div>

    <div class="table-panel">
      <div class="tabs-row"><strong>最近对局流水</strong><el-select v-model="gameType" clearable placeholder="全部游戏" @change="load"><el-option v-for="(label,key) in gameNames" :key="key" :label="label" :value="key" /></el-select></div>
      <el-table v-loading="loading" :data="results">
        <el-table-column label="时间" min-width="145"><template #default="{row}">{{ formatDate(row.created_at) }}</template></el-table-column>
        <el-table-column label="用户" prop="username" min-width="110" />
        <el-table-column label="游戏" min-width="110"><template #default="{row}">{{ gameNames[row.game_type] || row.game_type }}</template></el-table-column>
        <el-table-column label="结果" min-width="90"><template #default="{row}"><el-tag :type="Number(row.net_profit_micropoints) >= 0 ? 'success' : 'danger'" effect="dark">{{ resultNames[row.result] || row.result }}</el-tag></template></el-table-column>
        <el-table-column label="投入" min-width="90"><template #default="{row}">{{ points(row.stake_micropoints) }}</template></el-table-column>
        <el-table-column label="到账" min-width="90"><template #default="{row}">{{ points(row.payout_micropoints) }}</template></el-table-column>
        <el-table-column label="手续费" min-width="90"><template #default="{row}">{{ points(row.fee_micropoints) }}</template></el-table-column>
        <el-table-column label="净盈亏" min-width="100"><template #default="{row}"><span :class="Number(row.net_profit_micropoints) >= 0 ? 'profit' : 'loss'">{{ Number(row.net_profit_micropoints) >= 0 ? '+' : '' }}{{ points(row.net_profit_micropoints) }}</span></template></el-table-column>
      </el-table>
    </div>

    <div class="table-panel"><div class="tabs-row"><strong>配置修改审计</strong></div><el-table :data="audits"><el-table-column label="时间" min-width="145"><template #default="{row}">{{ formatDate(row.created_at) }}</template></el-table-column><el-table-column label="管理员" prop="username" width="110" /><el-table-column label="来源 IP" prop="ip_address" width="130" /><el-table-column label="修改摘要" prop="detail" min-width="360" show-overflow-tooltip /></el-table></div>
  </section>
</template>

<style scoped>
.operations-page { display:grid; gap:18px; }.heading,.panel-title,.tabs-row,.save-row { display:flex; align-items:center; justify-content:space-between; gap:14px; }.settings-grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:16px; }.setting-panel { padding:18px; }.panel-title h2 { margin:0; color:#fff; font-size:16px; }.panel-title p { margin:5px 0 0; color:var(--muted); font-size:12px; }.switch-list { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:10px; margin:16px 0; }.switch-list label { display:flex; align-items:center; justify-content:space-between; min-height:42px; padding:0 12px; border:1px solid var(--line); border-radius:12px; background:rgba(5,25,55,.38); }.field-grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:12px; }.field-grid label { display:grid; gap:7px; color:#e6f2ff; font-size:13px; }.field-grid small { color:var(--muted); }.field-grid :deep(.el-input-number) { width:100%; }.save-row { justify-content:flex-end; }.tabs-row { padding:14px; border-bottom:1px solid var(--line); }.tabs-row .el-select { width:160px; }.profit { color:var(--success); }.loss,.sum-note.invalid { color:var(--danger); }.sum-note { margin:14px 0 0; color:var(--success); font-size:12px; }
@media(max-width:900px){.settings-grid{grid-template-columns:1fr}} @media(max-width:560px){.heading{align-items:flex-start}.field-grid,.switch-list{grid-template-columns:1fr}.tabs-row{align-items:stretch;flex-direction:column}.tabs-row .el-select{width:100%}}
</style>

