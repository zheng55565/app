import { vi } from 'vitest'

function memoryStorage(): Storage {
  const values = new Map<string, string>()
  return {
    get length() { return values.size },
    clear: () => values.clear(),
    getItem: (key) => values.get(key) ?? null,
    key: (index) => [...values.keys()][index] ?? null,
    removeItem: (key) => { values.delete(key) },
    setItem: (key, value) => { values.set(key, String(value)) },
  }
}

Object.defineProperty(globalThis, 'localStorage', { configurable: true, value: memoryStorage() })
Object.defineProperty(globalThis, 'sessionStorage', { configurable: true, value: memoryStorage() })

if (!globalThis.crypto.randomUUID) {
  Object.defineProperty(globalThis.crypto, 'randomUUID', {
    value: vi.fn(() => '4f0f55b5-2e87-4ffd-86fa-2391b4775046'),
  })
}
