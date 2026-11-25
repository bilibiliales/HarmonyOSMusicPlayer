/** 与发现页一致的二级菜单左右滑动；内容按菜单键重建，数据仍由页面持有。 */
export class SecondaryTabMotion {
  static readonly DURATION: number = 280

  static direction(current: string, next: string, order: string[]): number {
    return order.indexOf(next) > order.indexOf(current) ? -1 : 1
  }

  static effect(direction: number): TransitionEffect {
    return TransitionEffect.asymmetric(
      TransitionEffect.translate({ x: direction < 0 ? '100%' : '-100%' }),
      TransitionEffect.translate({ x: direction < 0 ? '-100%' : '100%' })
    ).animation({ duration: SecondaryTabMotion.DURATION, curve: Curve.EaseOut })
  }
}

@Component
export struct SecondaryTabContent {
  @Prop value: string = ''
  @Prop motionDirection: number = -1
  @Prop fill: boolean = false

  @Builder
  private emptyContent() {}

  @BuilderParam content: () => void = this.emptyContent

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach([this.value], (_value: string) => {
        Column() { this.content() }
          .width('100%').height(this.fill ? '100%' : undefined)
          .transition(SecondaryTabMotion.effect(this.motionDirection))
      }, (value: string) => value)
    }.width('100%').height(this.fill ? '100%' : undefined).clip(true)
  }
}
