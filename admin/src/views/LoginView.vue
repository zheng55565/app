<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Lock, User, Monitor } from '@element-plus/icons-vue'

import { adminApi } from '@/api/admin'
import { ApiError } from '@/api/request'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()
const form = reactive({ username: '', password: '' })
const loading = ref(false)
const enabled = ref<boolean | null>(null)
const error = ref('')

onMounted(async () => {
  try { enabled.value = (await adminApi.status()).enabled }
  catch { enabled.value = false }
})

async function submit() {
  if (!form.username || !form.password || loading.value || enabled.value === false) return
  loading.value = true
  error.value = ''
  try {
    await auth.login(form.username, form.password)
    await router.replace(typeof route.query.redirect === 'string' ? route.query.redirect : '/')
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : '登录失败'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <main class="login-page">
    <section class="login-panel glass-panel">
      <div class="mark"><el-icon><Monitor /></el-icon></div>
      <h1>AI 公益管理台</h1>
      <p>运营与广告数据中心</p>
      <el-alert v-if="enabled === false" title="服务端尚未启用管理员登录" type="warning" :closable="false" show-icon />
      <el-form :model="form" @submit.prevent="submit">
        <el-form-item>
          <el-input v-model="form.username" size="large" autocomplete="username" placeholder="管理员账号" :prefix-icon="User" />
        </el-form-item>
        <el-form-item>
          <el-input v-model="form.password" size="large" autocomplete="current-password" type="password" show-password placeholder="管理员密码" :prefix-icon="Lock" @keyup.enter="submit" />
        </el-form-item>
        <div v-if="error" class="error">{{ error }}</div>
        <el-button type="primary" size="large" native-type="submit" :loading="loading" :disabled="enabled !== true">登录管理台</el-button>
      </el-form>
    </section>
  </main>
</template>

<style scoped>
.login-page { display: grid; min-height: 100vh; place-items: center; padding: 24px; }
.login-panel { width: min(390px, 100%); padding: 34px 30px 30px; text-align: center; }
.mark { display: grid; width: 58px; height: 58px; margin: 0 auto 18px; place-items: center; border: 1px solid var(--line); border-radius: 16px; color: var(--primary); background: rgba(0,153,232,.12); box-shadow: 0 0 25px rgba(0,170,240,.16); font-size: 30px; }
h1 { margin: 0; color: #fff; font-size: 22px; letter-spacing: 0; }
p { margin: 8px 0 26px; color: var(--muted); font-size: 13px; }
.el-alert { margin-bottom: 18px; text-align: left; }
.el-form { display: grid; gap: 4px; }
.el-form-item { margin-bottom: 14px; }
.el-button { width: 100%; margin-top: 4px; }
.error { margin: -3px 0 10px; color: var(--danger); font-size: 13px; text-align: left; }
@media (max-width: 420px) { .login-page { padding: 14px; } .login-panel { padding: 28px 20px 24px; } }
</style>
