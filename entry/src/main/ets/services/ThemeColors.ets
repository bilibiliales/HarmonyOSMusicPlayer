import { SkinService } from './SkinService'
import { ThemeMode, ThemeService } from './ThemeService'

/**
 * TC（Theme Colors）—— 全 App 唯一取色入口。
 *
 * 解析规则（优先级从高到低）：
 *   1. 装扮皮肤覆盖（SkinService，固定色，深浅色切换不影响）；
 *   2. 深浅色双值表（本文件，按 ThemeService.isDark() 运行时手动取值）。
 *
 * 为什么不直接用 $r('app.color.*') 资源跟随系统：
 *   资源切换依赖系统/模拟器对 setColorMode 的支持，预览器与部分设备上
 *   切换后界面不会立即刷新。手动解析 + skinVersion 广播重渲染是全端可靠的。
 *   （resources/base|dark/element/color.json 仍保留，用于启动窗与系统组件。）
 *
 * 使用约定（新页面零额外定义即可同时支持主题与皮肤）：
 *   - 页面/组件内取色一律 TC.xxx()，禁止直接写 $r('app.color.*') 或硬编码 hex；
 *   - 压在图片/视频上的文字用 TC.textOnMedia*()（常白，不随主题翻转）；
 *   - 品牌特有色（VIP 金等）不在语义层，继续内联；
 *   - 需要在主题/皮肤变化时原地刷新的组件，加一行
 *     @StorageProp('skinVersion') skinVersionObs: number = 0
 *     （ThemeService 与 SkinService 在变化时都会递增该值）。
 */

/** 浅色值表（与 resources/base/element/color.json 保持一致）。 */
const LIGHT: Record<string, string> = {
  'page_background': '#f4f4f7',
  'nav_background': '#f4f4f7',
  'surface_card': '#ffffff',
  'surface_card_alt': '#fbfbfd',
  'surface_inset': '#eeeef2',
  'surface_raised': '#e6e6ec',
  'chip_background': '#ecebf1',
  'sheet_background': '#ffffff',
  'text_primary': '#111114',
  'text_body': '#2b2b31',
  'text_secondary': '#6b6b75',
  'text_tertiary': '#8c8c96',
  'text_quaternary': '#a0a0a8',
  'text_on_accent': '#ffffff',
  'text_on_media': '#ffffff',
  'text_on_media_secondary': '#CCFFFFFF',
  'text_on_media_tertiary': '#99FFFFFF',
  'accent': '#ef233c',
  'accent_soft': '#e01e35',
  'accent_container': '#FCEBEC',
  'divider': '#e3e3e8',
  'border_subtle': '#e8e8ee',
  'scrim': '#000000',
  'header_scrim_top': '#B8FFFFFF',
  'header_scrim_mid': '#E8F4F4F7'
}

/** 深色值表（与 resources/dark/element/color.json 保持一致）。 */
const DARK: Record<string, string> = {
  'page_background': '#121215',
  'nav_background': '#121215',
  'surface_card': '#1b1b20',
  'surface_card_alt': '#1f1f24',
  'surface_inset': '#24242a',
  'surface_raised': '#2a2a30',
  'chip_background': '#29292f',
  'sheet_background': '#1b1b20',
  'text_primary': '#ffffff',
  'text_body': '#ededf0',
  'text_secondary': '#92929a',
  'text_tertiary': '#77777f',
  'text_quaternary': '#66666e',
  'text_on_accent': '#ffffff',
  'text_on_media': '#ffffff',
  'text_on_media_secondary': '#CCFFFFFF',
  'text_on_media_tertiary': '#99FFFFFF',
  'accent': '#ef233c',
  'accent_soft': '#ff6577',
  'accent_container': '#2B2024',
  'divider': '#303038',
  'border_subtle': '#2a2a30',
  'scrim': '#000000',
  'header_scrim_top': '#38121215',
  'header_scrim_mid': '#B3121215'
}

export class TC {
  /**
   * 取色：皮肤覆盖 > 手动双值表（按有效主题） > $r 资源回退。
   * 预览器单页预览不走 Ability 生命周期（ThemeService 未初始化），
   * 此时若用户未显式选过深浅色（跟随系统），回落 $r 由预览器自身的
   * colorMode 决定；一旦显式选择（含预览器里手动切换），立即走手动表。
   */
  private static pick(token: string, fallback: ResourceColor): ResourceColor {
    const skin: string | undefined = SkinService.colorOverride(token)
    if (skin !== undefined && skin.length > 0) {
      return skin
    }
    if (!ThemeService.isReady() && ThemeService.getMode() === ThemeMode.SYSTEM) {
      return fallback
    }
    return ThemeService.isDark() ? DARK[token] : LIGHT[token]
  }

  /** 页面底色（最底层背景）。 */
  static pageBackground(): ResourceColor { return TC.pick('page_background', $r('app.color.page_background')) }

