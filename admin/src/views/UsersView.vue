<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { Search, Refresh } from '@element-plus/icons-vue'

import { adminApi, type AdminUser } from '@/api/admin'
import { ApiError } from '@/api/request'
import { formatDate, formatMicrounits } from '@/utils/format'

const rows = ref<AdminUser[]>([])
const total = ref(0)
const loading = ref(false)
const error = ref('')
const filter = reactive({ q: '', status: '', page: 1, page_size: 20 })

async function load(reset = false) {
  if (reset) filter.page = 1
  loading.value = true
  error.value = ''
  try {
    const result = await adminApi.users(filter)
    rows.value = result.items
    total.value = result.total
  } catch (err) { error.value = err instanceof ApiError ? err.message : '用户列表加载失败' }
  finally { loading.value = false }
}

onMounted(() => load())
</script>

<template>
  <section class="users-page">
    <header><h1 class="page-heading">用户管理</h1><p class="page-subtitle">账号状态与额度余额查询</p></header>
    <el-alert v-if="error" :title="error" type="error" :closable="false" show-icon />
    <div class="table-panel">
      <div class="table-toolbar">
        <el-input v-model="filter.q" clearable placeholder="用户ID或昵称" :prefix-icon="Search" @keyup.enter="load(true)" />
        <el-select v-model="filter.status" clearable placeholder="全部状态" @change="load(true)">
          <el-option label="正常" value="active" /><el-option label="封禁" value="banned" />
        </el-select>
        <el-button type="primary" :icon="Search" @click="load(true)">查询</el-button>
        <el-button :icon="Refresh" :loading="loading" @click="load()">刷新</el-button>
      </div>
      <el-table v-loading="loading" :data="rows" min-width="900">
        <el-table-column prop="id" label="ID" width="84" />
        <el-table-column label="用户" min-width="160">
          <template #default="{ row }"><strong>{{ row.linuxdo_username || row.username || `用户${row.id}` }}</strong><small class="sub">{{ row.username || '-' }}</small></template>
        </el-table-column>
        <el-table-column label="状态" width="90">
          <template #default="{ row }"><el-tag :type="row.status === 'active' ? 'success' : 'danger'" effect="dark">{{ row.status === 'active' ? '正常' : '封禁' }}</el-tag></template>
        </el-table-column>
        <el-table-column label="AI额度" min-width="120"><template #default="{ row }">¥{{ formatMicrounits(row.balance_microunits) }}</template></el-table-column>
        <el-table-column label="游戏积分" min-width="110"><template #default="{ row }">{{ formatMicrounits(row.game_balance_micropoints) }}</template></el-table-column>
        <el-table-column label="中转站ID" prop="station_user_id" min-width="110" />
        <el-table-column label="最近登录" min-width="150"><template #default="{ row }">{{ formatDate(row.last_login_at) }}</template></el-table-column>
        <el-table-column label="注册时间" min-width="150"><template #default="{ row }">{{ formatDate(row.created_at) }}</template></el-table-column>
      </el-table>
      <div class="pagination-row"><el-pagination v-model:current-page="filter.page" v-model:page-size="filter.page_size" layout="total, prev, pager, next" :total="total" @current-change="load()" /></div>
    </div>
  </section>
</template>

<style scoped>
.users-page { display: grid; gap: 20px; }.table-toolbar .el-select { width: 140px; }.sub { display: block; margin-top: 3px; color: var(--muted); font-size: 11px; } strong { color: #fff; font-size: 13px; }
@media (max-width:720px) { .table-toolbar .el-select { width: 100%; } }
</style>
