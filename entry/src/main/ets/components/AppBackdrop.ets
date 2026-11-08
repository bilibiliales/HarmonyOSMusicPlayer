import { DecoKeys } from '../services/DecorationRuntime'

/**
 * 全局页面背景层。
 *
 * 放在 Index 最底层，皮肤设置了背景图时铺满全屏；所有页面/卡片的底色在
 * 皮肤启用背景图时会被运行时置为透明（page_background = #00000000），
 * 因此这一层能透出到每一个页面，无需逐页改动。
 */
@Component
export struct AppBackdrop {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @StorageProp('themeIsDark') isDark: boolean = false
  @StorageProp(DecoKeys.SKIN_BG) bgImage: string = ''
  @StorageProp(DecoKeys.SKIN_BG_OPACITY) bgOpacity: number = 100
  @StorageProp(DecoKeys.SKIN_BG_BLUR) bgBlur: number = 0
  @StorageProp(DecoKeys.SKIN_BG_COLOR) bgColor: string = ''
  @StorageProp(DecoKeys.SKIN_SCRIM) scrim: number = 0

  private scrimColor(): string {
    const alpha = Math.max(0, Math.min(100, this.scrim)) / 100
    return this.isDark ? `rgba(0,0,0,${alpha})` : `rgba(255,255,255,${alpha})`
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.bgColor ? this.bgColor : (this.isDark ? '#121215' : '#f4f4f7'))

      if (this.bgImage) {
        Image(this.bgImage)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          // 放大一点，避免高斯模糊在边缘出现透明缺口
          .scale({ x: 1.12, y: 1.12 })
          .blur(this.bgBlur)
          .opacity(Math.max(0, Math.min(100, this.bgOpacity)) / 100)
        if (this.scrim > 0) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.scrimColor())
        }
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }
}
