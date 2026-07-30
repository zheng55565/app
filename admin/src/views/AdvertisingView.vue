<script setup lang="ts">
import { onMounted, reactive, ref, watch } from 'vue'
import { Refresh } from '@element-plus/icons-vue'

import { adminApi, type AdClientEvent, type AdTask, type CallbackAudit } from '@/api/admin'
import { ApiError } from '@/api/request'
import { formatDate, formatMicrounits, shortId } from '@/utils/format'

const active = ref('tasks')
const loading = ref(false)
const error = ref('')
const total = ref(0)
const tasks = ref<AdTask[]>([])
const callbacks = ref<CallbackAudit[]>([])
const events = ref<AdClientEvent[]>([])
const pager = reactive({ page: 1, page_size: 20, status: '', event_type: '' })

const eventNames: Record<string, string> = { impression: '曝光', click: '点击', close: '关闭', load_failed: '加载失败' }
const triggerNames: Record<string, string> = { rewarded_ad_completed: '广告完成', game_settlement: '游戏结算', red_packet_claimed: '红包领取', admin_preview: '管理端预览' }

async function load(reset = false) {
  if (reset) pager.page = 1
  loading.value = true
  error.value = ''
  try {
    if (active.value === 'tasks') {
      const result = await adminApi.tasks({ page: pager.page, page_size: pager.page_size, status: pager.status })
      tasks.value = result.items; total.value = result.total
    } else if (active.value === 'callbacks') {
      const result = await adminApi.callbacks({ page: pager.page, page_size: pager.page_size })
      callbacks.value = result.items; total.value = result.total
    } else {
      const result = await adminApi.events({ page: pager.page, page_size: pager.page_size, event_type: pager.event_type })
      events.value = result.items; total.value = result.total
    }
  } catch (err) { error.value = err instanceof ApiError ? err.message : '广告数据加载失败' }
  finally { loading.value = false }
}

watch(active, () => load(true))
onMounted(() => load())
</script>

