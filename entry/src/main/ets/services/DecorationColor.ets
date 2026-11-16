/** 颜色小工具（装扮运行时用，避免依赖 ArkUI 的 Color 对象）。 */
export class DecoColor {
  /** 是否为深色（按相对亮度）。无法解析时按 false。 */
  static isDark(color: string): boolean {
    const rgb = DecoColor.parse(color)
    if (!rgb) { return false }
    const luminance = (0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]) / 255
    return luminance < 0.5
  }

  /** 把 #rgb/#rrggbb/#aarrggbb 转成 rgba(...)，透明度 0-1。非 hex 原样返回。 */
  static alpha(color: string, alpha: number): string {
    if (!color) { return '' }
    const rgb = DecoColor.parse(color)
    if (!rgb) { return color }
    const a = Math.max(0, Math.min(1, alpha))
    return `rgba(${rgb[0]},${rgb[1]},${rgb[2]},${a})`
  }

  /** 把 hex 与背景色混合（ratio 为 color 占比）。 */
  static mix(color: string, background: string, ratio: number): string {
    const a = DecoColor.parse(color)
    const b = DecoColor.parse(background)
    if (!a || !b) { return color }
    const r = Math.max(0, Math.min(1, ratio))
    const mixValue = (x: number, y: number): number => Math.round(x * r + y * (1 - r))
    return `rgb(${mixValue(a[0], b[0])},${mixValue(a[1], b[1])},${mixValue(a[2], b[2])})`
  }

  /** 把用户填写的颜色规范成可用值：支持 #rgb / #rrggbb / #aarrggbb / rgba()。 */
  static normalize(color: string): string {
    const value = color.trim()
    if (!value) { return '' }
    if (value.startsWith('#')) {
      const body = value.substring(1)
      if (body.length === 3) {
        return `#${body[0]}${body[0]}${body[1]}${body[1]}${body[2]}${body[2]}`.toUpperCase()
      }
      if (body.length === 6 || body.length === 8) {
        return `#${body}`.toUpperCase()
      }
      return ''
    }
    if (value.startsWith('rgb')) {
      return value
    }
    return ''
  }

  private static parse(color: string): number[] | null {
    const value = color.trim()
    if (value.startsWith('#')) {
      let body = value.substring(1)
      if (body.length === 3) {
        body = `${body[0]}${body[0]}${body[1]}${body[1]}${body[2]}${body[2]}`
      }
      if (body.length === 8) {
        // #aarrggbb -> 取后 6 位
        body = body.substring(2)
      }
      if (body.length !== 6) { return null }
      const r = parseInt(body.substring(0, 2), 16)
      const g = parseInt(body.substring(2, 4), 16)
      const b = parseInt(body.substring(4, 6), 16)
      if (Number.isNaN(r) || Number.isNaN(g) || Number.isNaN(b)) { return null }
      return [r, g, b]
    }
    const match = value.match(/rgba?\(([^)]+)\)/)
    if (!match) { return null }
    const parts = match[1].split(',')
    if (parts.length < 3) { return null }
    const r = parseInt(parts[0].trim(), 10)
    const g = parseInt(parts[1].trim(), 10)
    const b = parseInt(parts[2].trim(), 10)
    if (Number.isNaN(r) || Number.isNaN(g) || Number.isNaN(b)) { return null }
    return [r, g, b]
  }
}
