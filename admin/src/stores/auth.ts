import { computed, ref } from 'vue'
import { defineStore } from 'pinia'

import { adminApi } from '@/api/admin'
import { ADMIN_TOKEN_KEY } from '@/api/request'

export const useAuthStore = defineStore('auth', () => {
  const token = ref(sessionStorage.getItem(ADMIN_TOKEN_KEY) || '')
  const username = ref('')
  const initialized = ref(false)
  const authenticated = computed(() => Boolean(token.value))

  async function login(account: string, password: string) {
    const result = await adminApi.login(account, password)
    token.value = result.token
    username.value = result.admin.username
    sessionStorage.setItem(ADMIN_TOKEN_KEY, result.token)
  }

  async function restore() {
    if (initialized.value) return authenticated.value
    initialized.value = true
    if (!token.value) return false
    try {
      const me = await adminApi.me()
      username.value = me.username
      return true
    } catch {
      logout()
      return false
    }
  }

  function logout() {
    token.value = ''
    username.value = ''
    sessionStorage.removeItem(ADMIN_TOKEN_KEY)
  }

  return { token, username, authenticated, initialized, login, restore, logout }
})
