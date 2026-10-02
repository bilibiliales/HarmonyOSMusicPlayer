@Component
export struct VinylRecord {
  @Prop @Watch('syncRotation') isPlaying: boolean = false
  @Prop coverUrl: string = ''
  @Prop diameter: number = 44
  @State private angle: number = 0
  private rotationTimer: number = -1
  private lastTick: number = 0
  private visible: boolean = false

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

  build() {
    Stack() {
      Image($r('app.media.ic_cd'))
        .width(this.diameter).height(this.diameter).objectFit(ImageFit.Contain)
      if (this.coverUrl) {
        Image(this.coverUrl)
          .width(this.diameter * 0.63).height(this.diameter * 0.63)
          .objectFit(ImageFit.Cover).borderRadius('50%').clip(true)
      } else {
        SymbolGlyph($r('sys.symbol.music'))
          .fontSize(this.diameter * 0.3).fontColor(['#ffffff'])
      }
    }
    .width(this.diameter).height(this.diameter)
    .borderRadius('50%').clip(true)
    .rotate({ angle: this.angle })
    .onVisibleAreaChange([0, 1], (_isVisible: boolean, ratio: number) => {
      this.visible = ratio > 0
      this.syncRotation()
    })
  }
}
