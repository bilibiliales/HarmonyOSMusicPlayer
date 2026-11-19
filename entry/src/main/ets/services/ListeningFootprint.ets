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
 * 以给定基准 endTime 按周期递减（保留给需要相对推算的场景）。
 * 周：每期 -7 天；月：每期 -该月天数。offset = 0 返回 0。
 * 当前页面改用 periodEndTimestamp 按本地规则直接计算。
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

/**
 * 按接口约定计算周期结束时间戳（毫秒）：
 *   周 = 该周周六 0 点；月 = 该月最后一天 0 点；年 = 该年最后一天 0 点。
 * offset = 0 表示当前周期，负数为往前若干个周期。
 * 直接用本地日期推算，不依赖接口返回的 endTime，保证请求与顶部选中的周期严格对应。
 */
export function periodEndTimestamp(period: string, offset: number, now: Date = new Date()): number {
  if (period === 'week') {
    // getDay(): 周日=0…周六=6；换算成周一=0…周日=6 后定位本周一
    const mondayIndex = (now.getDay() + 6) % 7
    const monday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - mondayIndex)
    // 周六 = 周一 + 5 天，再按整周平移
    const saturday = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + 5 + offset * 7)
    return saturday.getTime()
  }
  if (period === 'month') {
    const target = new Date(now.getFullYear(), now.getMonth() + offset, 1)
    // 下个月第 0 天 = 本月最后一天
    const last = new Date(target.getFullYear(), target.getMonth() + 1, 0)
    return last.getTime()
  }
  if (period === 'year') {
    return new Date(now.getFullYear() + offset, 11, 31).getTime()
  }
  return 0
}

/** 无数据时导航条显示的周期名，与 endTime 使用同一套本地规则，保证标题与数据一致。 */
export function listeningPeriodTitle(period: string, offset: number, now: Date = new Date()): string {
  const value = periodEndTimestamp(period, offset, now)
  if (value <= 0) { return period === 'week' ? '本周' : period === 'month' ? '本月' : '今年' }
  const end = new Date(value)
  if (period === 'year') { return `${end.getFullYear()}年` }
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
