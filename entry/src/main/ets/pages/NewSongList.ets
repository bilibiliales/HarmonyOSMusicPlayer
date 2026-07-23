import { mapApiSong, NewSongPageParam, songItemType, TopSongResponse } from '../models'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'

@Component
export struct NewSongListPage {
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  pageParam: NewSongPageParam = { type: 0, title: '全部' }
  @State songs: songItemType[] = []
  @State loading: boolean = true
  @State message: string = ''

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

  build() {
    NavDestination() {
      Column() {
        Stack({ alignContent: Alignment.BottomStart }) {
          if (this.pageParam.cover && this.pageParam.cover.length > 0) {
            Image(this.pageParam.cover).width('100%').height(210 + this.topAvoidHeight).objectFit(ImageFit.Cover)
          } else {
            Column().width('100%').height(210 + this.topAvoidHeight)
              .linearGradient({ angle: 135, colors: [['#6f2536', 0], ['#202039', 1]] })
          }
          Column().width('100%').height(210 + this.topAvoidHeight)
            .linearGradient({ angle: 0, colors: [['#121215', 0], ['rgba(18,18,21,0.08)', 1]] })
          Column({ space: 7 }) {
            Text(`${this.pageParam.title}新歌速递`)
              .fontSize(27).fontWeight(FontWeight.Bold).fontColor('#ffffff')
            Text('新歌实时更新，点击即可播放')
              .fontSize(12).fontColor('#d0d0d5')
          }
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 20, right: 20, bottom: 22 })

          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor(['#ffffff'])
          }
          .width(42).height(42).borderRadius(21).backgroundColor('rgba(0,0,0,0.35)')
          .justifyContent(FlexAlign.Center)
          .position({ left: 14, top: this.topAvoidHeight + 14 })
          .onClick(() => this.pageStack.pop())
        }
        .width('100%').height(210 + this.topAvoidHeight)

        Row() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.play_fill')).fontSize(18).fontColor(['#ffffff'])
            Text(`播放全部 ${this.songs.length > 0 ? `(${this.songs.length})` : ''}`)
              .fontSize(14).fontWeight(FontWeight.Medium).fontColor('#ffffff')
          }
          .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20).fontColor(['#8a8a92'])
            .onClick(() => this.loadSongs())
        }
        .height(56).padding({ left: 18, right: 18 })
        .onClick(() => this.playAt(0))

        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress().width(34).height(34).color('#ef233c')
            Text('正在加载新歌').fontSize(12).fontColor('#77777f')
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
        } else if (this.message.length > 0 && this.songs.length === 0) {
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(35).fontColor(['#77777f'])
            Text(this.message).fontSize(12).fontColor('#77777f')
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.songs, (item: songItemType, index: number) => {
              ListItem() {
                Row({ space: 12 }) {
                  Text((index + 1).toString()).width(28).fontSize(12)
                    .fontColor(index < 3 ? '#ef4058' : '#66666e').textAlign(TextAlign.Center)
                  Image(item.img).width(52).height(52).borderRadius(11).objectFit(ImageFit.Cover)
                  Column({ space: 5 }) {
                    Text(item.name).width('100%').fontSize(14).fontColor('#eeeeF1').maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${item.author}${item.album ? ` · ${item.album}` : ''}`)
                      .width('100%').fontSize(10).fontColor('#77777f').maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Text(this.formatDuration(item.duration || 0)).fontSize(10).fontColor('#66666e')
                  SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(18).fontColor(['#77777f'])
                }
                .height(68).padding({ left: 12, right: 16 })
                .onClick(() => this.playAt(index))
              }
            })
            ListItem() {
              Text('已加载全部新歌').width('100%').fontSize(11).fontColor('#5f5f67')
                .textAlign(TextAlign.Center).padding(24)
            }
          }
          .layoutWeight(1).width('100%').scrollBar(BarState.Off)
        }
      }
      .width('100%').height('100%').backgroundColor('#121215')
    }
    .hideTitleBar(true)
  }
}
