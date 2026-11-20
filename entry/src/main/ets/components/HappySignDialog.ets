import { HappySignHotComment, HappySignInfo } from '../models/home'
import { DailyExtraService } from '../services/DailyExtraService'
import { TC } from '../services/ThemeColors'

/**
 * 今日乐签：独立自定义弹窗。
 * 内容来自接口返回，主视觉底色使用签名自带的 backColor，其余配色跟随主题。
 */
@CustomDialog
export struct HappySignDialog {
  controller?: CustomDialogController
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Prop info: HappySignInfo = new HappySignInfo()

  private cardBackground(): string {
    return DailyExtraService.signBackgroundColor(this.info.backColor)
  }

  @Builder
  private Cover() {
    if (this.info.resourceCover.length > 0) {
      Image(this.info.resourceCover)
        .width(72)
        .height(72)
        .borderRadius(12)
        .objectFit(ImageFit.Cover)
        .backgroundColor(TC.chipBackground())
    } else {
      Column()
        .width(72)
        .height(72)
        .borderRadius(12)
        .backgroundColor(TC.chipBackground())
    }
  }

  build() {
    Column({ space: 12 }) {
      // 主视觉：签名文案 + 作者，底色来自签名
      Stack({ alignContent: Alignment.BottomStart }) {
        Column()
          .width('100%')
          .height(132)
          .borderRadius(16)
          .backgroundColor(this.cardBackground() ? this.cardBackground() : TC.accent())
        if (this.info.cover.length > 0) {
          Image(this.info.cover)
            .width(44)
            .height(44)
            .borderRadius(10)
            .objectFit(ImageFit.Cover)
            .position({ x: '100%', y: 12 })
            .translate({ x: -58 })
        }
        Column({ space: 4 }) {
          Text(this.info.mainText)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(TC.textOnAccent())
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.info.author.length > 0 ? `—— ${this.info.author}` : '')
            .fontSize(11)
            .fontColor(TC.textOnAccent())
            .opacity(0.85)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 14 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      // 签名里附带的歌曲
      if (this.info.resourceCover.length > 0 || this.info.resourceName.length > 0) {
        Row({ space: 10 }) {
          this.Cover()
          Column({ space: 4 }) {
            Text(this.info.resourceName)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(TC.textPrimary())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.info.resourceAuthor)
              .fontSize(11)
              .fontColor(TC.textSecondary())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding(10)
        .backgroundColor(TC.surfaceCard())
        .borderRadius(14)
      }

      // 热门留言，最多展示三条
      if (this.info.hotComments.length > 0) {
        Column({ space: 8 }) {
          Text('云村热评').fontSize(13).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
          ForEach(this.info.hotComments.slice(0, 3), (comment: HappySignHotComment, index: number) => {
            Row({ space: 8 }) {
              Text(`${index + 1}`)
                .fontSize(11)
                .fontColor(TC.accent())
                .width(14)
                .textAlign(TextAlign.Center)
              Column({ space: 3 }) {
                Text(comment.content)
                  .fontSize(11)
                  .fontColor(TC.textBody())
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (comment.authorName.length > 0) {
                  Text(`@${comment.authorName}`).fontSize(9).fontColor(TC.textQuaternary())
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }, (comment: HappySignHotComment, index: number) => `sign_comment_${index}_${comment.content}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      // 二维码
      if (this.info.qrCode.length > 0) {
        Column({ space: 6 }) {
          Image(this.info.qrCode)
            .width(96)
            .height(96)
            .objectFit(ImageFit.Contain)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
          Text('扫码查看乐签').fontSize(10).fontColor(TC.textTertiary())
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }

      Button('知道了')
        .width('100%')
        .height(40)
        .fontSize(13)
        .fontColor(TC.textOnAccent())
        .backgroundColor(TC.accent())
        .borderRadius(20)
        .onClick(() => this.controller?.close())
    }
    .width('86%')
    .constraintSize({ maxHeight: '80%' })
    .padding(18)
    .backgroundColor(TC.sheetBackground())
    .borderRadius(20)
  }
}
