import { HeartBurst } from './HeartBurst'

/** 共用红心图标：点赞状态变为选中时，在按钮中心播放装扮特效。 */
@Component
export struct HeartLike {
  @Prop @Watch('likedChanged') liked: boolean = false
  @Prop iconSize: number = 20
  @Prop iconColor: ResourceColor = '#ef233c'
  /** 列表行可能随点赞数据重建，用成功点赞的时间把动画传给新组件。 */
  @Prop @Watch('stampChanged') burstStamp: number = 0
  @Prop useStamp: boolean = false
  @State private trigger: number = 0

  private likedChanged(): void {
    if (this.liked && !this.useStamp) {
      this.trigger++
    }
  }

  aboutToAppear(): void {
    this.stampChanged()
  }

  private stampChanged(): void {
    if (this.useStamp && this.burstStamp > 0 && Date.now() - this.burstStamp < 500) {
      this.trigger++
    }
  }

  build() {
    Stack() {
      SymbolGlyph(this.liked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
        .fontSize(this.iconSize).fontColor([this.iconColor])
      HeartBurst({ trigger: this.trigger })
        .position({ x: this.iconSize / 2 - 60, y: this.iconSize / 2 - 80 })
    }
    .width(this.iconSize).height(this.iconSize)
    .clip(false)
  }
}
