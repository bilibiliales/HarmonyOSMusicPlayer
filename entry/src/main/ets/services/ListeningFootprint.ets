import { ListenReportData } from '../models/api'

export interface ListeningDay {
  key: string
  day: number
  weekday: string
  minutes: number
  reported: boolean
  future: boolean
}

export interface ListeningPeriod {
  days: ListeningDay[]
  rows: ListeningDay[][]
  title: string
  totalMinutes: number
  listenedDays: number
  axisMinutes: number
}

export function listeningDateKey(date: Date): string {
  return `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')}`
}

function parseDay(value: string | number, anchor?: Date): Date | undefined {
  const text = String(value).trim()
  let match = /^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:$|[ T])/.exec(text)
  if (!match) { match = /^(\d{4})(\d{2})(\d{2})$/.exec(text) }
  if (match) {
    const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
    return date.getFullYear() === Number(match[1]) && date.getMonth() === Number(match[2]) - 1 &&
      date.getDate() === Number(match[3]) ? date : undefined
  }
  if (/^\d{10,13}$/.test(text)) {
    const date = new Date(Number(text) < 100000000000 ? Number(text) * 1000 : Number(text))
    return Number.isFinite(date.getTime()) ? date : undefined
  }
  if (anchor) {
    const short = /^(?:(\d{1,2})[-/.])?(\d{1,2})$/.exec(text)
    if (short) {
      const month = short[1] ? Number(short[1]) - 1 : anchor.getMonth()
      const date = new Date(anchor.getFullYear(), month, Number(short[2]))
      if (date.getMonth() === month && date.getDate() === Number(short[2])) { return date }
    }
  }
  return undefined
}

const WEEK_MS: number = 7 * 24 * 60 * 60 * 1000
const DAY_MS: number = 24 * 60 * 60 * 1000

/** 接口的 startTime / endTime 可能是毫秒、秒或日期串，统一成毫秒。 */
export function listeningTimeValue(raw: number | string | undefined): number {
  if (raw === undefined) { return 0 }
  let value = 0
  if (typeof raw === 'number') {
    value = raw
  } else {
    const text = String(raw).trim()
    if (/^\d{10,13}$/.test(text)) {
      value = Number(text)
    } else {
      const date = parseDay(text)
      return date ? date.getTime() : 0
    }
  }
  if (value <= 0) { return 0 }
  return value < 100000000000 ? value * 1000 : value
}

/**
 * 以「不带 endTime 请求返回的 endTime」为唯一基准递减（不要再按本地今天推算）。
 * 周：每期 -7 天（周六 0 点）；月：每期 -该月天数（月末 0 点）。
 * offset = 0 返回 0，表示不传 endTime，即接口默认的本周 / 本月。
 * 因为永远是基准减去正数，不可能产生比基准更新的日期。
 */
export function listeningPeriodEnd(period: string, baseEnd: number, offset: number): number {
  if (offset === 0 || baseEnd <= 0) { return 0 }
  if (period === 'week') { return baseEnd + offset * WEEK_MS }
  let end = baseEnd
  const step = offset < 0 ? -1 : 1
  const count = Math.abs(offset)
  for (let i = 0; i < count; i++) {
    const d = new Date(end)
    const days = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate()
    end += step * days * DAY_MS
  }
  return end
}

/** 无数据时导航条显示的周期名，同样从接口基准推导。 */
export function listeningPeriodTitle(period: string, baseEnd: number, offset: number): string {
  if (baseEnd <= 0) { return period === 'week' ? '本周' : '本月' }
  const value = listeningPeriodEnd(period, baseEnd, offset)
  const end = new Date(value > 0 ? value : baseEnd)
  if (period === 'month') { return `${end.getFullYear()}年${end.getMonth() + 1}月` }
  const start = new Date(end.getFullYear(), end.getMonth(), end.getDate() - 6)
  return `${start.getFullYear()}.${start.getMonth() + 1}.${start.getDate()} — ${end.getMonth() + 1}.${end.getDate()}`
}

