import { DecoKeys } from '../services/DecorationRuntime'
import { DecorationMedia } from '../services/DecorationMedia'
import { TC } from '../services/ThemeColors'

/**
 * 冷启动装扮：图片或视频全屏展示，到时或播完自动消失，可手动跳过。
 * 每个进程只展示一次（AppStorage startupShown）。
 */
@Component
export struct StartupOverlay {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  // 装扮在 Ability.onCreate 里发布，但页面首帧与 AppStorage 同步的先后顺序
  // 在不同版本/预览器上并不保证，因此额外用 @Watch 兜底：值后到也能拉起开屏。
  @StorageProp(DecoKeys.STARTUP_MEDIA) @Watch('onMediaChanged') media: string = ''
  @StorageProp(DecoKeys.STARTUP_TYPE) mediaType: string = 'image'
  @StorageProp(DecoKeys.STARTUP_DURATION) duration: number = 3000
  @StorageProp(DecoKeys.STARTUP_SKIP) allowSkip: boolean = true
  @State visible: boolean = false
  @State remaining: number = 0
  private timer: number = -1
  private ticker: number = -1

  aboutToAppear(): void {
    this.tryShow()
  }

  private onMediaChanged(): void {
    if (!this.visible) { this.tryShow() }
  }

  /** 像开屏广告：每个进程只在冷启动展示一次，倒计时结束或点「跳过」消失。 */
  private tryShow(): void {
    const shown = AppStorage.get<boolean>('startupShown') ?? false
    if (this.visible || !this.media || shown) {
      return
    }
    AppStorage.setOrCreate<boolean>('startupShown', true)
    this.visible = true
    this.remaining = Math.max(1, Math.round(this.duration / 1000))
    const total = Math.max(0, this.duration)
    this.timer = setTimeout(() => this.close(), total)
    this.ticker = setInterval(() => {
      this.remaining = Math.max(0, this.remaining - 1)
    }, 1000)
  }

  aboutToDisappear(): void {
    this.clearTimers()
  }

  private clearTimers(): void {
    if (this.timer !== -1) {
      clearTimeout(this.timer)
      this.timer = -1
    }
    if (this.ticker !== -1) {
      clearInterval(this.ticker)
      this.ticker = -1
    }
  }

  private close(): void {
    this.clearTimers()
    this.visible = false
  }

  build() {
    if (this.visible) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        if (this.mediaType === 'video') {
          Video({ src: DecorationMedia.displayUri(this.media) })
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .autoPlay(true)
            .muted(true)
            .controls(false)
            .onFinish(() => this.close())
        } else {
          Image(DecorationMedia.displayUri(this.media))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        }

        if (this.allowSkip) {
          Row({ space: 6 }) {
            Text('跳过')
              .fontSize(12)
              .fontColor(TC.textOnMedia())
            Text(`${this.remaining}s`)
              .fontSize(12)
              .fontColor(TC.textOnMediaSecondary())
          }
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .backgroundColor('rgba(0,0,0,0.36)')
          .borderRadius(16)
          .margin({ right: 18, bottom: 46 })
          .onClick(() => this.close())
        }
      }
      .width('100%')
      .height('100%')
      .zIndex(200)
      // 开屏期间吞掉点击，避免误触下面的页面（跳过按钮是子组件，仍优先响应）
      .onClick(() => {})
      .transition(TransitionEffect.opacity(0).animation({ duration: 220 }))
    }
  }
}
