import { TC } from '../services/ThemeColors'
@Component
export struct LevelTaskRing {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Prop value: number = 0
  @Prop remaining: number = 0
  @Prop label: string = ''
  @Prop unit: string = ''
  @Prop color: string = '#ff6577'

  build() {
    Column({ space: 16 }) {
      Stack() {
        Progress({ value: this.value, total: 100, type: ProgressType.Ring })
          .width(112).height(112).color(this.color).backgroundColor(TC.surfaceRaised())
          .style({ strokeWidth: 5, enableSmoothEffect: true })
        Text(`还需${Math.max(0, Math.ceil(this.remaining))}${this.unit}`)
          .fontSize(13).fontColor(TC.textBody()).maxLines(1)
      }.width(112).height(112)
      Text(this.label).fontSize(15).fontColor(TC.textSecondary())
    }.width('100%').alignItems(HorizontalAlign.Center)
  }
}
