import { TC } from '../services/ThemeColors'

/**
 * 详情页统一的底部收尾。
 *
 * 内容很少时（例如用户没有一条动态）头图会显得顶在页面中间，
 * 这里固定给一段留白 + 「没有更多了」，让页面始终有完整的收束。
 */
@Component
export struct NoMoreFooter {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Prop label: string = '没有更多了'
  /** 额外留白，内容特别少的页面可以加大。 */
  @Prop extraSpace: number = 0

  build() {
    Column() {
      Text(`—  ${this.label}  —`)
        .fontSize(11)
        .fontColor(TC.textQuaternary())
    }
    .width('100%')
    .height(120 + this.extraSpace)
    .justifyContent(FlexAlign.Center)
  }
}
