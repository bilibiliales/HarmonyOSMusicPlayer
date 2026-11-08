import { TC } from '../services/ThemeColors'

/**
 * 黑胶唱片。
 *
 * 装扮可替换：唱片底图（backImage）、封面比例/偏移/圆角、整体不透明度。
 * 未装扮时与默认观感完全一致（ic_cd + 63% 圆形封面）。
 */
@Component
export struct VinylRecord {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Prop @Watch('syncRotation') isPlaying: boolean = false
  @Prop coverUrl: string = ''
  @Prop diameter: number = 44
  /** 自定义唱片底图；空=默认 ic_cd。 */
  @Prop backImage: string = ''
  /** 封面相对直径的百分比 0-100。 */
  @Prop coverRatio: number = 63
  /** 封面中心相对唱片中心的偏移（vp）。 */
  @Prop coverOffsetX: number = 0
  @Prop coverOffsetY: number = 0
  /** 封面圆角百分比 0-50。 */
  @Prop coverRadius: number = 50
  @Prop vinylOpacity: number = 100
  @State private angle: number = 0
  private rotationTimer: number = -1
  private lastTick: number = 0
  private visible: boolean = false

  aboutToAppear(): void {
    this.visible = true
    this.syncRotation()
  }

  aboutToDisappear(): void {
    this.visible = false
    this.stopRotation()
  }

  private stopRotation(): void {
    if (this.rotationTimer !== -1) {
      clearInterval(this.rotationTimer)
      this.rotationTimer = -1
    }
  }

  private syncRotation(): void {
    if (!this.visible || !this.isPlaying) {
      this.stopRotation()
      return
    }
    if (this.rotationTimer !== -1) {
      return
    }
    this.lastTick = Date.now()
    this.rotationTimer = setInterval(() => {
      const now = Date.now()
      this.angle = (this.angle + Math.min(now - this.lastTick, 100) * 0.036) % 360
      this.lastTick = now
    }, 16)
  }

  private coverSize(): number {
    const ratio = Math.max(1, Math.min(100, this.coverRatio))
    return this.diameter * ratio / 100
  }

  build() {
    Stack() {
      Stack() {
        if (this.backImage) {
          Image(this.backImage)
            .width(this.diameter).height(this.diameter).objectFit(ImageFit.Contain)
        } else {
          Image($r('app.media.ic_cd'))
            .width(this.diameter).height(this.diameter).objectFit(ImageFit.Contain)
        }
        if (this.coverUrl) {
          Image(this.coverUrl)
            .width(this.coverSize()).height(this.coverSize())
            .objectFit(ImageFit.Cover)
            .borderRadius(`${Math.max(0, Math.min(50, this.coverRadius))}%`)
            .clip(true)
            .translate({ x: this.coverOffsetX, y: this.coverOffsetY })
        } else {
          SymbolGlyph($r('sys.symbol.music'))
            .fontSize(this.diameter * 0.3).fontColor([TC.textOnMedia()])
            .translate({ x: this.coverOffsetX, y: this.coverOffsetY })
        }
      }
      .width(this.diameter).height(this.diameter)
      .borderRadius('50%').clip(true)
      .rotate({ angle: this.angle })
    }
    .width(this.diameter).height(this.diameter)
    .opacity(Math.max(0, Math.min(100, this.vinylOpacity)) / 100)
    .onVisibleAreaChange([0, 1], (_isVisible: boolean, ratio: number) => {
      this.visible = ratio > 0
      this.syncRotation()
    })
  }
}
