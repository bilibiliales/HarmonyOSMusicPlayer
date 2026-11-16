import { DecoKeys } from '../services/DecorationRuntime'

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
  @StorageProp(DecoKeys.HEART_COUNT) count: number = 0
  @StorageProp(DecoKeys.HEART_SIZE) heartSize: number = 22
  @StorageProp(DecoKeys.HEART_DURATION) duration: number = 1200
  @State private particles: HeartParticle[] = []
  @State private progress: number = 0
  private seq: number = 0
  private resetTimer: number = -1

  /** trigger 变化时喷一次。 */
  private burst(): void {
    if (this.trigger <= 0 || this.count <= 0) {
      return
    }
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
    animateTo({ duration: this.duration, curve: Curve.EaseOut }, () => {
      this.progress = 1
    })
    this.resetTimer = setTimeout(() => {
      this.particles = []
      this.progress = 0
      this.resetTimer = -1
    }, this.duration + 80)
  }

  /** 上飘阶段渐显（前 20%），之后缓慢渐隐。 */
  private alphaOf(particle: HeartParticle): number {
    const p = this.progress
    if (p < 0.2) {
      return Math.max(0, p / 0.2)
    }
    return Math.max(0, 1 - (p - 0.2) / 0.8)
  }

  aboutToDisappear(): void {
    if (this.resetTimer !== -1) {
      clearTimeout(this.resetTimer)
      this.resetTimer = -1
    }
  }

  build() {
    Stack() {
      ForEach(this.particles, (particle: HeartParticle) => {
        SymbolGlyph($r('sys.symbol.heart_fill'))
          .fontSize(this.heartSize * particle.scale)
          .fontColor([this.color ? this.color : '#ef233c'])
          .translate({
            // 先上飘再回落：正弦曲线，progress 0.5 时到最高点
            x: particle.dx + particle.drift * this.progress,
            y: -particle.rise * Math.sin(this.progress * Math.PI)
          })
          .rotate({ angle: particle.rotate * this.progress })
          .opacity(this.alphaOf(particle))
      }, (particle: HeartParticle) => `${particle.id}`)
    }
    .width(120)
    .height(160)
    .hitTestBehavior(HitTestMode.None)
  }
}
