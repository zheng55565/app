export function formatDate(value?: string | null) {
  if (!value) return '-'
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? '-' : new Intl.DateTimeFormat('zh-CN', {
    month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
  }).format(date)
}

export function formatMicrounits(value: string | number | null | undefined) {
  const amount = Number(value || 0) / 1_000_000
  return amount.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 6 })
}

export function shortId(value?: string | null, length = 14) {
  if (!value) return '-'
  return value.length <= length ? value : `${value.slice(0, length)}…`
}
