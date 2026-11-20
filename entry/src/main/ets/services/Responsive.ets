/**
 * 全屏 / 大屏适配的断点工具。
 *
 * 约定（宽度单位 vp）：
 * - compact  < 600      手机竖屏、手机横屏的小窗
 * - medium   600 ~ 900  平板竖屏、折叠屏展开
 * - expanded >= 900     平板横屏、桌面全屏
 *
 * 页面用 onAreaChange 拿到自身宽高后调用这里的方法，避免各处写死阈值。
 */
export class Responsive {
  static readonly MEDIUM: number = 600
  static readonly EXPANDED: number = 900
  /** 横屏判定除了宽度够，还要求明显宽于高，排除竖屏平板。 */
  static readonly WIDE_LANDSCAPE_MIN: number = 840

  static columns(width: number, compact: number, medium: number, expanded: number): number {
    if (width >= Responsive.EXPANDED) { return expanded }
    if (width >= Responsive.MEDIUM) { return medium }
    return compact
  }

  static isExpanded(width: number): boolean {
    return width >= Responsive.EXPANDED
  }

  static isWideLandscape(width: number, height: number): boolean {
    return width >= Responsive.WIDE_LANDSCAPE_MIN && width > height
  }

  /** Flex 换行布局里每项的宽度百分比，已给列间距留出余量。 */
  static itemPercent(columns: number): string {
    if (columns <= 1) { return '100%' }
    if (columns === 2) { return '48.5%' }
    if (columns === 3) { return '31.8%' }
    if (columns === 4) { return '23.5%' }
    return '18.8%'
  }

  /** WaterFlow 的 columnsTemplate。 */
  static waterFlowColumns(columns: number): string {
    const count = Math.max(1, Math.floor(columns))
    let template = '1fr'
    for (let i = 1; i < count; i++) {
      template = `${template} 1fr`
    }
    return template
  }

  /**
   * 详情类页面在大屏上的正文宽度上限：内容不再随窗口无限拉长，
   * 超出部分居中留白（阅读更舒服，也不会出现一条超长文本）。
   */
  static contentWidth(width: number, max: number): number {
    if (width <= 0) { return max }
    return width > max ? max : width
  }
}
