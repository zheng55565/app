import { request } from './request'

export interface PageResult<T> { items: T[]; total: number; page: number; page_size: number }

export interface Overview {
  users_total: number
  users_active: number
  ad_tasks_today: number
  rewarded_today: number
  reward_microunits_today: number
  callback_failures_today: number
  impressions_today: number
  clicks_today: number
  game_rounds_today: number
  generated_at: string
}

export interface AdminUser {
  id: string
  username: string | null
  linuxdo_username: string | null
  status: 'active' | 'banned'
  station_user_id: string | null
  balance_microunits: string
  game_balance_micropoints: string
  created_at: string
  last_login_at: string | null
}

export interface AdTask {
  id: string
  user_id: string
  username: string | null
  ad_platform: string
  ad_unit_id: string
  reward_amount_microunits: string
  status: string
  client_transaction_id: string | null
  provider_transaction_id: string | null
  created_at: string
  rewarded_at: string | null
  expires_at: string | null
}

export interface CallbackAudit {
  id: string
  provider: string
  transaction_id: string | null
  task_token: string | null
  placement_id: string | null
  signature_present: boolean
  signature_valid: boolean | null
  http_status: number | null
  outcome: string | null
  received_at: string
  completed_at: string | null
}

export interface AdClientEvent {
  id: string
  event_id: string
  creative_id: string | null
  placement: string
  trigger_name: string
  event_type: 'impression' | 'click' | 'close' | 'load_failed'
  session_id: string | null
  metadata: Record<string, unknown>
  occurred_at: string | null
  created_at: string
}

export interface GameSettings {
  rps_enabled: boolean
  mine_enabled: boolean
  battle_enabled: boolean
  match3_enabled: boolean
  rps_payout_basis_points: number
  mine_liability_basis_points: number
  mine_fee_basis_points: number
  battle_fee_basis_points: number
  battle_min_eliminated: number
  battle_max_eliminated: number
  battle_opponent_min_count: number
  battle_opponent_max_count: number
  battle_opponent_min_stake: number
  battle_opponent_max_stake: number
  match3_clear_reward_points: number
  match3_chest_again_basis_points: number
  match3_chest_1_basis_points: number
  match3_chest_5_basis_points: number
  match3_chest_10_basis_points: number
}

export interface AdSettings {
  rewarded_enabled: boolean
  reward_microunits: number
  daily_max: number
  daily_reward_max_microunits: number
  device_daily_max: number
  device_reward_max_microunits: number
  ip_daily_max: number
  ip_reward_max_microunits: number
}

export interface AiSettings { enabled: boolean; image_models: string[] }
export interface RuntimeSettings { game: GameSettings; ad: AdSettings; ai: AiSettings }

export interface GameResult {
  id: string
  user_id: string
  username: string
  game_type: string
  game_id: string
  mode: string
  result: string
  stake_micropoints: string
  payout_micropoints: string
  fee_micropoints: string
  net_profit_micropoints: string
  detail: Record<string, unknown>
  created_at: string
}

export interface SettingAudit {
  id: string
  username: string
  detail: string
  ip_address: string | null
  created_at: string
}

function qs(params: Record<string, string | number | undefined>) {
  const search = new URLSearchParams()
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== '') search.set(key, String(value))
  })
  return search.toString()
}

export const adminApi = {
  status: () => request<{ enabled: boolean }>('/api/admin/auth/status', { auth: false }),
  login: (username: string, password: string) =>
    request<{ token: string; admin: { username: string } }>('/api/admin/auth/login', {
      method: 'POST', auth: false, body: { username, password },
    }),
  me: () => request<{ username: string; role: string }>('/api/admin/me'),
  overview: () => request<Overview>('/api/admin/overview'),
  users: (params: Record<string, string | number | undefined>) =>
    request<PageResult<AdminUser>>(`/api/admin/users?${qs(params)}`),
  tasks: (params: Record<string, string | number | undefined>) =>
    request<PageResult<AdTask>>(`/api/admin/ad-tasks?${qs(params)}`),
  callbacks: (params: Record<string, string | number | undefined>) =>
    request<PageResult<CallbackAudit>>(`/api/admin/ad-callbacks?${qs(params)}`),
  events: (params: Record<string, string | number | undefined>) =>
    request<PageResult<AdClientEvent>>(`/api/admin/ad-events?${qs(params)}`),
  settings: () => request<RuntimeSettings>('/api/admin/settings'),
  updateSettings: <T>(namespace: 'game' | 'ad' | 'ai', value: T) =>
    request<{ namespace: string; value: T }>(`/api/admin/settings/${namespace}`, {
      method: 'PUT', body: value,
    }),
  gameResults: (params: Record<string, string | number | undefined>) =>
    request<PageResult<GameResult>>(`/api/admin/game-results?${qs(params)}`),
  settingAudits: (params: Record<string, string | number | undefined>) =>
    request<PageResult<SettingAudit>>(`/api/admin/setting-audits?${qs(params)}`),
}
