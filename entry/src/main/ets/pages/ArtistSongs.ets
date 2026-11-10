import {
  ApiSong,
  ArtistSongsPageParam,
  ArtistSongsResponse,
  SharePageParam,
  mapApiSong
} from '../models/api'
import { songItemType } from '../models/music'
import { ApiClient } from '../services/ApiClient'
import { playerController } from '../services/PlayerController'
import { TC } from '../services/ThemeColors'
import { DetailTopBar } from '../components/DetailTopBar'
import { ShareSheet } from '../components/ShareSheet'

/**
 * 歌手全部歌曲：/artist/songs 偏移分页，拉到底继续加载；
 * 顶栏带搜索按钮，点开呼出搜索框（对已加载歌曲实时筛选，继续下滑加载更多即可扩大搜索范围）。
 */
@Component
export struct ArtistSongsPage {
  @StorageProp('skinVersion') skinVersionObs: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @Consume('topAvoidHeight') topAvoidHeight: number
  pageParam: ArtistSongsPageParam = { id: '', name: '' }

  @State songs: songItemType[] = []
  @State loading: boolean = false
  @State more: boolean = true
  @State total: number = 0
  @State message: string = ''
  @State searchVisible: boolean = false
  @State keyword: string = ''
  @State scrollOffset: number = 0
  @State shareVisible: boolean = false
  private offSet: number = 0
  private readonly pageSize: number = 30

  aboutToAppear(): void {
    this.total = this.pageParam.total || 0
    this.loadMore()
  }

  private async loadMore(): Promise<void> {
    if (this.loading || !this.more || !this.pageParam.id) {
      return
    }
    this.loading = true
    this.message = ''
    try {
      const response = await ApiClient.get<ArtistSongsResponse>('/artist/songs', [
        { key: 'id', value: this.pageParam.id },
        { key: 'limit', value: this.pageSize.toString() },
        { key: 'offset', value: this.offSet.toString() }
      ])
      if (response.code === 200) {
        const incoming = (response.songs || []).map((song: ApiSong) => mapApiSong(song))
        this.songs = this.songs.concat(incoming)
        this.offSet += incoming.length
        if (response.total) {
          this.total = response.total
        } else if (!this.total) {
          this.total = this.songs.length
        }
        this.more = response.more === true
      }
    } catch (error) {
      this.message = error instanceof Error ? error.message : '歌曲加载失败'
    } finally {
      this.loading = false
    }
  }

  private filtered(): songItemType[] {
    const key = this.keyword.trim().toLowerCase()
    if (!key) {
      return this.songs
    }
    return this.songs.filter((song: songItemType) =>
    `${song.name} ${song.author} ${song.album}`.toLowerCase().includes(key))
  }

  private async playAt(index: number): Promise<void> {
    const list = this.filtered()
    if (list.length === 0) {
      return
    }
    await playerController.setQueue(list, index, true)
    this.pageStack.pushPathByName('PlayPage', null)
  }

  private shareParam(): SharePageParam {
    return {
      type: 'artist',
      id: this.pageParam.id,
      name: this.pageParam.name || '歌手',
      img: this.pageParam.cover || '',
      author: `${this.total} 首歌曲`
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          Column().width('100%').height(this.topAvoidHeight + 54)

          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.play_fill')).fontSize(17).fontColor([TC.textPrimary()])
            Text(`${this.pageParam.name || '歌手'} · 共 ${this.total || this.songs.length} 首`)
              .fontSize(14).fontWeight(FontWeight.Bold).fontColor(TC.textPrimary())
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          }
          .width('100%').height(50).padding({ left: 18, right: 18 })
          .onClick(() => this.playAt(0))

          List() {
            ForEach(this.filtered(), (song: songItemType, index: number) => {
              ListItem() {
                Row({ space: 12 }) {
                  Text((index + 1).toString()).width(28).fontSize(12)
                    .fontColor(index < 3 ? TC.accentSoft() : TC.textTertiary())
                    .textAlign(TextAlign.Center)
                  Column({ space: 4 }) {
                    Row({ space: 6 }) {
                      Text(song.name).fontSize(14).fontColor(TC.textBody()).maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                      if (song.fee === 1) {
                        Text('VIP').fontSize(8).fontColor(TC.accentSoft())
                          .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                          .border({ width: 1, color: TC.accentSoft() }).borderRadius(3)
                      }
                    }
                    Text(`${song.author}${song.album ? ` · ${song.album}` : ''}`)
                      .fontSize(11).fontColor(TC.textTertiary()).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1).alignItems(HorizontalAlign.Start)
                  SymbolGlyph($r('sys.symbol.play_circle')).fontSize(21).fontColor([TC.textTertiary()])
                }
                .height(62).padding({ left: 12, right: 16 })
                .onClick(() => this.playAt(index))
              }
            }, (song: songItemType, index: number) => `${song.id}_${index}`)

            if (this.filtered().length === 0 && !this.loading) {
              ListItem() {
                Column({ space: 8 }) {
                  Text(this.keyword ? '没有找到匹配歌曲' : '暂无歌曲')
                    .fontSize(13).fontColor(TC.textTertiary())
                  if (this.keyword && this.more) {
                    Text('继续下滑加载更多歌曲后再试').fontSize(11).fontColor(TC.textQuaternary())
                  }
                }
                .width('100%').height(140).justifyContent(FlexAlign.Center)
              }
            }

            ListItem() {
              Row() {
                if (this.loading) {
                  LoadingProgress().width(24).height(24).color(TC.accent())
                } else {
                  Text(this.more ? '继续上滑加载更多' : '已经到底了')
                    .fontSize(11).fontColor(TC.textQuaternary())
                }
              }
              .width('100%').height(56).justifyContent(FlexAlign.Center)
            }
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .onScrollIndex((start: number) => { this.scrollOffset = start * 62 })
          .onReachEnd(() => this.loadMore())

          if (this.message) {
            Text(this.message).width('100%').fontSize(11).fontColor(TC.accentSoft())
              .textAlign(TextAlign.Center).padding({ bottom: 8 })
          }
        }
        .width('100%').height('100%')

        DetailTopBar({
          title: '全部歌曲',
          scrollOffset: this.scrollOffset,
          showSearch: true,
          searchMode: this.searchVisible,
          searchText: this.keyword,
          searchPlaceholder: '搜索歌曲 / 专辑',
          onSearchToggle: () => {
            this.searchVisible = !this.searchVisible
            if (!this.searchVisible) {
              this.keyword = ''
            }
          },
          onSearchTextChange: (value: string) => this.keyword = value,
          onShare: () => this.shareVisible = true
        })

        if (this.shareVisible) {
          ShareSheet({
            shareParam: this.shareParam(),
            visible: true,
            onClose: () => this.shareVisible = false
          })
        }
      }
      .width('100%').height('100%').backgroundColor(TC.pageBackground())
    }
    .hideTitleBar(true)
  }
}
