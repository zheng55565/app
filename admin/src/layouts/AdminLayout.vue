<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { DataAnalysis, User, Promotion, Fold, SwitchButton, Monitor, Trophy, Setting } from '@element-plus/icons-vue'

import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const route = useRoute()
const router = useRouter()
const mobileMenu = ref(false)

const nav = [
  { path: '/', label: '运营总览', icon: DataAnalysis },
  { path: '/users', label: '用户管理', icon: User },
  { path: '/advertising', label: '广告中心', icon: Promotion },
  { path: '/game-operations', label: '游戏运营', icon: Trophy },
  { path: '/platform-settings', label: '广告与模型', icon: Setting },
]

function logout() {
  auth.logout()
  router.replace('/login')
}

function unauthorized() { logout() }
onMounted(() => window.addEventListener('admin:unauthorized', unauthorized))
onBeforeUnmount(() => window.removeEventListener('admin:unauthorized', unauthorized))
</script>

<template>
  <div class="admin-shell">
    <aside class="sidebar">
      <div class="brand"><el-icon><Monitor /></el-icon><span>AI 公益管理台</span></div>
      <nav>
        <RouterLink v-for="item in nav" :key="item.path" :to="item.path" :class="{ active: route.path === item.path }">
          <el-icon><component :is="item.icon" /></el-icon><span>{{ item.label }}</span>
        </RouterLink>
      </nav>
      <button class="logout" type="button" @click="logout"><el-icon><SwitchButton /></el-icon><span>退出登录</span></button>
    </aside>

    <div class="main-area">
      <header class="topbar">
        <el-button class="menu-button" text circle aria-label="打开菜单" @click="mobileMenu = true"><el-icon><Fold /></el-icon></el-button>
        <div><span class="status-dot" />服务运行中</div>
        <div class="operator">{{ auth.username }}</div>
      </header>
      <main class="page-content"><RouterView /></main>
    </div>

    <el-drawer v-model="mobileMenu" direction="ltr" size="268px" :with-header="false" class="mobile-drawer">
      <div class="drawer-brand"><el-icon><Monitor /></el-icon>AI 公益管理台</div>
      <RouterLink v-for="item in nav" :key="item.path" :to="item.path" class="drawer-link" @click="mobileMenu = false">
        <el-icon><component :is="item.icon" /></el-icon>{{ item.label }}
      </RouterLink>
      <button class="drawer-link drawer-logout" type="button" @click="logout"><el-icon><SwitchButton /></el-icon>退出登录</button>
    </el-drawer>
  </div>
</template>

<style scoped>
.admin-shell { display: flex; min-height: 100vh; }
.sidebar { position: fixed; inset: 0 auto 0 0; z-index: 10; display: flex; flex-direction: column; width: 236px; padding: 18px 14px; border-right: 1px solid var(--line); background: rgba(5,25,55,.88); backdrop-filter: blur(18px); }
.brand, .drawer-brand { display: flex; align-items: center; gap: 10px; height: 44px; padding: 0 10px; color: #fff; font-size: 16px; font-weight: 700; }
.brand .el-icon, .drawer-brand .el-icon { color: var(--primary); font-size: 23px; filter: drop-shadow(0 0 8px rgba(0,192,249,.45)); }
nav { display: grid; gap: 6px; margin-top: 26px; }
nav a, .drawer-link, .logout { display: flex; align-items: center; gap: 11px; min-height: 44px; padding: 0 13px; border: 1px solid transparent; border-radius: 12px; color: var(--muted); font-size: 14px; transition: .2s ease; }
nav a:hover, nav a.active { color: #fff; border-color: var(--line); background: linear-gradient(135deg, rgba(0,153,232,.2), rgba(0,192,249,.08)); box-shadow: 0 0 18px rgba(0,170,240,.08); }
nav a.active .el-icon { color: var(--primary); transform: translateY(-1px); filter: drop-shadow(0 0 6px rgba(0,192,249,.45)); }
.logout { margin-top: auto; border: 0; background: transparent; cursor: pointer; }
.logout:hover { color: #fff; background: rgba(255,71,87,.1); }
.main-area { width: calc(100% - 236px); min-width: 0; margin-left: 236px; }
.topbar { position: sticky; top: 0; z-index: 8; display: flex; align-items: center; justify-content: space-between; height: 58px; padding: 0 24px; border-bottom: 1px solid var(--line); color: var(--muted); background: rgba(5,25,55,.72); backdrop-filter: blur(16px); font-size: 12px; }
.operator { color: #e6f2ff; }
.menu-button { display: none; }
.page-content { width: min(1440px, 100%); margin: 0 auto; padding: 24px; }
.drawer-brand { margin-bottom: 20px; }
.drawer-link { width: 100%; margin: 5px 0; background: transparent; }
.drawer-router-link-active { color: #fff; background: rgba(0,153,232,.16); }
.drawer-logout { border: 0; cursor: pointer; }
@media (max-width: 860px) {
  .sidebar { display: none; }
  .main-area { width: 100%; margin-left: 0; }
  .menu-button { display: inline-flex; }
  .topbar { padding: 0 14px; }
  .page-content { padding: 16px 12px 24px; }
}
</style>
