import { DecoKeys } from '../services/DecorationRuntime'
import { DecorationMedia } from '../services/DecorationMedia'

class HeartParticle {
  id: number = 0
  dx: number = 0
  drift: number = 0
  rise: number = 0
  scale: number = 1
  rotate: number = 0
}

/**
 * 点赞红心特效：从红心按钮位置向上飘、渐隐，结束后自动清空。
 *
 * 未启用装扮时 count = 0，不渲染任何东西，行为与原来一致。
 */
@Component
export struct HeartBurst {
  @Prop @Watch('burst') trigger: number = 0
  @StorageProp(DecoKeys.HEART_COLOR) color: string = ''
  @StorageProp(DecoKeys.HEART_IMAGE) @Watch('imageChanged') texture: string = ''
  @StorageProp(DecoKeys.HEART_COUNT) count: number = 0
  @StorageProp(DecoKeys.HEART_SIZE) heartSize: number = 22
  @StorageProp(DecoKeys.HEART_DURATION) duration: number = 1200
  @StorageProp(DecoKeys.HEART_MODE) mode: string = 'burst'
  @StorageProp(DecoKeys.HEART_FADE_IN) fadeIn: number = 300
  @StorageProp(DecoKeys.HEART_HOLD) hold: number = 1000
  @StorageProp(DecoKeys.HEART_FADE_OUT) fadeOut: number = 400
  @State private particles: HeartParticle[] = []
  @State private progress: number = 0
  @State private textureFailed: boolean = false
  private seq: number = 0
  private resetTimer: number = -1

  private aboveTimer: number = -1
  private showAbove(): void {
    const particle = new HeartParticle()
    particle.id = ++this.seq
    this.particles = [particle]
    this.progress = 0
    const seq = this.seq
    const fadeIn = Math.max(0, Math.min(5000, this.fadeIn))
    const hold = Math.max(0, Math.min(10000, this.hold))
    const fadeOut = Math.max(0, Math.min(5000, this.fadeOut))
    animateTo({ duration: fadeIn, curve: Curve.Linear }, () => this.progress = 1)
    this.aboveTimer = setTimeout(() => {
      if (this.seq !== seq) { return }
      animateTo({ duration: fadeOut, curve: Curve.Linear }, () => this.progress = 2)
      this.aboveTimer = -1
    }, fadeIn + hold)
    this.resetTimer = setTimeout(() => {
      if (this.seq !== seq) { return }
      this.particles = []
      this.progress = 0
      this.resetTimer = -1
    }, fadeIn + hold + fadeOut + 80)
  }

  private imageChanged(): void {
    this.textureFailed = false
  }

  aboutToAppear(): void {
    if (this.trigger > 0) { this.burst() }
  }

  /** trigger 变化时喷一次。 */
  private burst(): void {
    if (this.trigger <= 0 || this.count <= 0) {
      return
    }
    if (this.aboveTimer !== -1) { clearTimeout(this.aboveTimer); this.aboveTimer = -1 }
    if (this.resetTimer !== -1) { clearTimeout(this.resetTimer); this.resetTimer = -1 }
    if (this.mode === 'above') { this.showAbove(); return }
    const list: HeartParticle[] = []
    const total = Math.max(1, Math.min(20, Math.round(this.count)))
    for (let i = 0; i < total; i++) {
      const particle = new HeartParticle()
      particle.id = ++this.seq
      particle.dx = (Math.random() - 0.5) * 46
      particle.drift = (Math.random() - 0.5) * 70
      particle.rise = 70 + Math.random() * 110
      particle.scale = 0.6 + Math.random() * 0.9
      particle.rotate = (Math.random() - 0.5) * 60
      list.push(particle)
    }
    if (this.resetTimer !== -1) {
      clearTimeout(this.resetTimer)
      this.resetTimer = -1
    }
    this.particles = list
    this.progress = 0
    const burstSeq = this.seq
    const duration = Math.max(600, Math.min(3000, this.duration))
    animateTo({ duration: duration / 2, curve: Curve.EaseOut, onFinish: () => {
      if (this.seq !== burstSeq || this.resetTimer === -1) { return }
      animateTo({ duration: duration / 2, curve: Curve.EaseIn }, () => {
        this.progress = 2
      })
    } }, () => {
      this.progress = 1
    })
    this.resetTimer = setTimeout(() => {
      this.particles = []
      this.progress = 0
      this.resetTimer = -1
    }, duration + 80)
  }

  /** 上飘阶段渐显（前 20%），之后缓慢渐隐。 */
  private alphaOf(particle: HeartParticle): number {
    return this.progress <= 1 ? this.progress : Math.max(0, 2 - this.progress)
  }

  aboutToDisappear(): void {
    this.seq++
    if (this.aboveTimer !== -1) { clearTimeout(this.aboveTimer); this.aboveTimer = -1 }
    if (this.resetTimer !== -1) {
      clearTimeout(this.resetTimer)
      this.resetTimer = -1
    }
  }

  build() {
    Stack() {
      ForEach(this.particles, (particle: HeartParticle) => {
        Stack() {
          if (this.texture && !this.textureFailed) {
            Image(DecorationMedia.displayUri(this.texture))
              .width(this.heartSize * particle.scale).height(this.heartSize * particle.scale)
              .objectFit(ImageFit.Contain)
              .onError(() => this.textureFailed = true)
          } else {
            SymbolGlyph($r('sys.symbol.heart_fill'))
              .fontSize(this.heartSize * particle.scale)
              .fontColor([this.color ? this.color : '#ef233c'])
          }
        }
          .translate({
            x: this.mode === 'above' ? 0 : particle.dx + particle.drift * this.progress,
            y: this.mode === 'above' ? -(this.heartSize / 2 + 24) : -particle.rise * (1 - Math.abs(1 - this.progress))
          })
          .rotate({ angle: particle.rotate * this.progress })
          .opacity(this.alphaOf(particle))
      }, (particle: HeartParticle) => `${particle.id}`)
    }
    .width(120)
    .height(160)
    // 没有粒子时整个动画层从布局和命中测试中移除，
    // 否则它会盖在播放页 68%/40% 一片区域上，让下面的按钮点不到
    .visibility(this.particles.length > 0 ? Visibility.Visible : Visibility.None)
    .hitTestBehavior(HitTestMode.None)
  }
}
