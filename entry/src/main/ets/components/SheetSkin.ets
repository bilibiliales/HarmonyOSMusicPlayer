import { DecoKeys } from '../services/DecorationRuntime'
import { DecorationMedia } from '../services/DecorationMedia'
import { TC } from '../services/ThemeColors'

/**
 * 半模态（bindSheet）外观装扮。
 *
 * bindSheet 只能设置纯色底，没有背景图能力，所以图片必须画在弹层内容里：
 * 所有弹层的 @Builder 都用 `SheetSkinFrame` 包一层，
 * 它负责「底色 → 贴图 → 暗化蒙版 → 真实内容」的叠放，未装扮时与原来完全一致。
 *
 * 用法（在任意 @Builder 里）：
 *   SheetSkinFrame() {
 *     this.SomeSheet()   // 原来的弹层内容
 *   }
 */
@Component
export struct SheetSkinFrame {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @StorageProp(DecoKeys.SHEET_BG) sheetBg: string = ''
  @StorageProp(DecoKeys.SHEET_BG_COLOR) sheetColor: string = ''
  @StorageProp(DecoKeys.SHEET_BG_OPACITY) sheetOpacity: number = 100
  @StorageProp(DecoKeys.SHEET_BG_BLUR) sheetBlur: number = 0
  @StorageProp(DecoKeys.SHEET_SCRIM) sheetScrim: number = 0

  @Builder
  private emptyContent() {
  }

  @BuilderParam content: () => void = this.emptyContent

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 1. 底色：装扮色 > 主题弹层色
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.sheetColor ? this.sheetColor : TC.sheetBackground())

      // 2. 背景贴图
      if (this.sheetBg) {
        Image(DecorationMedia.displayUri(this.sheetBg))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(this.sheetBlur)
          .opacity(Math.max(0, Math.min(100, this.sheetOpacity)) / 100)
          .hitTestBehavior(HitTestMode.None)
      }

      // 3. 可读性蒙版
      if (this.sheetBg && this.sheetScrim > 0) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(`rgba(0,0,0,${Math.min(80, this.sheetScrim) / 100})`)
          .hitTestBehavior(HitTestMode.None)
      }

      // 4. 内容
      this.content()
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }
}
