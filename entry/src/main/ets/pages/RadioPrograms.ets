import { SkinBackdrop } from '../components/SkinBackdrop'
import { ProgramMenuRow } from '../components/RadioCards'
import { ShareSheet } from '../components/ShareSheet'
import { SharePageParam } from '../models/api'
import { ProgramItem } from '../models/home'
import { RadioPageParam } from '../models/radio'
import { RadioPlayback } from '../services/RadioPlayback'
import { RadioService } from '../services/RadioService'
import { BubbleTip } from '../services/BubbleTip'
import { TC } from '../services/ThemeColors'

/** 发现 - 播客：精选节目列表（入口在播客页顶部）。 */
@Component
export struct RadioProgramsPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @State programs: ProgramItem[] = []
  @State loading: boolean = false
  @State refreshing: boolean = false
  @State playing: boolean = false
  @State message: string = ''
  @State sharing: boolean = false
  @State shareParam: SharePageParam = { type: 'program', id: '', name: '', img: '' }
  private alive: boolean = true

  aboutToAppear(): void { this.alive = true; this.load() }
  aboutToDisappear(): void { this.alive = false }

  private async load(): Promise<void> {
    this.loading = true
    this.message = ''
    try {
      const programs = await RadioService.recommendedPrograms(20)
      if (this.alive) { this.programs = programs }
    } catch (error) {
      if (this.alive) { this.message = error instanceof Error ? error.message : '精选节目加载失败' }
    } finally { if (this.alive) { this.loading = false } }
  }

  private async play(index: number): Promise<void> {
    if (this.playing || this.programs.length === 0) { return }
    this.playing = true
    try {
      await RadioPlayback.play(this.programs, index)
      this.pageStack.pushPathByName('PlayPage', null)
    } catch (error) { BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '播放失败') }
    finally { this.playing = false }
  }

  private open(program: ProgramItem): void {
    const param: RadioPageParam = { id: String(program.id), name: program.name, cover: RadioService.cover(program) }
    this.pageStack.pushPathByName('RadioProgramPage', param)
  }

  private share(program: ProgramItem): void {
    this.shareParam = { type: 'program', id: String(program.id), name: program.name,
      img: RadioService.cover(program), author: RadioService.author(program) }
    this.sharing = true
  }

  @Builder
  private ShareOptions() {
    ShareSheet({ shareParam: this.shareParam, visible: true, onClose: () => this.sharing = false })
  }

  build() {
    NavDestination() {
      SkinBackdrop()
      Column() {
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([TC.textPrimary()])
            .onClick(() => this.pageStack.pop())
          Text('精选节目').fontSize(20).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
        }.width('100%').height(56 + this.topAvoidHeight).padding({ left: 17, top: this.topAvoidHeight })

        Refresh({ refreshing: $$this.refreshing }) {
          List() {
            ListItem() {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.play_fill')).fontSize(18).fontColor([TC.textPrimary()])
                Text(`播放全部${this.programs.length > 0 ? ` (${this.programs.length})` : ''}`)
                  .fontSize(14).fontWeight(FontWeight.Medium).fontColor(TC.textPrimary())
              }
              .width('100%').height(54).padding({ left: 17, right: 17 })
              .enabled(!this.playing && this.programs.length > 0)
              .onClick(() => this.play(0))
            }
            ForEach(this.programs, (program: ProgramItem, index: number) => {
              ListItem() {
                ProgramMenuRow({ program: program, index: index + 1,
                  onPlay: () => this.play(index),
                  onDetail: () => this.open(program),
                  onShare: () => this.share(program) })
              }
            }, (program: ProgramItem) => String(program.id))
            ListItem() {
              Column({ space: 10 }) {
                if (this.loading) {
                  LoadingProgress().width(30).height(30).color(TC.accent())
                } else if (this.message.length > 0) {
                  Text(this.message).fontSize(12).fontColor(TC.accentSoft())
                  Button('重试').fontSize(12).backgroundColor(TC.surfaceRaised()).fontColor(TC.textBody())
                    .onClick(() => this.load())
                } else {
                  Text(this.programs.length === 0 ? '暂无精选节目' : '已经到底了')
                    .fontSize(12).fontColor(TC.textTertiary())
                }
              }.width('100%').padding({ top: 20, bottom: 40 })
            }
          }
          .width('100%').height('100%').scrollBar(BarState.Off)
        }
        .layoutWeight(1)
        .onRefreshing(async () => { await this.load(); this.refreshing = false })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(TC.pageBackground())
      .bindContentCover(this.sharing, this.ShareOptions(), {
        modalTransition: ModalTransition.NONE, backgroundColor: Color.Transparent,
        onDisappear: () => this.sharing = false
      })
    }.hideTitleBar(true)
  }
}