/** 卡片文案用：本周 / 上周 / N 周前。 */
export function listeningPeriodOffsetLabel(period: string, offset: number): string {
  if (period === 'week') {
    if (offset === 0) { return '本周' }
    if (offset === -1) { return '上周' }
    return `${-offset} 周前`
  }
  if (offset === 0) { return '本月' }
  if (offset === -1) { return '上月' }
  return `${-offset} 个月前`
}

export function buildListeningPeriod(report: ListenReportData, monthly: boolean, now: Date = new Date(), periodStart?: Date): ListeningPeriod {
  const details = report.listenTimeDistributionBlock?.durationDetails || []
  let anchor = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  let aligned = periodStart !== undefined
  const reportStart = report.startTime ? parseDay(report.startTime) : undefined
  if (periodStart) {
    anchor = new Date(periodStart.getFullYear(), periodStart.getMonth(), periodStart.getDate())
  } else if (reportStart) {
    anchor = reportStart
    aligned = true
  } else {
    const dates: Date[] = []
    for (const detail of details) {
      const date = parseDay(detail.period)
      if (date) { dates.push(date) }
    }
    dates.sort((a: Date, b: Date) => a.getTime() - b.getTime())
    if (dates.length) { anchor = dates[0] }
  }
  const start = monthly ? new Date(anchor.getFullYear(), anchor.getMonth(), 1) :
    new Date(anchor.getFullYear(), anchor.getMonth(), anchor.getDate() - (aligned ? 0 : anchor.getDay()))
  const count = monthly ? new Date(start.getFullYear(), start.getMonth() + 1, 0).getDate() : 7
  const weekdays: string[] = ['日', '一', '二', '三', '四', '五', '六']
  const days: ListeningDay[] = []
  let total = 0
  let listened = 0
  let max = 0
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
  for (let index = 0; index < count; index++) {
    const date = new Date(start.getFullYear(), start.getMonth(), start.getDate() + index)
    const key = listeningDateKey(date)
    const detail = details.find((item) => {
      const parsed = parseDay(item.period, start)
      return parsed !== undefined && listeningDateKey(parsed) === key
    })
    const future = date.getTime() > today
    const reported = !future && detail !== undefined && Number.isFinite(detail.duration) && detail.duration >= 0
    const minutes = reported && detail ? detail.duration : 0
    days.push({ key: key, day: date.getDate(), weekday: weekdays[date.getDay()], minutes: minutes,
      reported: reported, future: future })
    total += minutes
    if (minutes > 0) { listened++ }
    max = Math.max(max, minutes)
  }
  const rows: ListeningDay[][] = []
  if (monthly) {
    const cells: ListeningDay[] = []
    const offset = start.getDay()
    const length = Math.ceil((offset + count) / 7) * 7
    for (let index = 0; index < length; index++) {
      cells.push(index >= offset && index < offset + count ? days[index - offset] :
        { key: `empty-${index}`, day: 0, weekday: '', minutes: 0, reported: false, future: false })
    }
    for (let index = 0; index < cells.length; index += 7) { rows.push(cells.slice(index, index + 7)) }
  }
  const duration = report.listenTimeBlock?.playDuration ?? report.listenTimeDistributionBlock?.playDuration
  const end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 6)
  return {
    days: days, rows: rows,
    title: monthly ? `${start.getFullYear()}年${start.getMonth() + 1}月` :
      `${start.getFullYear()}.${start.getMonth() + 1}.${start.getDate()} — ${end.getMonth() + 1}.${end.getDate()}`,
    totalMinutes: duration !== undefined && Number.isFinite(duration) && duration >= 0 ? duration : total,
    listenedDays: listened, axisMinutes: Math.max(60, Math.ceil(max / 60) * 60)
  }
}

export function listeningDayBackground(day: ListeningDay): string {
  if (!day.reported || day.minutes <= 0) { return 'transparent' }
  return day.minutes < 60 ? 'rgba(239,35,60,0.22)' : '#ef233c'
}

export function listeningDayColor(day: ListeningDay): string {
  if (day.future) { return '#484850' }
  if (!day.reported || day.minutes <= 0) { return '#77777f' }
  return day.minutes < 60 ? '#ff6577' : '#ffffff'
}
