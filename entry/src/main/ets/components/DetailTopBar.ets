import { TC } from '../services/ThemeColors'

/**
 * 详情页统一顶部栏。
 *
 * 视觉基准来自专辑页：36×36 圆形半透明按钮、悬浮在头图之上、无常驻标题。
 * 在此基础上补两点：
 *  - 页面下滑时渐显「纯毛玻璃」背景（只模糊、不叠深/浅色底），并淡出顶部暗化渐变；
 *  - 标题随下滑「上浮 + 渐显」，滚动后只留下标题与按钮。
 *
 * 宿主只需把自身 Scroller 的 currentOffset().yOffset 传给 scrollOffset；
 * 分享统一由 onShare 回调打开 ShareSheet，避免各页各写一套分享。
 */
@Component
export struct DetailTopBar {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number

  @Prop title: string = ''
  /** 页面滚动偏移（vp），来自宿主 Scroll/List。 */
  @Prop scrollOffset: number = 0
  @Prop shareEnabled: boolean = true
  /** 是否显示搜索按钮（歌单、全部歌曲页）。 */
  @Prop showSearch: boolean = false
  /** 搜索态：中间标题区替换为输入框。 */
  @Prop searchMode: boolean = false
  @Prop searchText: string = ''
  @Prop searchPlaceholder: string = '搜索'
  /** 标题上方的小字副标题（曲风页的父级曲风名）。 */
  @Prop subtitle: string = ''
  /** 标题旁显示下拉箭头，配合 onTitleClick 做切换器。 */
  @Prop titleDropdown: boolean = false
  onShare: () => void = () => {}
  onSearchToggle: () => void = () => {}
  onSearchTextChange: (value: string) => void = () => {}
  onTitleClick: () => void = () => {}

  @Builder
  private emptyTrailing() {
  }

  /** 额外按钮（更多菜单、管理入口等），由宿主以尾随闭包提供。 */
  @BuilderParam trailing: () => void = this.emptyTrailing

  /** 0（贴顶）→ 1（下滑约 160vp 后完全展开）。 */
  private progress(): number {
    const value = this.scrollOffset / 160
    if (value < 0) { return 0 }
    if (value > 1) { return 1 }
    return value
  }

  @Builder
  private CircleButton(symbol: Resource, glyphSize: number, action: () => void) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(glyphSize)
        .fontColor([TC.textOnMedia()])
    }
    .width(36)
    .height(36)
    .borderRadius(18)
    .backgroundColor('rgba(0,0,0,0.35)')
    .justifyContent(FlexAlign.Center)
    .onClick(() => action())
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 1. 下滑渐显的纯毛玻璃：只做背景模糊，不叠深色/浅色底
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .backdropBlur(16)
        .opacity(this.progress())
        .animation({ duration: 160, curve: Curve.EaseOut })
        .hitTestBehavior(HitTestMode.None)

      // 2. 贴顶时压在头图上的暗化渐变，随毛玻璃出现而淡出
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({ angle: 180, colors: [['rgba(0,0,0,0.48)', 0], ['rgba(0,0,0,0)', 1]] })
        .opacity(1 - this.progress() * 0.85)
        .animation({ duration: 160, curve: Curve.EaseOut })
        .hitTestBehavior(HitTestMode.None)

      Column() {
        Column().width('100%').height(this.topAvoidHeight)
        Row({ space: 8 }) {
          this.CircleButton($r('sys.symbol.chevron_left'), 22, () => this.pageStack.pop())

          if (this.searchMode) {
            TextInput({ text: this.searchText, placeholder: this.searchPlaceholder })
              .layoutWeight(1)
              .height(36)
              .fontSize(12)
              .fontColor(TC.textPrimary())
              .placeholderColor(TC.textQuaternary())
              .backgroundColor('rgba(20,20,25,0.45)')
              .borderRadius(18)
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => this.onSearchTextChange(value))
          } else if (this.title.length > 0) {
            // 标题上浮 + 渐显：贴顶时下沉 12vp 且全透明
            Column({ space: 2 }) {
              if (this.subtitle.length > 0) {
                Text(this.subtitle)
                  .fontSize(10)
                  .fontColor(TC.textBody())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              Row({ space: 6 }) {
                Text(this.title)
                  .layoutWeight(1)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(TC.textPrimary())
                  .textAlign(TextAlign.Center)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.titleDropdown) {
                  SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(12).fontColor([TC.textBody()])
                }
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
            }
            .layoutWeight(1)
            .opacity(this.progress())
            .translate({ y: (1 - this.progress()) * 12 })
            .animation({ duration: 200, curve: Curve.EaseOut })
            .onClick(() => this.onTitleClick())
          } else {
            Column().layoutWeight(1)
          }

          if (this.showSearch) {
            this.CircleButton(this.searchMode ? $r('sys.symbol.xmark_circle_fill') :
              $r('sys.symbol.magnifyingglass'), 18, () => this.onSearchToggle())
          }

          this.trailing()

          if (this.shareEnabled) {
            this.CircleButton($r('sys.symbol.share'), 18, () => this.onShare())
          }
        }
        .height(54)
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
    }
    .width('100%')
    .height(this.topAvoidHeight + 54)
  }
}
