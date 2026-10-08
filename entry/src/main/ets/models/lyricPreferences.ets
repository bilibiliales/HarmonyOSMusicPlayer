export class LyricPreferences {
  fontSize: number = 19
  horizontal: number = 0
  spacing: number = 23
  amplitude: number = 1
  highlight: string = '#ef233c'
  offset: number = 0

  static normalize(value: LyricPreferences | undefined): LyricPreferences {
    const defaults = new LyricPreferences()
    if (!value || typeof value !== 'object') { return defaults }
    defaults.fontSize = LyricPreferences.clamp(value.fontSize, 14, 32, 19)
    defaults.horizontal = LyricPreferences.clamp(value.horizontal, -16, 60, 0)
    defaults.spacing = LyricPreferences.clamp(value.spacing, 4, 48, 23)
    defaults.amplitude = LyricPreferences.clamp(value.amplitude, 0, 2, 1)
    defaults.offset = Math.round(LyricPreferences.clamp(value.offset, -4, 4, 0) * 10) / 10
    if (typeof value.highlight === 'string' && /^#[0-9a-fA-F]{6}$/.test(value.highlight)) {
      defaults.highlight = value.highlight
    }
    return defaults
  }

  private static clamp(value: number, min: number, max: number, fallback: number): number {
    return typeof value === 'number' && Number.isFinite(value) ? Math.max(min, Math.min(max, value)) : fallback
  }
}
