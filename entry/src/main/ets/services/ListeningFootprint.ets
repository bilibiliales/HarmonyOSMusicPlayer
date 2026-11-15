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

/**
 * /listen/data/report 的 endTime（毫秒时间戳）。
 * 接口约定：周 = 该周周六 0 点，月 = 该月最后一天 0 点；不传即本周 / 本月。
 * offset = 0 表示当前周期（返回 0，即不传 endTime），负数表示往前翻。
 */
export function listeningPeriodEnd(period: string, offset: number, now: Date = new Date()): number {
  if (offset === 0) { return 0 }
  if (period === 'week') {
    // 周报以周日为起点，周六为该周的标识日
    const sunday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - now.getDay())
    const saturday = new Date(sunday.getFullYear(), sunday.getMonth(), sunday.getDate() + 6)
    return saturday.getTime() + offset * WEEK_MS
  }
  // new Date(y, m + 1 + offset, 0) 即目标月份的最后一天 0 点，自动处理跨年与闰年
  return new Date(now.getFullYear(), now.getMonth() + 1 + offset, 0).getTime()
}

/** 周期第一天（周日 / 月初），用于历史周期的日期网格与标题。 */
export function listeningPeriodStart(period: string, offset: number, now: Date = new Date()): Date {
  const end = listeningPeriodEnd(period, offset, now)
  if (end > 0) {
    const d = new Date(end)
    return period === 'week' ? new Date(d.getFullYear(), d.getMonth(), d.getDate() - 6) :
      new Date(d.getFullYear(), d.getMonth(), 1)
  }
  return period === 'week' ? new Date(now.getFullYear(), now.getMonth(), now.getDate() - now.getDay()) :
    new Date(now.getFullYear(), now.getMonth(), 1)
}

/** 无数据时导航条显示的周期名。 */
export function listeningPeriodTitle(period: string, offset: number, now: Date = new Date()): string {
  const start = listeningPeriodStart(period, offset, now)
  if (period === 'month') { return `${start.getFullYear()}年${start.getMonth() + 1}月` }
  const end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 6)
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
