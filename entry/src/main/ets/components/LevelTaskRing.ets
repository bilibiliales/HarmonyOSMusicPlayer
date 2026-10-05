@Component
export struct LevelTaskRing {
  @Prop value: number = 0
  @Prop remaining: number = 0
  @Prop label: string = ''
  @Prop unit: string = ''
  @Prop color: string = '#ff6577'

  build() {
    Column({ space: 16 }) {
      Stack() {
        Progress({ value: this.value, total: 100, type: ProgressType.Ring })
          .width(112).height(112).color(this.color).backgroundColor('#303038')
          .style({ strokeWidth: 5, enableSmoothEffect: true })
        Text(`还需${Math.max(0, Math.ceil(this.remaining))}${this.unit}`)
          .fontSize(13).fontColor('#d0d0d7').maxLines(1)
      }.width(112).height(112)
      Text(this.label).fontSize(15).fontColor('#92929a')
    }.width('100%').alignItems(HorizontalAlign.Center)
  }
}
