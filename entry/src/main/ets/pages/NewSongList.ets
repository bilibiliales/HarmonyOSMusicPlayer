import { mapApiSong, NewSongPageParam, songItemType, TopSongResponse } from '../models'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { TC } from '../services/ThemeColors'
import { DetailTopBar } from '../components/DetailTopBar'
import { NoMoreFooter } from '../components/NoMoreFooter'

@Component
export struct NewSongListPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  pageParam: NewSongPageParam = { type: 0, title: '全部' }
  @State songs: songItemType[] = []
  @State loading: boolean = true
  @State message: string = ''
  @State scrollOffset: number = 0
  /** 播放全部行是否已冻结在顶栏下沿（只在跨阈值时翻转）。 */
  @State private frozen: boolean = false
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.loadSongs()
  }

  private async loadSongs(): Promise<void> {
    this.loading = true
    this.message = ''
    try {
      const response = await ApiClient.get<TopSongResponse>('/top/song', [
        { key: 'type', value: this.pageParam.type.toString() }
      ])
      if (response.code === 200 && response.data?.length) {
        this.songs = response.data.map((item) => mapApiSong(item))
      } else {
        this.message = '暂无新歌数据'
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '新歌加载失败'
    } finally {
      this.loading = false
    }
  }

  private async playAt(index: number): Promise<void> {
    if (this.songs.length === 0) {
      return
    }
    await playerController.setQueue(this.songs, index, true)
  }

  private formatDuration(value: number): string {
    const total = Math.floor(value / 1000)
    const minutes = Math.floor(total / 60)
    const seconds = total % 60
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`
  }

  private actionBarBaseY(): number {
    return 210 + this.topAvoidHeight
  }

  private freezeThreshold(): number {
    return this.actionBarBaseY() - this.topAvoidHeight - 54
  }

  @Builder
  private PlayAllRow() {
    Row() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.play_fill')).fontSize(18).fontColor([TC.textPrimary()])
        Text(`播放全部 ${this.songs.length > 0 ? `(${this.songs.length})` : ''}`)
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor(TC.textPrimary())
      }
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20).fontColor([TC.textSecondary()])
        .onClick(() => this.loadSongs())
    }
    .height(56).padding({ left: 18, right: 18 })
    .onClick(() => this.playAt(0))
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

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Scroll(this.scroller) {
          Column() {
            Stack({ alignContent: Alignment.BottomStart }) {
              if (this.pageParam.cover && this.pageParam.cover.length > 0) {
                Image(this.pageParam.cover).width('100%').height(210 + this.topAvoidHeight).objectFit(ImageFit.Cover)
              } else {
                Column().width('100%').height(210 + this.topAvoidHeight)
                  .linearGradient({ angle: 135, colors: [['#6f2536', 0], ['#202039', 1]] })
              }
              Column().width('100%').height(210 + this.topAvoidHeight)
                .linearGradient({ angle: 0, colors: [[TC.headerScrimTop(), 0], ['#00000000', 1]] })
              Column({ space: 7 }) {
                Text(`${this.pageParam.title}新歌速递`)
                  .fontSize(27).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
                Text('新歌实时更新，点击即可播放')
                  .fontSize(12).fontColor(TC.textBody())
              }
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 20, right: 20, bottom: 22 })
            }
            .width('100%').height(210 + this.topAvoidHeight)

            // 播放全部行本身就放在内容流里（跟随阶段零 JS 参与）
            this.FlowPlayAllRow()

            if (this.loading) {
              Column({ space: 12 }) {
                LoadingProgress().width(34).height(34).color(TC.accent())
                Text('正在加载新歌').fontSize(12).fontColor(TC.textTertiary())
              }
              .width('100%').height(180).justifyContent(FlexAlign.Center)
            } else if (this.message.length > 0 && this.songs.length === 0) {
              Column({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(35).fontColor([TC.textTertiary()])
                Text(this.message).fontSize(12).fontColor(TC.textTertiary())
              }
              .width('100%').height(180).justifyContent(FlexAlign.Center)
            } else {
              List() {
                ForEach(this.songs, (item: songItemType, index: number) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      Text((index + 1).toString()).width(28).fontSize(12)
                        .fontColor(index < 3 ? TC.accent() : TC.textTertiary()).textAlign(TextAlign.Center)
                      Image(item.img).width(52).height(52).borderRadius(11).objectFit(ImageFit.Cover)
                      Column({ space: 5 }) {
                        Text(item.name).width('100%').fontSize(14).fontColor(TC.textBody()).maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(`${item.author}${item.album ? ` · ${item.album}` : ''}`)
                          .width('100%').fontSize(10).fontColor(TC.textTertiary()).maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .layoutWeight(1).alignItems(HorizontalAlign.Start)
                      Text(this.formatDuration(item.duration || 0)).fontSize(10).fontColor(TC.textQuaternary())
                      SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(18).fontColor([TC.textTertiary()])
                    }
                    .height(68).padding({ left: 12, right: 16 })
                    .onClick(() => this.playAt(index))
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
          title: `${this.pageParam.title}新歌速递`,
          scrollOffset: this.scrollOffset,
          shareEnabled: false
        })
        // 冻结后由浮层接管
        if (this.frozen) {
          this.FrozenPlayAllRow()
        }
      }
      .width('100%').height('100%').backgroundColor(TC.pageBackground())
    }
    .hideTitleBar(true)
  }
}
