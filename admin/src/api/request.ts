export const ADMIN_TOKEN_KEY = 'gongyi_admin_token'

export class ApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly code?: string | number,
  ) {
    super(message)
  }
}

export interface RequestOptions extends Omit<RequestInit, 'body'> {
  body?: unknown
  auth?: boolean
  timeoutMs?: number
}

export async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const controller = new AbortController()
  const timeout = window.setTimeout(() => controller.abort(), options.timeoutMs ?? 10000)
  const headers = new Headers(options.headers)
  headers.set('Accept', 'application/json')
  if (options.body !== undefined) headers.set('Content-Type', 'application/json')
  if (options.auth !== false) {
    const token = sessionStorage.getItem(ADMIN_TOKEN_KEY)
    if (token) headers.set('Authorization', `Bearer ${token}`)
  }
  try {
    const response = await fetch(path, {
      ...options,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
      headers,
      signal: controller.signal,
    })
    const data = await response.json().catch(() => ({}))
    if (!response.ok) {
      if (response.status === 401 && options.auth !== false) {
        sessionStorage.removeItem(ADMIN_TOKEN_KEY)
        window.dispatchEvent(new CustomEvent('admin:unauthorized'))
      }
      throw new ApiError(data.message || `请求失败（${response.status}）`, response.status, data.code)
    }
    return data as T
  } catch (error) {
    if (error instanceof ApiError) throw error
    if ((error as Error)?.name === 'AbortError') throw new ApiError('请求超时', 408)
    throw new ApiError('网络连接失败', 0)
  } finally {
    window.clearTimeout(timeout)
  }
}
