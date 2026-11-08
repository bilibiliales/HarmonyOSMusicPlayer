import { PlayerLayer, PlayerStyleConfig } from '../models/decoration'
import { TC } from '../services/ThemeColors'

/**
 * 播放页全屏背景：背景色 / 图片 / 循环视频 / 用户图层 / 可读性蒙版。
 *
 * 未启用「播放器样式」时保持原样（模糊封面 + 渐变），避免默认观感回退。
 */
@Component
export struct PlayerBackdrop {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Prop style: PlayerStyleConfig = new PlayerStyleConfig()
  @Prop coverUrl: string = ''

  private scrimColor(): string {
    const alpha = Math.max(0, Math.min(100, this.style.bgScrim)) / 100
    return `rgba(0,0,0,${alpha})`
  }

  private hasCustomBackground(): boolean {
    return this.style.bgVideo.length > 0 || this.style.bgImage.length > 0 || this.style.bgColor.length > 0
  }

  @Builder
  private LayerView(layer: PlayerLayer) {
    Image(layer.src)
      .width(`${layer.w}%`)
      .height(`${layer.h}%`)
      .objectFit(ImageFit.Contain)
      .rotate({ angle: layer.rotation })
      .opacity(Math.max(0, Math.min(100, layer.opacity)) / 100)
      .position({ x: `${layer.x}%`, y: `${layer.y}%` })
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 兜底底色：任何情况下都不露白
      Column().width('100%').height('100%').backgroundColor(TC.pageBackground())

      if (this.style.bgColor) {
        Column().width('100%').height('100%').backgroundColor(this.style.bgColor)
      }

      if (this.style.bgVideo) {
        Video({ src: this.style.bgVideo })
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .autoPlay(true)
          .loop(true)
          .muted(true)
          .controls(false)
          .blur(this.style.bgBlur)
          .opacity(Math.max(0, Math.min(100, this.style.bgOpacity)) / 100)
      } else if (this.style.bgImage) {
        Image(this.style.bgImage)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .scale({ x: 1.08, y: 1.08 })
          .blur(this.style.bgBlur)
          .opacity(Math.max(0, Math.min(100, this.style.bgOpacity)) / 100)
      } else if (!this.hasCustomBackground()) {
        // 默认观感：当前封面模糊铺底 + 纵向渐变
        Image(this.coverUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(90)
          .opacity(0.44)
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 180,
            colors: [['rgba(12,12,16,0.42)', 0], ['rgba(15,15,20,0.82)', 0.58], ['#121215', 1]]
          })
      }

      // 自定义背景的可读性蒙版（默认观感已经有渐变，不再叠加）
      if (this.hasCustomBackground() && this.style.bgScrim > 0) {
        Column().width('100%').height('100%').backgroundColor(this.scrimColor())
      }

      ForEach(this.style.layers, (layer: PlayerLayer) => {
        this.LayerView(layer)
      }, (layer: PlayerLayer) => layer.id)

      // 底部控件区域的轻微压暗，保证控件在亮色背景上也能看清
      if (this.hasCustomBackground()) {
        Column()
          .width('100%')
          .height('42%')
          .position({ x: 0, y: '58%' })
          .linearGradient({
            angle: 180,
            colors: [['rgba(0,0,0,0)', 0], ['rgba(0,0,0,0.32)', 1]]
          })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }
}