  /** 底部导航 / 顶栏背景。 */
  static navBackground(): ResourceColor { return TC.pick('nav_background', $r('app.color.nav_background')) }

  /** 一级卡片背景。 */
  static surfaceCard(): ResourceColor { return TC.pick('surface_card', $r('app.color.surface_card')) }

  /** 一级卡片的相邻层次（略深/略浅的卡片）。 */
  static surfaceCardAlt(): ResourceColor { return TC.pick('surface_card_alt', $r('app.color.surface_card_alt')) }

  /** 内陷区域（搜索框、输入框、槽位）。 */
  static surfaceInset(): ResourceColor { return TC.pick('surface_inset', $r('app.color.surface_inset')) }

  /** 浮起层（弹层内卡片、按压态）。 */
  static surfaceRaised(): ResourceColor { return TC.pick('surface_raised', $r('app.color.surface_raised')) }

  /** 小胶囊 / 标签底。 */
  static chipBackground(): ResourceColor { return TC.pick('chip_background', $r('app.color.chip_background')) }

  /** 半模态 / 弹窗底板。 */
  static sheetBackground(): ResourceColor { return TC.pick('sheet_background', $r('app.color.sheet_background')) }

  /** 主文字（标题）。 */
  static textPrimary(): ResourceColor { return TC.pick('text_primary', $r('app.color.text_primary')) }

  /** 正文文字。 */
  static textBody(): ResourceColor { return TC.pick('text_body', $r('app.color.text_body')) }

  /** 次级说明文字。 */
  static textSecondary(): ResourceColor { return TC.pick('text_secondary', $r('app.color.text_secondary')) }

  /** 辅助文字（时间、角标）。 */
  static textTertiary(): ResourceColor { return TC.pick('text_tertiary', $r('app.color.text_tertiary')) }

  /** 最弱文字（占位、禁用）。 */
  static textQuaternary(): ResourceColor { return TC.pick('text_quaternary', $r('app.color.text_quaternary')) }

  /** 压在主题色上的文字（常白，深浅色一致）。 */
  static textOnAccent(): ResourceColor { return TC.pick('text_on_accent', $r('app.color.text_on_accent')) }

  /** 压在图片/视频上的文字（常白，不随主题翻转）。 */
  static textOnMedia(): ResourceColor { return TC.pick('text_on_media', $r('app.color.text_on_media')) }

  /** 图片上次级文字（常白 80%）。 */
  static textOnMediaSecondary(): ResourceColor { return TC.pick('text_on_media_secondary', $r('app.color.text_on_media_secondary')) }

  /** 图片上辅助文字（常白 60%）。 */
  static textOnMediaTertiary(): ResourceColor { return TC.pick('text_on_media_tertiary', $r('app.color.text_on_media_tertiary')) }

  /** 主题色 / 突出色（品牌红）。 */
  static accent(): ResourceColor { return TC.pick('accent', $r('app.color.accent')) }

  /** 主题色的弱化形态（浅红底、描边）。 */
  static accentSoft(): ResourceColor { return TC.pick('accent_soft', $r('app.color.accent_soft')) }

  /** 承载 accentSoft 文字的容器底（深色红棕 / 浅色浅粉），用于重试按钮、提醒条、徽标等。 */
  static accentContainer(): ResourceColor { return TC.pick('accent_container', $r('app.color.accent_container')) }

  /** 分割线。 */
  static divider(): ResourceColor { return TC.pick('divider', $r('app.color.divider')) }

  /** 细描边。 */
  static borderSubtle(): ResourceColor { return TC.pick('border_subtle', $r('app.color.border_subtle')) }

  /** 全屏遮罩。 */
  static scrim(): ResourceColor { return TC.pick('scrim', $r('app.color.scrim')) }

  /** 头图蒙版·上（头图淡入页面底色的起点）。 */
  static headerScrimTop(): ResourceColor { return TC.pick('header_scrim_top', $r('app.color.header_scrim_top')) }

  /** 头图蒙版·中。 */
  static headerScrimMid(): ResourceColor { return TC.pick('header_scrim_mid', $r('app.color.header_scrim_mid')) }

  /**
   * 仅接受 string | Resource 的组件属性（如 showActionMenu 的按钮文字色）取主题色。
   */
  static accentMenu(): string | Resource {
    // 不能复用 pick()：ResourceColor 含 Color/number 分支，
    // 而 showActionMenu 的按钮色只接受 string | Resource，类型必须精确。
    const skin: string | undefined = SkinService.colorOverride('accent')
    if (skin !== undefined && skin.length > 0) {
      return skin
    }
    if (ThemeService.isReady() || ThemeService.getMode() !== ThemeMode.SYSTEM) {
      const value: string = ThemeService.isDark() ? DARK['accent'] : LIGHT['accent']
      if (value !== undefined && value.length > 0) {
        return value
      }
    }
    return $r('app.color.accent')
  }
}
