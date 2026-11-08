import { BubbleTip } from '../services/BubbleTip'
import { DecorationStore } from '../services/DecorationStore'
import { DecoKind, DecorationCodec, DecorationItem } from '../models/decoration'
import { TC } from '../services/ThemeColors'
import { DecorationEditorParam } from './DecorationEditor'

/**
 * 装扮中心。
 *
 * 入口：侧边栏「AI 写歌」上方。
 * 结构：顶部概览（当前生效项数 + 我的装扮/全部取消）→ 12 类装扮入口 →
 *       每类点进去是「列表 + 编辑」的装扮编辑器；套装在编辑器里一次性打包多类。
 * 全部数据本地存储（DecorationStore），颜色类装扮会覆盖到 SkinService（装扮优先于深浅色）。
 */
@Component
export struct DecorationCenterPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @StorageProp('decorationActiveCount') activeCount: number = 0
  @State private mineVisible: boolean = false
  @State private tick: number = 0
  private kinds: string[] = [
    DecoKind.SKIN, DecoKind.PLAYER, DecoKind.DOCK, DecoKind.SIDEBAR, DecoKind.HOME_BG,
    DecoKind.HEART, DecoKind.STARTUP, DecoKind.AVATAR_FRAME, DecoKind.VIP_CARD,
    DecoKind.APP_ICON, DecoKind.VIP_BADGE, DecoKind.SUIT
  ]

  // ---- 数据查询（tick / activeCount 变化时重新取值，驱动界面刷新） ----

  private activeItem(kind: string): DecorationItem | undefined {
    return DecorationStore.activeItem(kind)
  }

  private previewOf(kind: string): string {
    const item = this.activeItem(kind)
    return item ? DecorationCodec.previewImage(item) : ''
  }

  private countOf(kind: string): number {
    return DecorationStore.list(kind).length
  }

  private activeKinds(): string[] {
    const result: string[] = []
    for (const kind of this.kinds) {
      if (kind !== DecoKind.SUIT && DecorationStore.activeItem(kind)) {
        result.push(kind)
      }
    }
    return result
  }

  private open(kind: string): void {
    const param = new DecorationEditorParam()
    param.kind = kind
    this.pageStack.pushPathByName('DecorationEditorPage', param)
  }

  private async cancel(kind: string): Promise<void> {
    await DecorationStore.deactivate(kind)
    this.tick = this.tick + 1
  }

  private async cancelAll(): Promise<void> {
    await DecorationStore.deactivateAll()
    this.tick = this.tick + 1
    this.mineVisible = false
    BubbleTip.show(this.getUIContext(), '已取消全部装扮')
  }

  // ---- 视图 ----

  @Builder
  private KindCard(kind: string) {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.previewOf(kind)) {
        Image(this.previewOf(kind))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 135,
            colors: [[TC.surfaceInset(), 0], [TC.chipBackground(), 1]]
          })
        SymbolGlyph(DecoKind.icon(kind))
          .fontSize(34)
          .fontColor([TC.textQuaternary()])
          .position({ x: '50%', y: '38%' })
          .translate({ x: -17, y: -17 })
      }

      // 底部压暗，保证标题在任何预览图上可读
      Column()
        .width('100%')
        .height('58%')
        .linearGradient({
          angle: 180,
          colors: [['rgba(0,0,0,0)', 0], ['rgba(0,0,0,0.62)', 1]]
        })

      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(DecoKind.title(kind))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
          if (DecorationStore.activeId(kind)) {
            Text('使用中')
              .fontSize(9)
              .fontColor('#FFFFFF')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(TC.accent())
              .borderRadius(7)
          }
        }
        Text(this.countOf(kind) > 0 ? `${this.countOf(kind)} 个可用` : DecoKind.desc(kind))
          .fontSize(10)
          .fontColor('rgba(255,255,255,0.78)')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 11 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(124)
    .borderRadius(18)
    .clip(true)
    .onClick(() => this.open(kind))
  }

  @Builder
  private MineSheet() {
    Column({ space: 14 }) {
      Row() {
        Column({ space: 3 }) {
          Text('我的装扮').fontSize(18).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
          Text(`当前生效 ${this.activeKinds().length} 项`).fontSize(11).fontColor(TC.textTertiary())
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('一键全部取消')
          .fontSize(12)
          .fontColor(TC.textPrimary())
          .backgroundColor(TC.chipBackground())
          .height(34)
          .padding({ left: 14, right: 14 })
          .borderRadius(17)
          .onClick(() => this.cancelAll())
      }
      .width('100%')

      if (this.activeKinds().length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.wand_and_stars')).fontSize(38).fontColor([TC.textQuaternary()])
          Text('还没有启用任何装扮').fontSize(13).fontColor(TC.textSecondary())
          Text('去挑一件喜欢的皮肤或播放器样式吧').fontSize(11).fontColor(TC.textTertiary())
        }
        .width('100%')
        .padding({ top: 60, bottom: 40 })
      } else {
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.activeKinds(), (kind: string) => {
              Row({ space: 12 }) {
                if (this.previewOf(kind)) {
                  Image(this.previewOf(kind))
                    .width(46)
                    .height(46)
                    .borderRadius(12)
                    .objectFit(ImageFit.Cover)
                } else {
                  Stack() {
                    SymbolGlyph(DecoKind.icon(kind)).fontSize(20).fontColor([TC.textTertiary()])
                  }
                  .width(46)
                  .height(46)
                  .borderRadius(12)
                  .backgroundColor(TC.surfaceInset())
                }

                Column({ space: 3 }) {
                  Text(DecoKind.title(kind)).fontSize(14).fontColor(TC.textPrimary())
                  Text(DecorationStore.activeName(kind))
                    .fontSize(11)
                    .fontColor(TC.textTertiary())
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Button('取消')
                  .fontSize(11)
                  .fontColor(TC.textSecondary())
                  .backgroundColor(TC.chipBackground())
                  .height(30)
                  .padding({ left: 12, right: 12 })
                  .borderRadius(15)
                  .onClick(() => this.cancel(kind))

                Button('更换')
                  .fontSize(11)
                  .fontColor(TC.textOnAccent())
                  .backgroundColor(TC.accent())
                  .height(30)
                  .padding({ left: 12, right: 12 })
                  .borderRadius(15)
                  .onClick(() => {
                    this.mineVisible = false
                    this.open(kind)
                  })
              }
              .width('100%')
              .padding(10)
              .backgroundColor(TC.surfaceCardAlt())
              .borderRadius(16)
            }, (kind: string) => kind)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 18, right: 18, top: 8, bottom: 18 })
  }

  build() {
    NavDestination() {
      Column() {
        Column().width('100%').height(this.topAvoidHeight)

        // 顶栏
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .fontColor([TC.textPrimary()])
            .onClick(() => this.pageStack.pop())
          Text('装扮中心').layoutWeight(1).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(TC.textPrimary()).textAlign(TextAlign.Center)
          Text('我的装扮')
            .fontSize(12)
            .fontColor(TC.accent())
            .onClick(() => this.mineVisible = true)
        }
        .height(56)
        .constraintSize({ minHeight: 56 })
        .width('100%')
        .padding({ left: 16, right: 16 })

        Scroll() {
          Column({ space: 16 }) {
            // 概览
            Stack({ alignContent: Alignment.BottomStart }) {
              Column()
                .width('100%')
                .height('100%')
                .linearGradient({
                  angle: 150,
                  colors: [[TC.accentContainer(), 0], [TC.surfaceCard(), 1]]
                })

              Column({ space: 8 }) {
                Text('打造只属于你的播放器').fontSize(19).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
                Text('皮肤、播放器样式、图标与特效全部本地保存，重启依然生效。')
                  .fontSize(11)
                  .fontColor(TC.textSecondary())
                Row({ space: 10 }) {
                  Row({ space: 4 }) {
                    Text(`${this.activeKinds().length}`).fontSize(15).fontWeight(FontWeight.Bold)
                      .fontColor(TC.accent())
                    Text('项生效中').fontSize(11).fontColor(TC.textTertiary())
                  }
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .backgroundColor(TC.surfaceCard())
                  .borderRadius(12)

                  Blank()

                  Button('我的装扮')
                    .fontSize(12)
                    .fontColor(TC.textOnAccent())
                    .backgroundColor(TC.accent())
                    .height(34)
                    .padding({ left: 16, right: 16 })
                    .borderRadius(17)
                    .onClick(() => this.mineVisible = true)
                }
                .width('100%')
              }
              .width('100%')
              .padding(18)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .height(160)
            .borderRadius(22)
            .clip(true)

            // 分类入口
            Text('个性装扮')
              .width('100%')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(TC.textPrimary())

            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
              ForEach(this.kinds, (kind: string) => {
                Column() {
                  this.KindCard(kind)
                }
                .width('48.5%')
                .margin({ bottom: 11 })
              }, (kind: string) => kind)
            }
            .width('100%')

            Text('颜色类装扮会优先于深浅色主题：皮肤里指定了固定色，切换深浅色时该颜色保持不变。')
              .width('100%')
              .fontSize(11)
              .fontColor(TC.textTertiary())
              .padding({ bottom: 20 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(TC.pageBackground())
      .bindSheet(this.mineVisible, this.MineSheet(), {
        height: '68%',
        backgroundColor: TC.sheetBackground(),
        showClose: false,
        dragBar: true,
        onDisappear: () => this.mineVisible = false
      })
    }
    .hideTitleBar(true)
    .onShown(() => {
      this.tick = this.tick + 1
    })
  }
}
