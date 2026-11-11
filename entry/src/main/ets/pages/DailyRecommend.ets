import { DailySongsResponse, mapApiSong, songItemType } from '../models'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { TC } from '../services/ThemeColors'
import { DetailTopBar } from '../components/DetailTopBar'
import { NoMoreFooter } from '../components/NoMoreFooter'

@Component
export struct DailyRecommendPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @State songs: songItemType[] = []
  @State loading: boolean = true
  @State message: string = ''
  @State scrollOffset: number = 0
  private todayDate: string = new Date().getDate().toString()
  private scroller: Scroller = new Scroller()

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
      } else {
        this.message = '暂无每日推荐歌曲'
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '每日推荐加载失败'
    } finally {
      this.loading = false
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

  private stickyOffset(): number {
    return Math.max(0, this.scrollOffset - (this.actionBarBaseY() - this.topAvoidHeight - 54))
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

  /** 唯一的播放全部行：滚到顶栏下沿后冻结（Excel 冻结行）。 */
  @Builder
  private StickyPlayAllRow() {
    Column() {
      this.PlayAllRow()
    }
    .width('100%')
    .position({ x: 0, y: this.actionBarBaseY() })
    .offset({ y: -this.scrollOffset + this.stickyOffset() })
    .backgroundColor(Color.Transparent)
    .backdropBlur(this.stickyOffset() > 0 ? 30 : 0)
    .zIndex(3)
  }

  build() {
    NavDestination() {
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
                  Text(this.todayDate).fontSize(42).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
                  Text('今日').fontSize(11).fontColor(TC.accentSoft())
                }
                Column({ space: 5 }) {
                  Text('每日推荐').fontSize(27).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
                  Text('今日限定好歌推荐').fontSize(12).fontColor(TC.textBody())
                }
                .alignItems(HorizontalAlign.Start)
              }
              .padding({ left: 20, bottom: 22 })
            }
            .width('100%').height(220 + this.topAvoidHeight)

            // 播放全部行由 StickyPlayAllRow 绘制，这里只留等高占位
            Column().width('100%').height(56)

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
          .width('100%').constraintSize({ minHeight: 640 })
        }
        .width('100%').height('100%').scrollBar(BarState.Off)
        .onDidScroll(() => { this.scrollOffset = this.scroller.currentOffset().yOffset })

        DetailTopBar({
          title: '每日推荐',
          scrollOffset: this.scrollOffset,
          shareEnabled: false
        })
        this.StickyPlayAllRow()
      }
      .width('100%').height('100%').backgroundColor(TC.pageBackground())
    }
    .hideTitleBar(true)
  }
}
