export class LyricPreferences {
  fontSize: number = 19
  horizontal: number = 0
  spacing: number = 23
  amplitude: number = 1
  /** 当前行「已高亮」的歌词色：逐字已唱过的字 / 普通歌词整行。只收 #RRGGBB。 */
  highlight: string = '#ef233c'
  /** 不在当前行的歌词色（已唱过与未到的其它行共用，层次由行透明度提供）。 */
  otherLineColor: string = 'rgba(255,255,255,0.46)'
  /** 当前行里「还没被逐字高亮」的字色。 */
  pendingColor: string = 'rgba(255,255,255,0.62)'
  offset: number = 0

  static normalize(value: LyricPreferences | undefined): LyricPreferences {
    const defaults = new LyricPreferences()
    if (!value || typeof value !== 'object') { return defaults }
    defaults.fontSize = LyricPreferences.clamp(value.fontSize, 14, 32, 19)
    defaults.horizontal = LyricPreferences.clamp(value.horizontal, -16, 60, 0)
    defaults.spacing = LyricPreferences.clamp(value.spacing, 4, 48, 23)
    defaults.amplitude = LyricPreferences.clamp(value.amplitude, 0, 2, 1)
    defaults.offset = Math.round(LyricPreferences.clamp(value.offset, -4, 4, 0) * 10) / 10
    defaults.highlight = LyricPreferences.color(value.highlight, defaults.highlight, false)
    defaults.otherLineColor = LyricPreferences.color(value.otherLineColor, defaults.otherLineColor, true)
    defaults.pendingColor = LyricPreferences.color(value.pendingColor, defaults.pendingColor, true)
    return defaults
  }

  private static clamp(value: number, min: number, max: number, fallback: number): number {
    return typeof value === 'number' && Number.isFinite(value) ? Math.max(min, Math.min(max, value)) : fallback
  }

  /** 旧存档可能没有这两个新字段；颜色支持 hex / #AARRGGBB / rgb() / rgba()。 */
  private static color(value: string | undefined, fallback: string, allowAlpha: boolean): string {
    if (!value || typeof value !== 'string') { return fallback }
    const text = value.trim()
    if (/^#[0-9a-fA-F]{6}$/.test(text)) { return text }
    if (!allowAlpha) { return fallback }
    if (/^#[0-9a-fA-F]{8}$/.test(text)) { return text }
    if (/^rgba?\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}\s*(,\s*(0|1|0?\.\d+)\s*)?\)$/.test(text)) {
      return text
    }
    return fallback
  }
}
