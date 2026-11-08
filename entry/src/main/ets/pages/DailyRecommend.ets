import { DailySongsResponse, mapApiSong, songItemType } from '../models'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { TC } from '../services/ThemeColors'

@Component
export struct DailyRecommendPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  @State songs: songItemType[] = []
  @State loading: boolean = true
  @State message: string = ''
  private todayDate: string = new Date().getDate().toString()

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

  build() {
    NavDestination() {
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
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([TC.textPrimary()])
          }
          .width(42).height(42).borderRadius(21).backgroundColor('rgba(0,0,0,0.35)')
          .justifyContent(FlexAlign.Center).position({ left: 14, top: this.topAvoidHeight + 14 })
          .onClick(() => this.pageStack.pop())
        }
        .width('100%').height(220 + this.topAvoidHeight)

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

        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress().width(34).height(34).color(TC.accent())
            Text('正在加载每日推荐').fontSize(12).fontColor(TC.textTertiary())
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
        } else if (this.songs.length === 0) {
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(35).fontColor([TC.textTertiary()])
            Text(this.message || '暂无每日推荐歌曲').fontSize(12).fontColor(TC.textTertiary())
            Text('请确认账号已经登录').fontSize(10).fontColor(TC.textQuaternary())
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
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
            ListItem() {
              Text('每日推荐会随你的喜好持续更新').width('100%').fontSize(11).fontColor(TC.textQuaternary())
                .textAlign(TextAlign.Center).padding(24)
            }
          }
          .layoutWeight(1).width('100%').scrollBar(BarState.Off)
        }
      }
      .width('100%').height('100%').backgroundColor(TC.pageBackground())
    }
    .hideTitleBar(true)
  }
}
