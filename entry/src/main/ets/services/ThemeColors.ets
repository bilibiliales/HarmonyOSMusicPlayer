import { SkinService } from './SkinService'

/**
 * TC（Theme Colors）—— 全 App 唯一取色入口。
 *
 * 解析规则（优先级从高到低）：
 *   1. 装扮皮肤覆盖（SkinService，固定色，深浅色切换不影响）；
 *   2. 深浅色主题资源（resources/base|dark/element/color.json，跟随 colorMode 自动切换）。
 *
 * 使用约定（新页面零额外定义即可同时支持主题与皮肤）：
 *   - 页面/组件内取色一律 TC.xxx()，禁止直接写 $r('app.color.*') 或硬编码 hex；
 *   - 压在图片/视频上的文字用 TC.textOnMedia*()（常白，不随主题翻转）；
 *   - 品牌特有色（VIP 金等）不在语义层，继续内联；
 *   - 需要在应用皮肤时原地刷新的组件，加一行
 *     @StorageProp('skinVersion') skinVersionObs: number = 0。
 */
export class TC {
  private static pick(token: string, fallback: ResourceColor): ResourceColor {
    const skin: string | undefined = SkinService.colorOverride(token)
    if (skin !== undefined && skin.length > 0) {
      return skin
    }
    return fallback
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

  /** 压在主题色上的文字。 */
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
}
