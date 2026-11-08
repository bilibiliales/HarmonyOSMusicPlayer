import { common, ConfigurationConstant } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'

export class ThemeMode {
  static readonly SYSTEM: string = 'system'
  static readonly LIGHT: string = 'light'
  static readonly DARK: string = 'dark'
}

const STORE_NAME: string = 'theme_settings'
const KEY_MODE: string = 'theme_mode'
const AS_MODE: string = 'themeMode'
const AS_SYSTEM_DARK: string = 'systemDarkMode'
const AS_CURRENT: string = 'currentColorMode'

export class ThemeService {
  private static context: common.Context | undefined = undefined
  private static mode: string = ThemeMode.SYSTEM
  private static systemDark: boolean = false
  private static listeners: Array<(isDark: boolean) => void> = []

  /** 同步读取持久化的模式并在首帧前设置 colorMode，避免启动闪白/闪黑。 */
  static init(context: common.Context): void {
    ThemeService.context = context
    let saved: string = ThemeMode.SYSTEM
    try {
      const store = preferences.getPreferencesSync(context, { name: STORE_NAME })
      saved = store.getSync(KEY_MODE, ThemeMode.SYSTEM) as string
    } catch (_error) {
      saved = ThemeMode.SYSTEM
    }
    ThemeService.mode = ThemeService.parse(saved)
    // 用应用上下文读取当前系统色彩模式，作为「跟随系统」时的初始值
    try {
      ThemeService.systemDark =
        context.getApplicationContext().config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    } catch (_error) {
      ThemeService.systemDark = false
    }
    ThemeService.publish()
    ThemeService.apply()
  }

  private static parse(value: string): string {
    if (value === ThemeMode.LIGHT) { return ThemeMode.LIGHT }
    if (value === ThemeMode.DARK) { return ThemeMode.DARK }
    return ThemeMode.SYSTEM
  }

  private static publish(): void {
    AppStorage.setOrCreate<string>(AS_MODE, ThemeService.mode)
    AppStorage.setOrCreate<boolean>(AS_SYSTEM_DARK, ThemeService.systemDark)
    let effectiveDark: boolean = ThemeService.systemDark
    if (ThemeService.mode === ThemeMode.DARK) { effectiveDark = true }
    if (ThemeService.mode === ThemeMode.LIGHT) { effectiveDark = false }
    AppStorage.setOrCreate<number>(AS_CURRENT, effectiveDark
      ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT)
    AppStorage.setOrCreate<boolean>('themeIsDark', effectiveDark)
    // 通知监听方（如状态栏图标颜色），让沉浸式窗口跟随有效模式
    ThemeService.listeners.forEach((fn: (isDark: boolean) => void) => {
      try { fn(effectiveDark) } catch (_error) { /* 单个监听失败不影响其余 */ }
    })
  }

  /** 注册「有效模式变化」监听（EntryAbility 用于同步状态栏图标颜色）。 */
  static addModeListener(fn: (isDark: boolean) => void): void {
    ThemeService.listeners.push(fn)
  }

  /** 把用户选择落到系统层，$r('app.color.*') 会自动切换到对应资源。 */
  static apply(): void {
    if (!ThemeService.context) { return }
    let target: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
    if (ThemeService.mode === ThemeMode.LIGHT) {
      target = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
    } else if (ThemeService.mode === ThemeMode.DARK) {
      target = ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    }
    try {
      ThemeService.context.getApplicationContext().setColorMode(target)
    } catch (_error) {
      // 部分设备/模拟器不支持动态切换，降级为忽略
    }
  }

  static getMode(): string {
    return ThemeService.mode
  }

  static getSavedMode(): string {
    return ThemeService.mode
  }

  static async setMode(mode: string): Promise<void> {
    ThemeService.mode = mode
    ThemeService.publish()
    ThemeService.apply()
    if (!ThemeService.context) { return }
    const store = await preferences.getPreferences(ThemeService.context, STORE_NAME)
    await store.put(KEY_MODE, mode)
    await store.flush()
  }

  /** 仅在「跟随系统」时，系统切换才影响应用；手动模式下保持用户选择。 */
  static onSystemColorModeChange(colorMode: ConfigurationConstant.ColorMode): void {
    const dark = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    if (ThemeService.systemDark === dark) { return }
    ThemeService.systemDark = dark
    ThemeService.publish()
    if (ThemeService.mode === ThemeMode.SYSTEM) {
      // NOT_SET 状态下系统已自行切换资源，但仍需让监听方拿到最新值
      AppStorage.setOrCreate<number>(AS_CURRENT, colorMode)
    }
  }

  static isDark(): boolean {
    if (ThemeService.mode === ThemeMode.DARK) { return true }
    if (ThemeService.mode === ThemeMode.LIGHT) { return false }
    return ThemeService.systemDark
  }

  /** 状态栏/导航栏图标颜色跟随主题，供页面沉浸式布局使用。 */
  static statusBarContent(): string {
    return ThemeService.isDark() ? '#ffffff' : '#111114'
  }
}
