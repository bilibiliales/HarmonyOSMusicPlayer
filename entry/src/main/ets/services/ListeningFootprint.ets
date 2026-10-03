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

function parseDay(value: string): Date | undefined {
  const match = /^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:$|[ T])/.exec(value)
  if (!match) { return undefined }
  const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
  return date.getFullYear() === Number(match[1]) && date.getMonth() === Number(match[2]) - 1 &&
    date.getDate() === Number(match[3]) ? date : undefined
}

export function buildListeningPeriod(report: ListenReportData, monthly: boolean, now: Date = new Date()): ListeningPeriod {
  const details = report.listenTimeDistributionBlock?.durationDetails || []
  let anchor = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  if (report.startTime && report.startTime > 0) {
    const start = new Date(report.startTime < 100000000000 ? report.startTime * 1000 : report.startTime)
    if (Number.isFinite(start.getTime())) { anchor = start }
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
    new Date(anchor.getFullYear(), anchor.getMonth(), anchor.getDate() - (report.startTime ? 0 : anchor.getDay()))
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
      const parsed = parseDay(item.period)
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
