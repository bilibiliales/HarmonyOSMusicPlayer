import { SkinBackdrop } from '../components/SkinBackdrop'
import { DailySongsResponse, HappySignInfo, mapApiSong, songItemType } from '../models'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { TC } from '../services/ThemeColors'
import { DetailTopBar } from '../components/DetailTopBar'
import { NoMoreFooter } from '../components/NoMoreFooter'
import { SheetSkinFrame } from '../components/SheetSkin'
import { HappySignDialog } from '../components/HappySignDialog'
import { DailyExtraService } from '../services/DailyExtraService'
import { BubbleTip } from '../services/BubbleTip'

@Component
export struct DailyRecommendPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @State songs: songItemType[] = []
  @State loading: boolean = true
  @State message: string = ''
  @State scrollOffset: number = 0
  /** 播放全部行是否已冻结在顶栏下沿（只在跨阈值时翻转）。 */
  @State private frozen: boolean = false
  private todayDate: string = new Date().getDate().toString()
  private scroller: Scroller = new Scroller()

  // 历史日推
  @State private historyVisible: boolean = false
  @State private historyDates: string[] = []
  @State private historyDescription: string = ''
  @State private historyEmptyMessage: string = ''
  @State private historyLoading: boolean = false
  @State private showingHistory: boolean = false
  @State private historyDate: string = ''
  private todaySongs: songItemType[] = []

  // 今日乐签：真正的自定义弹窗，打开时才构建 controller 以带上最新数据
  @State private signInfo: HappySignInfo = new HappySignInfo()
  private signController?: CustomDialogController

  aboutToAppear(): void {
    this.loadSongs()
  }

  private async loadSongs(): Promise<void> {
    this.loading = true
    this.message = ''
    try {
      const response = await ApiClient.get<DailySongsResponse>('/recommend/songs')
      if (response.code === 200 && response.data?.dailySongs?.length) {
        this.songs = response.data.dailySongs.map((item) => {
          const song = mapApiSong(item)
          song.recommendTag = item.recommendReason || item.reason || ''
          return song
        })
        this.todaySongs = this.songs.slice()
        this.showingHistory = false
        this.historyDate = ''
      } else {
        this.message = '暂无每日推荐歌曲'
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '每日推荐加载失败'
    } finally {
      this.loading = false
    }
  }

  /** 打开历史日期列表。 */
  private async openHistory(): Promise<void> {
    this.historyVisible = true
    this.historyLoading = true
    try {
      const summary = await DailyExtraService.historyDates()
      this.historyDates = summary.dates
      this.historyDescription = summary.description || summary.noHistoryMessage
      this.historyEmptyMessage = summary.noHistoryMessage
    } catch (error) {
      this.historyDates = []
      this.historyDescription = error instanceof Error ? error.message : '历史日推加载失败'
    } finally {
      this.historyLoading = false
    }
  }

  /** 选中某一天：复用当前列表展示那天的歌。 */
  private async selectHistoryDate(date: string): Promise<void> {
    this.historyVisible = false
    this.loading = true
    this.message = ''
    try {
      const rows = await DailyExtraService.historyDetail(date)
      this.songs = rows.map((item) => {
        const song = mapApiSong(item)
        song.recommendTag = item.recommendReason || item.reason || ''
        return song
      })
      this.historyDate = date
      this.showingHistory = true
      this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '历史日推加载失败')
    } finally {
      this.loading = false
    }
  }

  private backToToday(): void {
    this.songs = this.todaySongs.slice()
    this.showingHistory = false
    this.historyDate = ''
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
  }

  /** 今日乐签：先取内容，再用自定义弹窗展示。 */
  private async openHappySign(): Promise<void> {
    try {
      const info = await DailyExtraService.happySign()
      this.signInfo = info
      this.signController = new CustomDialogController({
        builder: HappySignDialog({ info: info }),
        autoCancel: true,
        customStyle: true,
        alignment: DialogAlignment.Center
      })
      this.signController.open()
    } catch (error) {
      BubbleTip.show(this.getUIContext(), error instanceof Error ? error.message : '今日乐签加载失败')
    }
  }

  private async playAt(index: number): Promise<void> {
    if (this.songs.length > 0) {
      await playerController.setQueue(this.songs, index, true)
    }
  }

  private actionBarBaseY(): number {
    return 220 + this.topAvoidHeight
  }

  private freezeThreshold(): number {
    return this.actionBarBaseY() - this.topAvoidHeight - 54
  }

  @Builder
  private PlayAllRow() {
    Row() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.play_fill')).fontSize(18).fontColor([TC.textPrimary()])
        Text(`播放全部${this.songs.length > 0 ? ` (${this.songs.length})` : ''}`)
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor(TC.textPrimary())
      }
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20).fontColor([TC.textSecondary()])
        .onClick(() => this.loadSongs())
    }
    .height(56).padding({ left: 18, right: 18 }).onClick(() => this.playAt(0))
  }

  /** 跟随阶段：播放全部行在内容流里，由原生滚动 1:1 带走（零 JS 参与）。 */
  @Builder
  private FlowPlayAllRow() {
    Column() {
      this.PlayAllRow()
    }
    .width('100%')
    .opacity(this.frozen ? 0 : 1)
  }

  /** 冻结阶段：撞到顶栏下沿后由浮层接管，位置固定、只在跨阈值时切换一次。 */
  @Builder
  private FrozenPlayAllRow() {
    Column() {
      this.PlayAllRow()
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
    .backdropBlur(30)
    .position({ x: 0, y: this.topAvoidHeight + 54 })
    .zIndex(3)
  }

  @Builder
  private TopActionButton(symbol: Resource, action: () => void) {
    Row() {
      SymbolGlyph(symbol).fontSize(18).fontColor([TC.textOnMedia()])
    }
    .width(36)
    .height(36)
    .borderRadius(18)
    .backgroundColor('rgba(0,0,0,0.35)')
    .justifyContent(FlexAlign.Center)
    .onClick(() => action())
  }

  @Builder
  private HistorySheetContent() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 3 }) {
          Text('历史日推').fontSize(18).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
          if (this.historyDescription.length > 0) {
            Text(this.historyDescription).fontSize(10).fontColor(TC.textTertiary()).maxLines(2)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.xmark_circle_fill')).fontSize(20).fontColor([TC.textSecondary()])
          .onClick(() => this.historyVisible = false)
      }
      .width('100%')

      if (this.historyLoading) {
        Column({ space: 10 }) {
          LoadingProgress().width(28).height(28).color(TC.accent())
          Text('正在加载历史日期').fontSize(11).fontColor(TC.textTertiary())
        }
        .width('100%').height(140).justifyContent(FlexAlign.Center)
      } else if (this.historyDates.length === 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.clock')).fontSize(30).fontColor([TC.textQuaternary()])
          Text(this.historyEmptyMessage || '暂无历史日推').fontSize(12).fontColor(TC.textTertiary())
        }
        .width('100%').height(140).justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.historyDates, (date: string) => {
            ListItem() {
              Row() {
                SymbolGlyph($r('sys.symbol.clock')).fontSize(16).fontColor([TC.accent()])
                Text(date).fontSize(14).fontColor(TC.textBody()).layoutWeight(1)
                  .padding({ left: 8 })
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([TC.textQuaternary()])
              }
              .width('100%')
              .height(48)
              .padding({ left: 16, right: 16 })
              .backgroundColor(TC.surfaceCard())
              .borderRadius(12)
              .onClick(() => this.selectHistoryDate(date))
            }
          }, (date: string) => date)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding(18)
  }

  @Builder
  private skin_HistorySheet() {
    SheetSkinFrame() {
      this.HistorySheetContent()
    }
  }

  build() {
    NavDestination() {
      SkinBackdrop()
      Stack({ alignContent: Alignment.TopStart }) {
        Scroll(this.scroller) {
          Column() {
            Stack({ alignContent: Alignment.BottomStart }) {
              if (this.songs.length > 0 && this.songs[0].img.length > 0) {
                Image(this.songs[0].img).width('100%').height(220 + this.topAvoidHeight).objectFit(ImageFit.Cover)
              } else {
                Column().width('100%').height(220 + this.topAvoidHeight)
                  .linearGradient({ angle: 135, colors: [['#a9233c', 0], ['#30233b', 1]] })
              }
              Column().width('100%').height(220 + this.topAvoidHeight)
                .linearGradient({ angle: 0, colors: [[TC.headerScrimTop(), 0], ['#00000000', 1]] })
              Row({ space: 14 }) {
                Column({ space: 1 }) {
                  Text(this.showingHistory ? this.historyDate.substring(5) : this.todayDate)
                    .fontSize(42).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
                  Text(this.showingHistory ? '历史' : '今日').fontSize(11).fontColor(TC.accentSoft())
                }
                Column({ space: 5 }) {
                  Text('每日推荐').fontSize(27).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
                  Text(this.showingHistory ? `${this.historyDate} 的历史日推` : '今日限定好歌推荐')
                    .fontSize(12).fontColor(TC.textBody())
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                if (this.showingHistory) {
                  Text('返回今日')
                    .fontSize(11)
                    .fontColor(TC.textOnAccent())
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .backgroundColor(TC.accent())
                    .borderRadius(14)
                    .onClick(() => this.backToToday())
                }
              }
              .padding({ left: 20, right: 20, bottom: 22 })
            }
            .width('100%').height(220 + this.topAvoidHeight)

            // 播放全部行本身就放在内容流里（跟随阶段零 JS 参与）
            this.FlowPlayAllRow()

            if (this.loading) {
              Column({ space: 12 }) {
                LoadingProgress().width(34).height(34).color(TC.accent())
                Text('正在加载每日推荐').fontSize(12).fontColor(TC.textTertiary())
              }
              .width('100%').height(180).justifyContent(FlexAlign.Center)
            } else if (this.songs.length === 0) {
              Column({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(35).fontColor([TC.textTertiary()])
                Text(this.message || '暂无每日推荐歌曲').fontSize(12).fontColor(TC.textTertiary())
                Text('请确认账号已经登录').fontSize(10).fontColor(TC.textQuaternary())
              }
              .width('100%').height(180).justifyContent(FlexAlign.Center)
            } else {
              List() {
                ForEach(this.songs, (item: songItemType, index: number) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      Text((index + 1).toString()).width(26).fontSize(12)
                        .fontColor(index < 3 ? TC.accent() : TC.textTertiary()).textAlign(TextAlign.Center)
                      Image(item.img).width(52).height(52).borderRadius(11).objectFit(ImageFit.Cover)
                      Column({ space: 5 }) {
                        Text(item.name).width('100%').fontSize(14).fontColor(TC.textBody()).maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Row({ space: 6 }) {
                          if (item.recommendTag && item.recommendTag.length > 0) {
                            Text(item.recommendTag).fontSize(9).fontColor(TC.accentSoft()).maxLines(1)
                              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                              .border({ width: 1, color: TC.accent() }).borderRadius(4)
                          }
                          Text(item.author).layoutWeight(1).fontSize(10).fontColor(TC.textTertiary()).maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                        }
                        .width('100%')
                      }
                      .layoutWeight(1).alignItems(HorizontalAlign.Start)
                      SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(23).fontColor([TC.textSecondary()])
                    }
                    .height(68).padding({ left: 12, right: 16 }).onClick(() => this.playAt(index))
                  }
                })
              }
              .width('100%').scrollBar(BarState.Off)
            }
            NoMoreFooter()
          }
          .width('100%').constraintSize({ minHeight: '100%' })
        }
        .width('100%').height('100%').scrollBar(BarState.Off)
        .onDidScroll(() => {
          const y = this.scroller.currentOffset().yOffset
          // 顶栏只用到 0~160 这段做渐显，钳住后长列表滚动时不再逐帧刷新页面
          const barOffset = y > 170 ? 170 : y
          if (barOffset !== this.scrollOffset) {
            this.scrollOffset = barOffset
          }
          const f = y >= this.freezeThreshold()
          if (f !== this.frozen) {
            this.frozen = f
          }
        })

        DetailTopBar({
          title: '每日推荐',
          scrollOffset: this.scrollOffset,
          shareEnabled: false
        }) {
          Row({ space: 8 }) {
            this.TopActionButton($r('sys.symbol.clock'), () => this.openHistory())
            this.TopActionButton($r('sys.symbol.hand_draw'), () => this.openHappySign())
          }
        }
        // 冻结后由浮层接管
        if (this.frozen) {
          this.FrozenPlayAllRow()
        }
      }
      .width('100%').height('100%').backgroundColor(TC.pageBackground())
    }
    .hideTitleBar(true)
    .bindSheet(this.historyVisible, this.skin_HistorySheet(), {
      height: '52%',
      backgroundColor: TC.sheetBackground(),
      showClose: false,
      dragBar: true,
      onDisappear: () => { this.historyVisible = false }
    })
  }
}