<template>
  <section class="ad-page">
    <header class="heading"><div><h1 class="page-heading">广告中心</h1><p class="page-subtitle">奖励任务、平台回调和插屏埋点</p></div><el-button type="primary" :icon="Refresh" :loading="loading" @click="load()">刷新</el-button></header>
    <el-alert v-if="error" :title="error" type="error" :closable="false" show-icon />
    <div class="table-panel">
      <div class="tabs-row">
        <el-segmented v-model="active" :options="[{label:'奖励任务',value:'tasks'},{label:'平台回调',value:'callbacks'},{label:'插屏埋点',value:'events'}]" />
        <el-select v-if="active === 'tasks'" v-model="pager.status" clearable placeholder="全部状态" @change="load(true)">
          <el-option label="处理中" value="created" /><el-option label="已到账" value="rewarded" /><el-option label="已过期" value="expired" />
        </el-select>
        <el-select v-if="active === 'events'" v-model="pager.event_type" clearable placeholder="全部事件" @change="load(true)">
          <el-option v-for="(label,key) in eventNames" :key="key" :label="label" :value="key" />
        </el-select>
      </div>

      <el-table v-if="active === 'tasks'" v-loading="loading" :data="tasks">
        <el-table-column prop="id" label="任务" width="82" />
        <el-table-column label="用户" min-width="110"><template #default="{row}">{{ row.username || `用户${row.user_id}` }}</template></el-table-column>
        <el-table-column label="平台/广告位" min-width="170"><template #default="{row}"><strong>{{ row.ad_platform }}</strong><small>{{ row.ad_unit_id }}</small></template></el-table-column>
        <el-table-column label="奖励" min-width="100"><template #default="{row}">¥{{ formatMicrounits(row.reward_amount_microunits) }}</template></el-table-column>
        <el-table-column label="状态" width="98"><template #default="{row}"><el-tag :type="row.status === 'rewarded' ? 'success' : row.status === 'expired' ? 'info' : 'warning'" effect="dark">{{ row.status === 'rewarded' ? '已到账' : row.status === 'expired' ? '已过期' : '处理中' }}</el-tag></template></el-table-column>
        <el-table-column label="客户端交易号" min-width="160"><template #default="{row}"><span :title="row.client_transaction_id || ''">{{ shortId(row.client_transaction_id) }}</span></template></el-table-column>
        <el-table-column label="平台交易号" min-width="160"><template #default="{row}"><span :title="row.provider_transaction_id || ''">{{ shortId(row.provider_transaction_id) }}</span></template></el-table-column>
        <el-table-column label="创建时间" min-width="150"><template #default="{row}">{{ formatDate(row.created_at) }}</template></el-table-column>
      </el-table>

      <el-table v-else-if="active === 'callbacks'" v-loading="loading" :data="callbacks">
        <el-table-column prop="id" label="回调" width="82" />
        <el-table-column prop="provider" label="平台" width="90" />
        <el-table-column label="签名" width="90"><template #default="{row}"><el-tag :type="row.signature_valid ? 'success' : 'danger'" effect="dark">{{ row.signature_valid ? '通过' : '未通过' }}</el-tag></template></el-table-column>
        <el-table-column label="HTTP" width="84"><template #default="{row}"><span :class="row.http_status && row.http_status >= 400 ? 'loss' : 'profit'">{{ row.http_status ?? '-' }}</span></template></el-table-column>
        <el-table-column label="交易号" min-width="170"><template #default="{row}"><span :title="row.transaction_id || ''">{{ shortId(row.transaction_id, 18) }}</span></template></el-table-column>
        <el-table-column label="广告位" prop="placement_id" min-width="130" />
        <el-table-column label="结果" prop="outcome" min-width="190" show-overflow-tooltip />
        <el-table-column label="到达时间" min-width="150"><template #default="{row}">{{ formatDate(row.received_at) }}</template></el-table-column>
      </el-table>

      <el-table v-else v-loading="loading" :data="events">
        <el-table-column prop="id" label="事件" width="82" />
        <el-table-column label="类型" width="100"><template #default="{row}"><el-tag :type="row.event_type === 'click' ? 'success' : row.event_type === 'load_failed' ? 'danger' : 'primary'" effect="dark">{{ eventNames[row.event_type] }}</el-tag></template></el-table-column>
        <el-table-column label="触发场景" min-width="130"><template #default="{row}">{{ triggerNames[row.trigger_name] || row.trigger_name }}</template></el-table-column>
        <el-table-column label="广告位置" prop="placement" min-width="150" />
        <el-table-column label="素材" prop="creative_id" min-width="160" />
        <el-table-column label="会话" min-width="150"><template #default="{row}"><span :title="row.session_id || ''">{{ shortId(row.session_id) }}</span></template></el-table-column>
        <el-table-column label="上报时间" min-width="150"><template #default="{row}">{{ formatDate(row.created_at) }}</template></el-table-column>
      </el-table>
      <div class="pagination-row"><el-pagination v-model:current-page="pager.page" v-model:page-size="pager.page_size" layout="total, prev, pager, next" :total="total" @current-change="load()" /></div>
    </div>
  </section>
</template>

<style scoped>
.ad-page { display: grid; gap: 20px; }.heading { display: flex; align-items: center; justify-content: space-between; gap: 16px; }.tabs-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 14px; border-bottom: 1px solid var(--line); }.tabs-row .el-select { width: 140px; } strong, small { display: block; } strong { color: #fff; } small { margin-top: 3px; color: var(--muted); font-size: 11px; }.profit { color: var(--success); }.loss { color: var(--danger); }
@media(max-width:720px) { .tabs-row { align-items: stretch; flex-direction: column; overflow-x: auto; }.tabs-row .el-segmented, .tabs-row .el-select { width: 100%; }.heading { align-items: flex-start; } }
</style>
