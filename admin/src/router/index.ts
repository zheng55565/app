import { createRouter, createWebHistory } from 'vue-router'

import { useAuthStore } from '@/stores/auth'

const router = createRouter({
  history: createWebHistory('/admin/'),
  routes: [
    { path: '/login', name: 'login', component: () => import('@/views/LoginView.vue'), meta: { public: true } },
    {
      path: '/',
      component: () => import('@/layouts/AdminLayout.vue'),
      children: [
        { path: '', name: 'dashboard', component: () => import('@/views/DashboardView.vue') },
        { path: 'users', name: 'users', component: () => import('@/views/UsersView.vue') },
        { path: 'advertising', name: 'advertising', component: () => import('@/views/AdvertisingView.vue') },
        { path: 'game-operations', name: 'game-operations', component: () => import('@/views/GameOperationsView.vue') },
        { path: 'platform-settings', name: 'platform-settings', component: () => import('@/views/PlatformSettingsView.vue') },
      ],
    },
    { path: '/:pathMatch(.*)*', redirect: '/' },
  ],
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  if (to.meta.public) return auth.authenticated ? { name: 'dashboard' } : true
  return (await auth.restore()) ? true : { name: 'login', query: { redirect: to.fullPath } }
})

export default router
