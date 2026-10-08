interface TimedSystemLine { time: number; text: string }

// The system parser accepts LRC, not NetEase's JSON credit lines or YRC word tags.
export class SystemLrc {
  static normalize(source: string): string {
    const lines: TimedSystemLine[] = []
    const offsetMatch = /\[offset:([+-]?\d+)\]/i.exec(source)
    const offset = offsetMatch ? Number(offsetMatch[1]) : 0
    for (const raw of source.replace(/\r/g, '').split('\n')) {
      const line = raw.trim()
      const stamps = line.match(/\[\d+:\d{2}(?:[.:]\d{1,3})?\]/g)
      if (!stamps || !/^\[\d+:/.test(line)) { continue }
      const text = line.replace(/^(?:\[\d+:\d{2}(?:[.:]\d{1,3})?\])+/, '')
        .replace(/\(\d+,\d+,\d+\)/g, '').trim()
      for (const stamp of stamps) {
        const match = /\[(\d+):(\d{2})(?:[.:](\d{1,3}))?\]/.exec(stamp)
        if (!match || Number(match[2]) >= 60) { continue }
        const fraction = (match[3] || '').padEnd(3, '0')
        const time = Math.max(0, Number(match[1]) * 60000 + Number(match[2]) * 1000 + Number(fraction) + offset)
        lines.push({ time: time, text: text })
      }
    }
    return lines.sort((a: TimedSystemLine, b: TimedSystemLine) => a.time - b.time)
      .map((line: TimedSystemLine) => {
        const minutes = Math.floor(line.time / 60000).toString().padStart(2, '0')
        const seconds = Math.floor(line.time % 60000 / 1000).toString().padStart(2, '0')
        const hundredths = Math.floor(line.time % 1000 / 10).toString().padStart(2, '0')
        return '[' + minutes + ':' + seconds + '.' + hundredths + ']' + line.text
      }).join('\n')
  }
}
